-- Flare: feed mouse clicks to the melonamin.flare shell plugin.
--
-- Wayland gives no client a way to observe input it does not have focus for,
-- so the compositor has to do the observing. In normal mode these binds are
-- non-consuming: Hyprland runs the dispatcher *and* delivers the click to the
-- window under the pointer, so highlighting never costs you a click.
--
-- Presentation mode does not touch these binds: the shell puts an
-- input-accepting overlay on top instead, which is what stops clicks reaching
-- the apps underneath.
--
-- The shell plugin loads this itself with `hyprctl eval` and calls
-- flare.install(). Nothing needs to be added to hyprland.lua.

_G.flare = _G.flare or {}
local F = _G.flare

local BUTTONS = {
  { key = "mouse:272", name = "primary" },
  { key = "mouse:273", name = "secondary" },
  { key = "mouse:274", name = "middle" },
}

-- Sampling rate for the drag trail, and how far the pointer must travel
-- before the next dot. Distance spacing (rather than time) keeps the trail
-- even regardless of drag speed.
local DRAG_INTERVAL_MS = 32
local DRAG_MIN_DISTANCE = 24

-- ---------------------------------------------------------------- transport

-- The fallback shells out once per event, which costs ~19ms of `qs ipc`
-- startup: fine for a click, wasteful for a 30 Hz drag trail. The fast path is
-- a FIFO the plugin drains, at well under a millisecond.
-- No fallback to /tmp on purpose: it is world-writable, so anyone could
-- pre-create the FIFO path and read every click position. Without
-- XDG_RUNTIME_DIR there is simply no fast path, which is also what the shell
-- half does.
local RUNTIME = os.getenv("XDG_RUNTIME_DIR")
local FIFO_PATH = RUNTIME and (RUNTIME .. "/flare.fifo") or nil
local ACK_PATH = RUNTIME and (RUNTIME .. "/flare.ack") or nil

-- Writing to a FIFO blocks once its buffer fills, and this runs on the
-- compositor's thread, so a stalled reader must never be able to freeze
-- Hyprland. The plugin stamps an advancing counter into ACK_PATH once a second
-- from its own event loop; if that stops advancing we abandon the FIFO after
-- at most CHECK_EVERY * STALE_LIMIT writes -- a few KB, far below the 64K
-- pipe buffer.
local CHECK_EVERY = 100
local STALE_LIMIT = 2
local REOPEN_EVERY = 20

local fifo = nil
local sinceCheck = 0
local sinceReopen = REOPEN_EVERY
local lastAck = nil
local staleCount = 0

local function openFifo()
  if not FIFO_PATH then return nil end
  -- "r+" is O_RDWR: opening a FIFO this way never blocks even with no reader
  -- attached, and holding a read end means a write never raises SIGPIPE.
  local handle = io.open(FIFO_PATH, "r+")
  if not handle then return nil end
  -- ...but it opens a regular file squatting on the path just as happily, and
  -- writes to one neither block nor error, so every event would be appended to
  -- it and the IPC fallback would never engage. A FIFO cannot seek; a handle
  -- that can is not our pipe.
  if handle:seek("cur") then
    handle:close()
    return nil
  end
  handle:setvbuf("line")
  return handle
end

local function dropFifo()
  if fifo then fifo:close() end
  fifo = nil
  lastAck = nil
  staleCount = 0
  sinceCheck = 0
end

local function readerAlive()
  if not ACK_PATH then return false end
  local f = io.open(ACK_PATH, "r")
  if not f then return false end
  local tick = f:read("*l")
  f:close()
  if tick == nil then return false end

  if tick == lastAck then
    staleCount = staleCount + 1
    return staleCount < STALE_LIMIT
  end

  lastAck = tick
  staleCount = 0
  return true
end

local function send(line)
  if not FIFO_PATH then
    hl.exec_cmd("omarchy-shell -q flare event " .. string.format("%q", line))
    return
  end

  if not fifo then
    sinceReopen = sinceReopen + 1
    if sinceReopen >= REOPEN_EVERY then
      sinceReopen = 0
      fifo = openFifo()
    end
  end

  if fifo then
    sinceCheck = sinceCheck + 1
    if sinceCheck >= CHECK_EVERY then
      sinceCheck = 0
      if not readerAlive() then dropFifo() end
    end
  end

  if fifo then
    local ok = pcall(function() fifo:write(line .. "\n") end)
    if ok then return end
    dropFifo()
  end

  hl.exec_cmd("omarchy-shell -q flare event " .. string.format("%q", line))
end

local function pulse(kind, x, y)
  send(string.format("%s %.1f %.1f", kind, x, y))
end

-- Read the pointer inside the compositor at the instant of the click, so the
-- position is exact and costs no IPC round trip.
local function emit(kind)
  local at = hl.get_cursor_pos()
  pulse(kind, at.x, at.y)
  return at
end

-- -------------------------------------------------------------------- drag

-- Hyprland's Lua timers cannot be stopped once created, so the trail is a
-- chain of one-shots guarded by a generation counter: bumping the generation
-- retires every in-flight link. Any release retires the chain, whichever
-- button sent it -- tracking a held count instead leaks when a release never
-- arrives.
local generation = 0
local lastX, lastY = 0, 0
local samples = 0
local MAX_SAMPLES = math.floor(30000 / DRAG_INTERVAL_MS)

local function sample(forGeneration)
  if forGeneration ~= generation then return end

  samples = samples + 1
  if samples > MAX_SAMPLES then
    generation = generation + 1
    return
  end

  local at = hl.get_cursor_pos()
  local dx, dy = at.x - lastX, at.y - lastY
  if (dx * dx + dy * dy) >= (DRAG_MIN_DISTANCE * DRAG_MIN_DISTANCE) then
    lastX, lastY = at.x, at.y
    pulse("drag", at.x, at.y)
  end

  hl.timer(function() sample(forGeneration) end,
    { timeout = DRAG_INTERVAL_MS, type = "oneshot" })
end

local function beginDrag(at)
  -- Anchor on the press point: the press pulse already marks it, so the first
  -- drag dot lands one threshold away rather than on top of it.
  generation = generation + 1
  samples = 0
  lastX, lastY = at.x, at.y
  sample(generation)
end

local function endDrag()
  generation = generation + 1
end

-- ------------------------------------------------------------------ install

-- Binds are registered once and never swapped or unbound. Swapping them at
-- runtime (to make presentation mode consume clicks) crashes the compositor
-- inside CLuaKeybind::push, so presentation mode is done with an
-- input-accepting overlay in the shell instead, and these stay put.
local function add(key, options, handler)
  hl.bind(key, handler, options)
end

-- `force` is for the config-reload path: Hyprland drops every bind on reload,
-- so the flag has to be cleared before they can be put back. Nothing is
-- unbound -- the old handles are simply forgotten.
function F.install(shortcut, force)
  if force then F.installed = false end
  if F.installed then return "already" end
  F.installed = true

  for _, button in ipairs(BUTTONS) do
    add(button.key, { mouse = true, non_consuming = true },
      function() beginDrag(emit(button.name .. "-press")) end)
    add(button.key, { mouse = true, non_consuming = true, release = true },
      function() emit(button.name .. "-release"); endDrag() end)
  end

  -- Described on purpose: omarchy's keybindings cheatsheet lists any bind that
  -- carries one, which is how this stays discoverable. The mouse binds are
  -- left undescribed so they do not clutter it.
  if shortcut and shortcut ~= "" then
    add(shortcut, { description = "Flare: presentation mode" },
      function() send("!toggle") end)
  end

  return "installed"
end
