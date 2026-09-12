--[[ rick.lua  -  CC: Tweaked video player (multi-video)
Plays <name>.data on a monitor and <name>.dfpwm through a speaker, in a loop.
Usage:  rick [name]
  - no name: picks the only video, or shows a numbered picker if several
  - "rick intro" plays intro.data / intro.dfpwm
Controls on the computer keyboard:
  P - pause / resume
  [ - volume down       ] - volume up
  Q - quit
Photo quality: per-frame adaptive 16-colour palette (monitor palette is set
per frame before drawing). Centres the picture on whatever monitor it finds. ]]

local name = ...
local W, H, FPS, PAL, frames

local function loadVideo(n)
    local f = assert(fs.open(n .. ".data", "r"), n .. ".data not found")
    local content = f.readAll()
    f.close()

    content = content:gsub("\r\n", "\n")
    local ws, hs, fps_s, pal_s, body =
        content:match("^(%d+) (%d+) (%d+) (%d+)\n(.*)$")
    if not ws then
        print(n .. ".data size: " .. #content .. " bytes")
        print("first line: " .. (content:match("^[^\n]+") or "(end of file)"))
    end
    assert(ws, "bad " .. n .. ".data header (want: W H FPS [0/1])")

    local vid = {
        W = tonumber(ws), H = tonumber(hs),
        FPS = tonumber(fps_s), PAL = tonumber(pal_s), frames = {},
    }
    for part in body:gmatch("(.-)\n\n") do
        local lines = {}
        for line in part:gmatch("[^\n]+") do
            lines[#lines + 1] = line
        end
        local pal
        if vid.PAL == 1 then
            pal = {}
            for pr = 1, 4 do
                local ln = lines[pr]
                for c = 1, 4 do
                    local tok = ln:sub((c - 1) * 7 + 1, (c - 1) * 7 + 6)
                    pal[(pr - 1) * 4 + c] = {
                        tonumber(tok:sub(1, 2), 16) / 255,
                        tonumber(tok:sub(3, 4), 16) / 255,
                        tonumber(tok:sub(5, 6), 16) / 255,
                    }
                end
            end
        end
        local rows = {}
        for i = (vid.PAL == 1 and 5 or 1), #lines do
            rows[#rows + 1] = lines[i]
        end
        vid.frames[#vid.frames + 1] = { rows = rows, pal = pal }
    end
    assert(vid.frames[1] and vid.frames[1].rows[1]
           and #vid.frames[1].rows[1] == vid.W, "frame size mismatch")
    return vid
end

if not name then
    local list = {}
    for f in fs.find("*.data") do
        list[#list + 1] = f:sub(1, #f - 5)
    end
    if #list == 0 then
        error("no .data files here - run install first")
    elseif #list == 1 then
        name = list[1]
    else
        term.clear()
        term.setTextColor(colors.green)
        term.setCursorPos(1, 1)
        term.write("SELECT VIDEO   (1-" .. math.min(9, #list) .. ", Q = quit)")
        for i, nm in ipairs(list) do
            term.setCursorPos(1, 2 + i)
            term.setTextColor(colors.white)
            term.write((i <= 9 and (i .. ". ") or "   ") .. nm)
        end
        local picked
        while not picked do
            local ev = {os.pullEvent()}
            if ev[1] == "key" then
                if ev[2] == keys.q then return end
                local idx = ev[2] - keys.one + 1
                if idx >= 1 and idx <= math.min(9, #list) then
                    picked = idx
                end
            end
        end
        name = list[picked]
    end
end

local vid = loadVideo(name)
W, H, FPS, PAL = vid.W, vid.H, vid.FPS, vid.PAL
frames = vid.frames

local monitor = peripheral.find("monitor")
assert(monitor, "No monitor found. Place monitors then run: rick.")
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
local function applyPalette(idx)
    local pal = frames[idx].pal
    if not pal then return end
    for i = 1, 16 do
        local c = pal[i]
        monitor.setPaletteColor(2 ^ (i - 1), c[1], c[2], c[3])
    end
end
local function drawIdx(idx)
    applyPalette(idx)
    local rows = frames[idx].rows
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
    term.write(name .. "   " .. m1 .. ":" .. rs1 .. " / " .. m2 .. ":" .. rs2)
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
        return assert(io.open(name .. ".dfpwm", "rb"), name .. ".dfpwm not found"),
               dfpwm.make_decoder()
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

print("Now playing " .. name .. " - P pause, [ ] volume, Q quit")
parallel.waitForAll(videoThread, audioThread)
