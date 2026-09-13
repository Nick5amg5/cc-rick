--[[ rick.lua  -  CC: Tweaked video player (multi-video)
Plays <name>.data on a monitor and <name>.dfpwm through a speaker, in a loop.
Usage:  rick [name]
  - no name: picks the only video, or shows a numbered picker if several
  - "rick intro" plays intro.data / intro.dfpwm
  - "rick list" lists every installed track (name, size, resolution, etc.)
Controls on the computer keyboard:
  P - pause / resume       Q - quit
  [ - volume down     ] - volume up
  , - audio earlier   . - audio later   (persisted to rick.sync)
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

local function listInstalled()
    term.clear()
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, 1)
    term.write("INSTALLED TRACKS")
    local names = {}
    for _, f in ipairs(fs.find("*.data")) do
        names[#names + 1] = f:sub(1, #f - 5)
    end
    table.sort(names)
    if #names == 0 then
        error("no .data files here - run install first")
    end
    local total = 0
    for i, nm in ipairs(names) do
        local size = fs.getSize(nm .. ".data") or 0
        total = total + size
        local f = fs.open(nm .. ".data", "r")
        if not f then
            term.setTextColor(colors.red)
            term.setCursorPos(1, 2 + i)
            term.write(nm .. "   (unreadable)")
        else
            local hdr = f.readLine()
            f.close()
            local Ws, Hs, fpsS, palS = hdr:match("(%d+) (%d+) (%d+) (%d+)")
            if not Ws then
                term.setTextColor(colors.red)
                term.setCursorPos(1, 2 + i)
                term.write(nm .. "   (bad header)")
            else
                local W, H, FPS, PAL = tonumber(Ws), tonumber(Hs),
                                       tonumber(fpsS), tonumber(palS)
                local perFrame = H * (W + 1) + 1
                if PAL == 1 then perFrame = perFrame + 4 * 28 end
                local estFrames = math.max(1, math.floor(size / perFrame))
                local dur = estFrames / FPS
                term.setTextColor(colors.white)
                term.setCursorPos(1, 2 + i)
                term.write(nm)
                term.setCursorPos(16, 2 + i)
                term.write(string.format("%d x %d @%d", W, H, FPS)
                           .. (PAL == 1 and " pal" or "")) 
                term.setCursorPos(35, 2 + i)
                term.write(string.format("%.1fMB", size / 1048576))
                term.setCursorPos(45, 2 + i)
                term.write(string.format("%d:%02d", math.floor(dur / 60), dur % 60))
            end
        end
    end
    local free = fs.getFreeSpace("/") or 0
    local totalCap = total + free
    term.setTextColor(colors.white)
    term.setCursorPos(1, 3 + #names)
    term.write(string.format("used %.1f MB of %.1f MB, free %.1f MB",
                             total / 1048576, totalCap / 1048576, free / 1048576))
    term.setCursorPos(1, 5 + #names)
    term.setTextColor(colors.gray)
    term.write("press any key to exit")
    os.pullEvent("key")
    return 0
end

if name == "list" then
    return listInstalled()
end

if not name then
    local list = {}
    for _, f in ipairs(fs.find("*.data")) do
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

local monitor = peripheral.find("monitor")
assert(monitor, "No monitor found. Place monitors then run: rick.")
pcall(monitor.setTextScale, 0.5)
monitor.setBackgroundColor(colors.black)
monitor.clear()

local logo
do
    local lf = fs.open("logo.data", "r")
    if lf then
        local content = lf.readAll()
        lf.close()
        content = content:gsub("\r\n", "\n")
        local ws, hs, palS, body = content:match("^(%d+) (%d+) (%d+) (%d+)\n(.*)$")
        if ws then
            local lw, lh = tonumber(ws), tonumber(hs)
            local part = body:match("^(.-)\n\n")
            if part and lw and lh and lw > 0 and lh > 0 then
                local lines = {}
                for line in part:gmatch("[^\n]+") do lines[#lines + 1] = line end
                local pal
                if tonumber(palS) == 1 then
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
                for i = (tonumber(palS) == 1 and 5 or 1), #lines do
                    rows[#rows + 1] = lines[i]
                end
                if #rows == lh and rows[1] and #rows[1] == lw then
                    logo = { w = lw, h = lh, rows = rows, pal = pal }
                end
            end
        end
    end
end

local function showLogo(titleText, subtitleText)
    local mw, mh = monitor.getSize()
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
    if logo then
        if logo.pal then
            for i = 1, 16 do
                local c = logo.pal[i]
                monitor.setPaletteColor(2 ^ (i - 1), c[1], c[2], c[3])
            end
        end
        local sx = math.floor((mw - logo.w) / 2) + 1
        local sy = math.floor((mh - logo.h) / 2) + 1
        local blank = (" "):rep(logo.w)
        for y = 1, logo.h do
            monitor.setCursorPos(sx, sy + y - 1)
            monitor.blit(blank, logo.rows[y], logo.rows[y])
        end
        local sub = subtitleText or ""
        if sub ~= "" then
            monitor.setBackgroundColor(colors.black)
            monitor.setTextColor(colors.gray)
            monitor.setCursorPos(math.floor((mw - #sub) / 2) + 1,
                                 math.max(1, math.min(mh, sy + logo.h + 1)))
            monitor.write(sub)
        end
        return
    end
    monitor.setBackgroundColor(colors.gray)
    for x = 1, mw do
        monitor.setCursorPos(x, 1)
        monitor.write(" ")
        monitor.setCursorPos(x, mh)
        monitor.write(" ")
    end
    for y = 1, mh do
        monitor.setCursorPos(1, y)
        monitor.write(" ")
        monitor.setCursorPos(mw, y)
        monitor.write(" ")
    end
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.lime)
    monitor.setCursorPos(math.floor((mw - #titleText) / 2) + 1, math.max(1, math.floor(mh / 2) - 1))
    monitor.write(titleText)
    monitor.setTextColor(colors.gray)
    local sub = subtitleText or ""
    monitor.setCursorPos(math.floor((mw - #sub) / 2) + 1, math.floor(mh / 2) + 1)
    monitor.write(sub)
end

if not name then
    local all = {}
    for _, f in ipairs(fs.find("*.data")) do
        all[#all + 1] = f:sub(1, #f - 5)
    end
    if #all == 0 then
        error("no .data files here - run install first")
    elseif #all == 1 then
        name = all[1]
    else
        term.clear()
        term.setTextColor(colors.green)
        term.setCursorPos(1, 1)
        term.write("SELECT VIDEO   (1-" .. math.min(9, #all) .. ", Q = quit)")
        for i, nm in ipairs(all) do
            term.setCursorPos(1, 2 + i)
            term.setTextColor(colors.white)
            term.write((i <= 9 and (i .. ". ") or "   ") .. nm)
        end
        showLogo("SELECT TRACK", ("pick 1-%d, Q quits"):format(math.min(9, #all)))
        local picked
        while not picked do
            local ev = {os.pullEvent()}
            if ev[1] == "key" then
                if ev[2] == keys.q then return end
                local idx = ev[2] - keys.one + 1
                if idx >= 1 and idx <= math.min(9, #all) then
                    picked = idx
                end
            end
        end
        name = all[picked]
        showLogo("LOADING", name)
    end
end

local vid = loadVideo(name)
W, H, FPS, PAL = vid.W, vid.H, vid.FPS, vid.PAL
frames = vid.frames

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
local syncLead = 0.2                -- start video this many seconds after audio
do
    local f = io.open("rick.sync", "r")
    if f then
        local v = tonumber(f:read("*a"))
        if v then
            syncLead = math.max(0, math.min(1.5, v))
        end
        f:close()
    end
end
local function saveSync()
    local f = fs.open("rick.sync", "w")
    if f then
        f.write(string.format("%.2f", syncLead))
        f.close()
    end
end
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
    term.setCursorPos(1, 13)
    term.write("sync " .. string.format("%.2f", syncLead) .. " s   [ , / . ]")
end
drawGui(true)

local vstart = os.clock()

local function videoThread()
    local step = FPS / 20
    local acc = 0
    local timerId = os.startTimer(0.05)
    while not quit do
        local ev = {os.pullEvent()}
        if ev[1] == "timer" and ev[2] == timerId then
            timerId = os.startTimer(0.05)
            if not paused and os.clock() - vstart >= syncLead then
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
            elseif ev[2] == keys.comma then
                syncLead = math.max(0, syncLead - 0.05)
                saveSync()
                drawGui(true)
            elseif ev[2] == keys.period then
                syncLead = math.min(1.5, syncLead + 0.05)
                saveSync()
                drawGui(true)
            end
        end
    end
end

local function audioThread()
    local speaker = peripheral.find("speaker")
    if not speaker then
        print("No speaker found - video only.")
        while true do sleep(0.05) end
    end
    local dfpwm = require "cc.audio.dfpwm"
    local function openTrack()
        return assert(io.open(name .. ".dfpwm", "rb"), name .. ".dfpwm not found"),
               dfpwm.make_decoder()
    end
    local track, decoder = openTrack()
    while not quit do
        if paused then
            sleep(0.05)
        else
            local chunk = track:read(2048)
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

print("Now playing " .. name .. " - P pause, [ ] volume, , . sync, Q quit")
parallel.waitForAll(videoThread, audioThread)
showLogo("STOPPED", name)
