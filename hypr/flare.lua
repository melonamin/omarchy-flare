-- Flare: feed mouse clicks to the melonamin.flare shell plugin.
--
-- Wayland gives no client a way to observe input it does not have focus for,
-- so the compositor has to do the observing. These binds are non-consuming:
-- Hyprland runs the dispatcher *and* delivers the click to the window under
-- the pointer, so highlighting never costs you a click.
--
-- Load it from ~/.config/hypr/hyprland.lua with:
--   require("hypr.flare")

local BUTTONS = {
  { key = "mouse:272", name = "primary" },
  { key = "mouse:273", name = "secondary" },
  { key = "mouse:274", name = "middle" },
}

-- Sampling rate for the drag trail, and how far the pointer must travel
-- before the next dot. Distance spacing (rather than time) keeps the trail
-- even regardless of drag speed -- see DragThrottle in the macOS build (§6.6).
local DRAG_INTERVAL_MS = 32
local DRAG_MIN_DISTANCE = 24

-- Transport. The fallback shells out once per event, which costs ~20ms of
-- `qs ipc` startup: fine for a click, wasteful for a 30 Hz drag trail. The
-- fast path is a FIFO the plugin drains, at well under a millisecond.
local RUNTIME = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local FIFO_PATH = RUNTIME .. "/flare.fifo"
local ACK_PATH = RUNTIME .. "/flare.ack"

-- Writing to a FIFO blocks once its buffer fills, and this runs on the
-- compositor's thread, so a stalled reader must never be able to freeze
-- Hyprland. The plugin stamps an advancing counter into ACK_PATH once a
-- second from its own event loop; if that stops advancing we abandon the FIFO
-- after at most CHECK_EVERY * STALE_LIMIT writes -- a few KB, far below the
-- 64K pipe buffer.
local CHECK_EVERY = 100
local STALE_LIMIT = 2
local REOPEN_EVERY = 20

local fifo = nil
local sinceCheck = 0
local sinceReopen = REOPEN_EVERY
local lastAck = nil
local staleCount = 0

local function openFifo()
  -- "r+" is O_RDWR: opening a FIFO this way never blocks even with no reader
  -- attached, and holding a read end means a write never raises SIGPIPE.
  local handle = io.open(FIFO_PATH, "r+")
  if handle then handle:setvbuf("line") end
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

local function send(kind, x, y)
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
    local ok = pcall(function()
      fifo:write(string.format("%s %.1f %.1f\n", kind, x, y))
    end)
    if ok then return end
    dropFifo()
  end

  hl.exec_cmd(string.format(
    "omarchy-shell -q flare pulse %s %.1f %.1f", kind, x, y))
end

-- Read the pointer inside the compositor at the instant of the click, so the
-- position is exact and costs no IPC round trip.
local function emit(kind)
  local at = hl.get_cursor_pos()
  send(kind, at.x, at.y)
  return at
end

-- Drag tracking. Hyprland's Lua timers cannot be stopped once created, so the
-- trail is a chain of one-shots guarded by a generation counter: bumping the
-- generation retires every in-flight link.
--
-- Any release retires the chain, whichever button sent it. Tracking a held
-- count instead looks tidier but leaks: a press whose release never arrives
-- (it happens -- a click can land on a surface that swallows the release)
-- pins the count above zero and the chain samples forever.
local generation = 0
local lastX, lastY = 0, 0
local samples = 0

-- A drag that somehow never sees its release still has to end. No real drag
-- runs this long, so the cap only ever fires on a lost release.
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
    send("drag", at.x, at.y)
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

for _, button in ipairs(BUTTONS) do
  hl.bind(button.key, function() beginDrag(emit(button.name .. "-press")) end,
    { mouse = true, non_consuming = true })

  hl.bind(button.key, function() emit(button.name .. "-release"); endDrag() end,
    { mouse = true, non_consuming = true, release = true })
end
