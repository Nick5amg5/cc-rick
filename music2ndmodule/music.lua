--[[ music.lua - CC:Tweaked music player (local library + playlists)

A self-contained, offline cousin of the classic pastebin "music" streaming
player: instead of streaming from a web API it plays .dfpwm files already on
this computer (or downloaded with "music add").

Layout on disk:
  music/<name>.dfpwm         your songs (audio only, no video)
  music/playlists/<n>.txt    playlists, one song name per line

Command line usage:
  music               open the terminal GUI
  music play <name>   play one song and exit when done
  music add <url> <n> save a .dfpwm file from a URL into music/ as n.dfpwm
                      (e.g.  music add https://host/x.dfpwm mytrack)

GUI keys:
  up / down     move through the list
  enter         play the highlighted song
  n / b         next / previous song
  space         pause / resume
  l             loop the song list on / off
  [ and ]       volume down / up
  a             add the highlighted song to the current playlist
  s             save the current playlist (prompts for a name if none)
  p             cycle playlists (ALL songs -> playlist 1 -> ... -> ALL)
  c             create a new, empty playlist and switch to it
  x             delete the current playlist file
  q             quit

Notes:
  - Plays through the first connected speaker.
  - Requires http enabled for "music add" - regular playback is fully offline.
]]

local args = { ... }

local CHUNK = 2048                       -- dfpwm bytes per feed (~0.34 s)
local function songPath(n) return "music/" .. n .. ".dfpwm" end

local function scanSongs()
    local out = {}
    for _, f in ipairs(fs.find("music/*.dfpwm")) do
        local base = f
        if base:find("/") then base = base:match("([^/]+)$") end
        out[#out + 1] = base:sub(1, #base - 6)
    end
    table.sort(out)
    return out
end

local function listPlaylists()
    local out = {}
    for _, f in ipairs(fs.find("music/playlists/*")) do
        if not fs.isDir(f) then
            local base = f
            if base:find("/") then base = base:match("([^/]+)$") end
            out[#out + 1] = base:gsub("%.txt$", "")
        end
    end
    table.sort(out)
    return out
end

local function loadPlaylist(name)
    local path = "music/playlists/" .. name .. ".txt"
    local items = {}
    if fs.exists(path) then
        local f = fs.open(path, "r")
        local c = f.readAll()
        f.close()
        for line in c:gmatch("[^\r\n]+") do
            items[#items + 1] = line
        end
    end
    return items
end

local function savePlaylist(name, items)
    if not name or name == "" then return end
    fs.makeDir("music/playlists")
    local f = assert(fs.open("music/playlists/" .. name .. ".txt", "w"))
    f.write(table.concat(items, "\n"))
    f.close()
end

local state = {
    volume = 1.5,
    playing = false,
    paused = false,
    loop = false,
    current = nil,           -- song name currently loaded
    elapsed = 0,
    dir = nil,               -- open file handle
    openName = nil,
    seq = 0,                 -- increments on every song change (aborts old playback)
}

local viewMode = "ALL"       -- "ALL" or a playlist name
local viewList = scanSongs() -- names currently shown
local cursor = 1
local playlists = listPlaylists()

local function inList(n, lst)
    for i, x in ipairs(lst) do if x == n then return i end end
    return nil
end

local function rebuildView()
    if viewMode == "ALL" then
        viewList = scanSongs()
    else
        viewList = {}
        for _, n in ipairs(loadPlaylist(viewMode)) do
            if fs.exists(songPath(n)) then viewList[#viewList + 1] = n end
        end
    end
    if cursor > #viewList then cursor = math.max(1, #viewList) end
end

local function emit()
    os.queueEvent("music_redraw")
    os.queueEvent("music_audio")
end

local function startSong(n)
    state.current = n
    state.playing = true
    state.paused = false
    state.elapsed = 0
    state.dir = nil
    state.seq = state.seq + 1
    emit()
end

local function stopSong()
    state.playing = false
    state.paused = false
    state.current = nil
    state.dir = nil
    state.seq = state.seq + 1
    emit()
end

local function nextSong()
    if not state.current then
        if #viewList > 0 then startSong(viewList[math.min(cursor, #viewList)]) end
        return
    end
    local i = inList(state.current, viewList)
    if i then
        if i < #viewList then
            startSong(viewList[i + 1])
            return
        elseif state.loop and #viewList > 0 then
            startSong(viewList[1])
            return
        end
    else
        if #viewList > 0 then startSong(viewList[1]) end
        return
    end
    stopSong()
end

local function prevSong()
    if not state.current then
        if #viewList > 0 then startSong(viewList[math.min(cursor, #viewList)]) end
        return
    end
    local i = inList(state.current, viewList)
    if i and i > 1 then
        startSong(viewList[i - 1])
    elseif state.loop and #viewList > 0 then
        startSong(viewList[#viewList])
    else
        state.elapsed = 0 -- just restart the current one
        state.seq = state.seq + 1
        state.dir = nil
        emit()
    end
end

local function fmtT(s)
    local m = math.floor(s / 60)
    local r = math.floor(s) % 60
    return m .. ":" .. string.format("%02d", r)
end

local function draw()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.black)
    for x = 1, w do term.setCursorPos(x, 1) term.write(" ") end
    term.setCursorPos(1, 1)
    term.write("  MUSIC 2.0 - local player")
    term.setBackgroundColor(colors.black)

    if state.current then
        local name = state.current
        if #name > w - 4 then name = name:sub(1, w - 7) .. "..." end
        term.setTextColor(colors.white)
        term.setCursorPos(2, 2)
        term.write("Now: " .. name)
        local total = 0
        local p = songPath(state.current)
        if fs.exists(p) then
            total = fs.getSize(p) * 8 / 48000
        end
        local barW = math.max(8, w - 22)
        local frac = total > 0 and (state.elapsed / total) or 0
        local filled = math.floor(frac * barW)
        term.setTextColor(colors.lightGray)
        term.setCursorPos(2, 3)
        term.write(fmtT(state.elapsed) .. " / " .. fmtT(total))
        term.setBackgroundColor(colors.gray)
        for x = 0, barW - 1 do
            term.setCursorPos(12 + x, 3)
            term.write(x < filled and "=" or "-")
        end
        term.setBackgroundColor(colors.black)
        term.setCursorPos(13 + barW + 1, 3)
        term.setTextColor(state.paused and colors.yellow or colors.lime)
        term.write(state.paused and "PAUSED" or "PLAYING")
    else
        term.setTextColor(colors.lightGray)
        term.setCursorPos(2, 2)
        term.write("Not playing")
        term.setCursorPos(2, 3)
        term.write("Volume " .. math.floor(state.volume * 10) / 10 .. "  Loop " ..
                   (state.loop and "on" or "off"))
    end
    term.setTextColor(colors.white)
    term.setCursorPos(2, 4)
    term.write("View: " .. viewMode .. "  (" .. #viewList .. " songs)")
    term.setCursorPos(2, 5)
    term.setTextColor(colors.gray)
    local pls = {}
    for i, n in ipairs(playlists) do pls[i] = n end
    term.write("Playlists: " .. (#pls == 0 and "(none)" or table.concat(pls, ", ")))

    local top = 7
    local rowsAvail = h - top - 1
    local half = math.floor(rowsAvail / 2)
    local off = math.max(0, math.min(math.max(0, #viewList - rowsAvail), cursor - 1 - half))
    for row = 1, rowsAvail do
        local idx = off + row
        local y = top + row - 1
        if y > h - 1 then break end
        term.setBackgroundColor(colors.black)
        if viewList[idx] then
            if idx == cursor then
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.black)
            elseif state.current == viewList[idx] and state.playing then
                term.setTextColor(colors.lime)
            else
                term.setTextColor(colors.white)
            end
            term.setCursorPos(2, y)
            term.write("  ")
            local name = viewList[idx]
            if #name > w - 6 then name = name:sub(1, w - 9) .. "..." end
            term.write(name)
            term.setCursorPos(w - 1, y)
            term.write(" ")
        end
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    term.setCursorPos(1, h)
    term.clearLine()
    local help = "ENTER play | n/b next | space pause | l loop | [ ] vol | a add | s save | p playlists | c new | x del | q quit"
    term.write(help:sub(1, math.max(1, w - 1)))
end

-- ------------------------------------------------------------------- audio --
local function audioLoop()
    local dfpwm = require "cc.audio.dfpwm"
    local speaker = peripheral.find("speaker")
    if not speaker then
        error("No speaker attached. Place a speaker next to this computer.", 0)
    end
    local decoder
    while true do
        os.pullEvent("music_audio")
        if state.playing and state.current and not state.paused then
            if state.dir == nil or state.openName ~= state.current then
                if state.dir then pcall(state.dir.close, state.dir) end
                local p = songPath(state.current)
                local h = io.open(p, "rb")
                if not h then
                    stopSong()
                else
                    state.dir = h
                    state.openName = state.current
                    decoder = dfpwm.make_decoder()
                    state.elapsed = 0
                end
            end
            if state.dir then
                local mySeq = state.seq
                local chunk = state.dir:read(CHUNK)
                if not chunk or #chunk == 0 then
                    pcall(state.dir.close, state.dir)
                    state.dir = nil
                    state.openName = nil
                    if mySeq == state.seq then nextSong() end
                    if mySeq == state.seq then emit() end
                else
                    local buffer = decoder(chunk)
                    while not speaker.playAudio(buffer, state.volume) do
                        os.pullEvent("speaker_audio_empty")
                        if not state.playing or state.seq ~= mySeq then break end
                    end
                    if mySeq == state.seq then
                        state.elapsed = state.elapsed + #chunk * 8 / 48000
                        os.queueEvent("music_redraw")
                    end
                end
            end
        end
    end
end

-- -------------------------------------------------------------------- ui --
local function promptLine(txt)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 2)
    term.clearLine()
    term.write(txt)
    local s = read()
    term.setCursorPos(1, 2)
    term.clearLine()
    return s
end

local function runCLI()
    local cmd = args[1]
    if cmd == "add" then
        local url = args[2]
        local name = args[3]
        if not url or not name then
            print("usage: music add <url> <name>")
            return
        end
        if not http then
            print("http is disabled on this server - copy the file in manually instead.")
            return
        end
        io.write("downloading " .. name .. " ... ")
        local resp = http.get(url, nil, true, { timeout = 120000 })
        if not resp then
            print("FAILED")
            return
        end
        local data = resp.readAll()
        resp.close()
        fs.makeDir("music")
        local f = assert(fs.open(songPath(name), "wb"))
        f.write(data)
        f.close()
        print("saved music/" .. name .. ".dfpwm  (" .. #data .. " bytes)")
        return
    end
    if cmd == "play" then
        local name = args[2]
        if not name then print("usage: music play <name>") return end
        if not fs.exists(songPath(name)) then
            print("no music/" .. name .. ".dfpwm - place the file or use 'music add'")
            return
        end
        startSong(name)
        parallel.waitForAny(audioLoop, function()
            while state.playing do os.pullEvent("music_audio") end
        end)
        print("done")
        return
    end
end

local function uiLoop()
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "key" then
            local k = ev[2]
            if k == keys.up or k == keys.w then
                if cursor > 1 then cursor = cursor - 1 end
                os.queueEvent("music_redraw")
            elseif k == keys.down then
                if cursor < #viewList then cursor = cursor + 1 end
                os.queueEvent("music_redraw")
            elseif k == keys.enter then
                if viewList[cursor] then startSong(viewList[cursor]) end
            elseif k == keys.n then
                nextSong()
            elseif k == keys.b then
                prevSong()
            elseif k == keys.space then
                if state.current or #viewList > 0 then
                    if not state.current then startSong(viewList[cursor] or viewList[1]) end
                    state.paused = not state.paused
                    emit()
                end
            elseif k == keys.l then
                state.loop = not state.loop
                os.queueEvent("music_redraw")
            elseif k == keys.leftBracket then
                state.volume = math.max(0, state.volume - 0.1)
                os.queueEvent("music_redraw")
            elseif k == keys.rightBracket then
                state.volume = math.min(3, state.volume + 0.1)
                os.queueEvent("music_redraw")
            elseif k == keys.equals or k == keys.plus then
                state.volume = math.min(3, state.volume + 0.1)
                os.queueEvent("music_redraw")
            elseif k == keys.minus then
                state.volume = math.max(0, state.volume - 0.1)
                os.queueEvent("music_redraw")
            elseif k == keys.a then
                local n = viewList[cursor]
                if n and viewMode ~= "ALL" then
                    local items = loadPlaylist(viewMode)
                    if not inList(n, items) then
                        items[#items + 1] = n
                        savePlaylist(viewMode, items)
                        rebuildView()
                    end
                else
                    print("pick a playlist first (p or c) - then use 'a' to add songs")
                end
                os.queueEvent("music_redraw")
            elseif k == keys.s then
                if viewMode == "ALL" then
                    local nm = promptLine("save playlist as: ")
                    if nm ~= "" then
                        savePlaylist(nm, scanSongs())
                        playlists = listPlaylists()
                    end
                else
                    savePlaylist(viewMode, loadPlaylist(viewMode))
                end
                os.queueEvent("music_redraw")
                emit()
            elseif k == keys.p then
                local idx = 0
                if viewMode ~= "ALL" then
                    for i, n in ipairs(playlists) do if n == viewMode then idx = i break end end
                end
                if #playlists == 0 then
                    viewMode = "ALL"
                else
                    viewMode = viewMode == "ALL" and playlists[1] or playlists[(idx % #playlists) + 1]
                end
                cursor = 1
                rebuildView()
                os.queueEvent("music_redraw")
            elseif k == keys.c then
                local nm = promptLine("new playlist name: ")
                if nm ~= "" then
                    fs.makeDir("music/playlists")
                    savePlaylist(nm, {})
                    playlists = listPlaylists()
                    viewMode = nm
                    rebuildView()
                end
                os.queueEvent("music_redraw")
            elseif k == keys.x then
                if viewMode ~= "ALL" then
                    local path = "music/playlists/" .. viewMode .. ".txt"
                    if fs.exists(path) then fs.delete(path) end
                    playlists = listPlaylists()
                    viewMode = "ALL"
                    rebuildView()
                    os.queueEvent("music_redraw")
                end
            elseif k == keys.q then
                if state.playing then stopSong() end
                term.clear()
                term.setCursorPos(1, 1)
                term.setTextColor(colors.white)
                print("bye")
                return
            end
        elseif ev[1] == "music_redraw" then
            draw()
        end
    end
end

-- ------------------------------------------------------------------ main --
if #args > 0 and args[1] ~= "" then
    runCLI()
    return
end

if not peripheral.find("speaker") then
    print("No speaker attached. Place a speaker next to this computer.")
    print("Run again once a speaker is connected.")
    return
end

fs.makeDir("music")
fs.makeDir("music/playlists")
playlists = listPlaylists()
rebuildView()
term.clear()
draw()
parallel.waitForAny(uiLoop, audioLoop)