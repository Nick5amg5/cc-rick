--[[ rick.lua  -  CC: Tweaked video player
Plays rick.data on a monitor and rick.dfpwm through a speaker, in a loop.
Centres the picture on whatever monitor size it finds.

Usage:  rick [side]
Controls on the computer keyboard:
  P - pause / resume
  [ - volume down       ] - volume up
  Q - quit
The computer screen shows a progress bar while the monitor plays the video.
You can also hold Ctrl+T to quit. ]]

local side = ...
local W, H, FPS = 121, 52, 12

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
pcall(monitor.setTextScale, 0.5)
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

local paused = false
local quit = false
local volume = 1.2                  -- 0 .. 3, use [] to change
local framesShown = 0
local lastGuiAt = -1

local function drawGui(force)
    if not force and framesShown - lastGuiAt < 10 then return end
    lastGuiAt = framesShown
    local total = #frames / FPS
    local frac = framesShown / #frames
    local t = framesShown / FPS
    local m1, r1 = math.floor(t / 60), math.floor(t) % 60
    local m2, r2 = math.floor(total / 60), math.floor(total) % 60
    local rs1 = r1 < 10 and ("0" .. r1) or tostring(r1)
    local rs2 = r2 < 10 and ("0" .. r2) or tostring(r2)
    local sw = term.getSize()
    local barW = math.max(10, sw - 2)
    local filled = math.floor(frac * barW)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    term.write("CC RICK   " .. m1 .. ":" .. rs1 .. " / " .. m2 .. ":" .. rs2)
    term.setCursorPos(1, 3)
    term.write(string.rep("=", filled) .. string.rep("-", barW - filled))
    term.setCursorPos(1, 5)
    term.write(math.floor(frac * 100) .. "%")
    term.setCursorPos(1, 7)
    if paused then
        term.write("PAUSED - press P to resume")
    else
        term.write("P = pause / resume   Q = quit")
    end
    local mw2, mh2 = monitor.getSize()
    term.setCursorPos(1, 9)
    term.write("screen " .. mw2 .. "x" .. mh2 .. " cells")
    term.setCursorPos(1, 11)
    term.write("volume " .. math.floor(volume * 10) / 10 .. "   [ - / = ]")
end
drawGui(true)

local function videoThread()
    local step = FPS / 20
    local acc = 0
    local timerId = os.startTimer(0.05)
    while not quit do
        local ev = {os.pullEvent()}
        if ev[1] == "timer" and ev[2] == timerId then
            timerId = os.startTimer(0.05)
            if not paused then
                acc = acc + step
                if acc >= 1 then
                    local n = math.floor(acc)
                    acc = acc - n
                    lastIdx = (lastIdx - 1 + n) % #frames + 1
                    drawIdx(lastIdx)
                    framesShown = framesShown + n
                    drawGui(false)
                end
            end
        elseif ev[1] == "key" then
            if ev[2] == keys.p then
                paused = not paused
                drawGui(true)
            elseif ev[2] == keys.q then
                quit = true
            elseif ev[2] == keys.minus then
                volume = math.max(0, volume - 0.1)
                drawGui(true)
            elseif ev[2] == keys.equals then
                volume = math.min(3, volume + 0.1)
                drawGui(true)
            end
        end
    end
end

local function audioThread()
    local speaker = peripheral.find("speaker")
    if not speaker then
        print("No speaker found - video only.")
        while true do sleep(0) end
    end
    local dfpwm = require "cc.audio.dfpwm"
    local function openTrack()
        return assert(io.open("rick.dfpwm", "rb"), "rick.dfpwm not found"), dfpwm.make_decoder()
    end
    local track, decoder = openTrack()
    while not quit do
        if paused then
            sleep(0)
        else
            local chunk = track:read(16 * 1024)
            if not chunk or #chunk == 0 then
                track:close()
                track, decoder = openTrack()
            else
                local buffer = decoder(chunk)
                while not speaker.playAudio(buffer, volume) and not quit do
                    os.pullEvent("speaker_audio_empty")
                end
            end
        end
    end
    track:close()
end

print("Now playing - P pause, [ ] volume, Q quit")
parallel.waitForAll(videoThread, audioThread)
