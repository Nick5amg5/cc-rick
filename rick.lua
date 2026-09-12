--[[ rick.lua  -  CC: Tweaked video player
Plays rick.data on a monitor and rick.dfpwm through a speaker, in a loop.
Centres and letterboxes the picture on whatever monitor size it finds.

Usage:  rick [side]
Run without a side to auto-detect any connected monitor. Pass a side to pick
a specific one (e.g.  rick right  ). Starts video + audio together.
Hold Ctrl+T to quit. ]]

local side = ...
local W, H, FPS = 29, 11, 15

-- Load and cache frames as blit-ready colour rows.
local f = assert(fs.open("rick.data", "r"), "rick.data not found")
local content = f.readAll()
f.close()

local ws, hs, fps_s, body = content:match("^(%d+) (%d+) (%d+)\n(.*)$")
assert(ws, "bad rick.data header")
assert(tonumber(ws) == W and tonumber(hs) == H, "rick.data size does not match this player")

local frames = {}
for part in body:gmatch("(.-)\n\n") do
    local rows = {}
    for line in part:gmatch("[^\n]+") do
        rows[#rows + 1] = line
    end
    frames[#frames + 1] = rows
end
assert(#frames > 0 and frames[1][1] and #frames[1][1] == W, "frame size mismatch")

local monitor = side and peripheral.wrap(side) or peripheral.find("monitor")
assert(monitor, "No monitor found. Place monitors then run: rick [side].")
monitor.setBackgroundColor(colors.black)
monitor.clear()

local spaces = (" "):rep(W)
local startX, startY
local function computeOffsets()
    local mw, mh = monitor.getSize()
    startX = math.floor((mw - W) / 2) + 1
    startY = math.floor((mh - H) / 2) + 1
end
computeOffsets()

local lastIdx = 1
local function drawIdx(idx)
    local rows = frames[idx]
    for y = 1, H do
        monitor.setCursorPos(startX, startY + y - 1)
        monitor.blit(spaces, rows[y], rows[y])
    end
end
drawIdx(1)

local function videoThread()
    -- Advance one frame per (20/FPS) ticks using a fractional accumulator.
    local step = FPS / 20
    local acc = 0
    while true do
        acc = acc + step
        if acc >= 1 then
            local n = math.floor(acc)
            acc = acc - n
            lastIdx = (lastIdx - 1 + n) % #frames + 1
            drawIdx(lastIdx)
        end
        sleep(0) -- yield one server tick
    end
end

local function audioThread()
    local speaker = peripheral.find("speaker")
    local dfpwm = require "cc.audio.dfpwm"
    if not speaker then
        print("No speaker found - playing video only.")
        while true do sleep(0) end
    end
    while true do
        local track = assert(io.open("rick.dfpwm", "rb"), "rick.dfpwm not found")
        local decoder = dfpwm.make_decoder()
        while true do
            local chunk = track:read(16 * 1024)
            if not chunk or #chunk == 0 then break end
            local buffer = decoder(chunk)
            while not speaker.playAudio(buffer) do
                os.pullEvent("speaker_audio_empty")
            end
        end
        track:close()
    end
end

print("Now playing: " .. #frames .. " frames at " .. FPS .. " fps")
print("Terminate with Ctrl+T")
parallel.waitForAll(videoThread, audioThread)
