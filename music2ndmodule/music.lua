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
  f             search online (same song API as the classic CC "music" player)
  d             save the highlighted online result into your own library
  z             save the currently playing song (adds it to a playlist; if it's
                an online stream it's downloaded to your library first)
  a             add the highlighted song to the current playlist
  s             save the current playlist (prompts for a name if none)
  p             cycle playlists (ALL songs -> playlist 1 -> ... -> ALL)
  c             create a new, empty playlist and switch to it
  x             delete the current playlist file
  q             quit

Notes:
  - Plays through the first connected speaker.
  - Online search + streaming + saving all need http enabled, and the
    song API host added to the server's http whitelist.
    Regular playback of your own library is fully offline.
]]

local args = { ... }

local CHUNK = 2048                       -- dfpwm bytes per feed (~0.34 s)
local function songPath(n) return "music/" .. n .. ".dfpwm" end

local API_BASE = "https://ipod-2to6magyna-uc.a.run.app/"
local API_VER = "2.1"
local onlineList = {}                    -- flattened online search results
local lastSearchUrl = nil                -- pending http.request url
local searchPending = false

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
    current = nil,           -- song label currently loaded
    elapsed = 0,
    dir = nil,               -- open file handle (library song)
    http = nil,              -- open stream handle (online song)
    online = nil,            -- { url, id } when streaming from the API
    onlineOpen = nil,        -- the online entry currently open
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
    elseif viewMode == "ONLINE" then
        -- online results stay exactly as the search returned them
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

local function closeHandles()
    if state.http then pcall(state.http.close, state.http) end
    state.http = nil
    if state.dir then pcall(state.dir.close, state.dir) end
    state.dir = nil
end

local function startSong(n)
    state.current = n
    state.online = nil
    state.onlineOpen = nil
    closeHandles()
    state.playing = true
    state.paused = false
    state.elapsed = 0
    state.seq = state.seq + 1
    emit()
end

local function stopSong()
    state.playing = false
    state.paused = false
    state.current = nil
    state.online = nil
    state.onlineOpen = nil
    closeHandles()
    state.seq = state.seq + 1
    emit()
end

local function streamUrl(id)
    return API_BASE .. "?v=" .. API_VER .. "&id=" .. textutils.urlEncode(id)
end

local function sanitizeName(n)
    n = (n or ""):gsub("[^%w%._%- ]", ""):gsub("%s+", " "):sub(1, 40)
    if n == "" then n = "song" end
    return n
end

local function flattenResults(res)
    local out = {}
    for _, r in ipairs(res or {}) do
        if type(r) == "table" then
            if r.type == "playlist" and type(r.playlist_items) == "table" then
                for _, it in ipairs(r.playlist_items) do
                    out[#out + 1] = {
                        label = it.name or it.id or "track",
                        id = it.id,
                        name = it.name,
                        artist = it.artist,
                    }
                end
            else
                out[#out + 1] = {
                    label = r.name or r.id or "track",
                    id = r.id,
                    name = r.name,
                    artist = r.artist,
                }
            end
        end
    end
    return out
end

local function startOnline(it)
    state.current = it.label
    state.online = { url = streamUrl(it.id), id = it.id, item = it }
    state.onlineOpen = nil
    closeHandles()
    state.playing = true
    state.paused = false
    state.elapsed = 0
    state.seq = state.seq + 1
    emit()
end

local function playIndex(i)
    if viewMode == "ONLINE" and onlineList[i] then
        startOnline(onlineList[i])
    else
        startSong(viewList[i])
    end
end

local function nextSong()
    if not state.current then
        if #viewList > 0 then playIndex(math.min(cursor, #viewList)) end
        return
    end
    local i = inList(state.current, viewList)
    if i then
        if i < #viewList then
            playIndex(i + 1)
            return
        elseif state.loop and #viewList > 0 then
            playIndex(1)
            return
        end
    else
        if #viewList > 0 then playIndex(1) end
        return
    end
    stopSong()
end

local function prevSong()
    if not state.current then
        if #viewList > 0 then playIndex(math.min(cursor, #viewList)) end
        return
    end
    local i = inList(state.current, viewList)
    if i and i > 1 then
        playIndex(i - 1)
    elseif state.loop and #viewList > 0 then
        playIndex(#viewList)
    else
        state.elapsed = 0 -- just restart the current one
        state.seq = state.seq + 1
        state.onlineOpen = nil
        closeHandles()
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
        term.setTextColor(colors.lightGray)
        term.setCursorPos(2, 3)
        local barW = math.max(8, w - 22)
        if total > 0 then
            local frac = state.elapsed / total
            local filled = math.floor(frac * barW)
            term.write(fmtT(state.elapsed) .. " / " .. fmtT(total))
            term.setBackgroundColor(colors.gray)
            for x = 0, barW - 1 do
                term.setCursorPos(12 + x, 3)
                term.write(x < filled and "=" or "-")
            end
            term.setBackgroundColor(colors.black)
            term.setCursorPos(13 + barW + 1, 3)
        else
            term.write(fmtT(state.elapsed) .. " (streaming)")
            term.setCursorPos(13 + barW + 1, 3)
        end
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

    if state.status then
        term.setTextColor(colors.lightGray)
        term.setCursorPos(2, 6)
        local st = state.status
        if #st > w - 3 then st = st:sub(1, w - 6) .. "..." end
        term.write(st)
    end

    local top = 7
    local rowsAvail = h - top - 1
    local half = math.floor(rowsAvail / 2)
    local off = math.max(0, math.min(math.max(0, #viewList - rowsAvail), cursor - 1 - half))
    if viewMode == "ONLINE" and #viewList == 0 and not searchPending then
        term.setTextColor(colors.gray)
        term.setCursorPos(2, top)
        term.write("No results - press f to search online")
    end
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
    local help = "ENTER play | n/b next | space pause | l loop | [ ] vol | f search | d save | z save now playing | a add | p playlists | c new | x del | q quit"
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
            local online = state.online
            local needOpen = false
            if online then
                needOpen = state.onlineOpen ~= online
            else
                needOpen = state.dir == nil or state.openName ~= state.current
            end
            if needOpen then
                if state.http then pcall(state.http.close, state.http) end
                state.http = nil
                if online then
                    local resp = http.get(online.url, nil, true, { timeout = 60000 })
                    if not resp then
                        stopSong()
                    else
                        state.http = resp
                        state.onlineOpen = online
                        decoder = dfpwm.make_decoder()
                        state.elapsed = 0
                    end
                else
                    if state.dir and state.openName ~= state.current then
                        pcall(state.dir.close, state.dir)
                    end
                    state.dir = io.open(songPath(state.current), "rb")
                    if not state.dir then
                        stopSong()
                    else
                        state.openName = state.current
                        decoder = dfpwm.make_decoder()
                        state.elapsed = 0
                    end
                end
            end
            local h = state.online and state.http or state.dir
            if h then
                local mySeq = state.seq
                local chunk = h:read(CHUNK)
                if not chunk or #chunk == 0 then
                    if state.online then
                        pcall(state.http.close, state.http)
                        state.http = nil
                        state.onlineOpen = nil
                    else
                        pcall(state.dir.close, state.dir)
                        state.dir = nil
                        state.openName = nil
                    end
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
                if viewList[cursor] then
                    if viewMode == "ONLINE" then
                        if onlineList[cursor] then startOnline(onlineList[cursor]) end
                    else
                        startSong(viewList[cursor])
                    end
                end
            elseif k == keys.n then
                nextSong()
            elseif k == keys.b then
                prevSong()
            elseif k == keys.space then
                if state.current or #viewList > 0 then
                    if not state.current then playIndex(math.max(1, cursor)) end
                    state.paused = not state.paused
                    emit()
                end
            elseif k == keys.l then
                state.loop = not state.loop
                os.queueEvent("music_redraw")
            elseif k == keys.f then
                if not http then
                    state.status = "http is disabled on this server"
                    os.queueEvent("music_redraw")
                else
                    local q = promptLine("search online: ")
                    if q ~= "" then
                        lastSearchUrl = API_BASE .. "?v=" .. API_VER .. "&search=" .. textutils.urlEncode(q)
                        searchPending = true
                        viewMode = "ONLINE"
                        onlineList = {}
                        viewList = {}
                        cursor = 1
                        state.status = "searching ..."
                        os.queueEvent("music_redraw")
                        http.request(lastSearchUrl)
                    end
                end
            elseif k == keys.d then
                if viewMode == "ONLINE" and onlineList[cursor] then
                    local it = onlineList[cursor]
                    local fname = sanitizeName(it.name or it.label)
                    state.status = "saving " .. fname .. " ..."
                    os.queueEvent("music_redraw")
                    local resp = http.get(streamUrl(it.id), nil, true, { timeout = 120000 })
                    if resp then
                        local data = resp.readAll()
                        resp.close()
                        fs.makeDir("music")
                        local f = assert(fs.open(songPath(fname), "wb"))
                        f.write(data)
                        f.close()
                        state.status = "saved music/" .. fname .. ".dfpwm (" .. #data .. " B) - press p to see it"
                    else
                        state.status = "download failed - is " .. API_BASE .. " whitelisted?"
                    end
                    os.queueEvent("music_redraw")
                else
                    state.status = "use f to search online first"
                    os.queueEvent("music_redraw")
                end
            elseif k == keys.z then
                if not state.current or not state.playing then
                    state.status = "nothing is playing to save"
                    os.queueEvent("music_redraw")
                else
                    local cur = state.current
                    local ok = true
                    local target = (viewMode ~= "ALL" and viewMode ~= "ONLINE") and viewMode or nil
                    if state.online then
                        local it = state.online.item
                        local fname = sanitizeName(it.name or it.label)
                        state.status = "saving " .. fname .. " to library ..."
                        os.queueEvent("music_redraw")
                        local resp = http.get(state.online.url, nil, true, { timeout = 120000 })
                        if not resp then
                            state.status = "couldn't download - check http/whitelist"
                            ok = false
                            os.queueEvent("music_redraw")
                        else
                            local data = resp.readAll()
                            resp.close()
                            fs.makeDir("music")
                            local f = assert(fs.open(songPath(fname), "wb"))
                            f.write(data)
                            f.close()
                            cur = fname
                        end
                    end
                    if ok then
                        if not target then
                            local nm = promptLine("add \"" .. cur .. "\" to playlist: ")
                            if nm ~= "" then target = nm end
                        end
                        if target then
                            local items = loadPlaylist(target)
                            if inList(cur, items) then
                                state.status = "already in playlist \"" .. target .. "\""
                            else
                                items[#items + 1] = cur
                                savePlaylist(target, items)
                                state.status = "added \"" .. cur .. "\" to \"" .. target .. "\""
                            end
                            playlists = listPlaylists()
                            viewMode = "ALL"
                            rebuildView()
                        end
                    end
                    os.queueEvent("music_redraw")
                end
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
                if n and viewMode ~= "ALL" and viewMode ~= "ONLINE" then
                    local items = loadPlaylist(viewMode)
                    if not inList(n, items) then
                        items[#items + 1] = n
                        savePlaylist(viewMode, items)
                        rebuildView()
                    end
                elseif viewMode == "ONLINE" then
                    state.status = "use d to save an online result to your library"
                else
                    state.status = "pick a playlist first (p or c) - then use 'a' to add songs"
                end
                os.queueEvent("music_redraw")
            elseif k == keys.s then
                if viewMode == "ONLINE" then
                    state.status = "can't save an online view - press p to pick a playlist first"
                elseif viewMode == "ALL" then
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
                if viewMode ~= "ALL" and viewMode ~= "ONLINE" then
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
        elseif ev[1] == "http_success" then
            local okUrl, handle = ev[2], ev[3]
            if okUrl == lastSearchUrl then
                local txt = handle.readAll()
                handle.close()
                local okParse, res = pcall(textutils.unserialiseJSON, txt)
                searchPending = false
                if okParse and type(res) == "table" then
                    onlineList = flattenResults(res)
                    viewList = {}
                    for _, it in ipairs(onlineList) do viewList[#viewList + 1] = it.label end
                    cursor = 1
                    state.status = #onlineList .. " online result" .. (#onlineList == 1 and "" or "s")
                else
                    state.status = "search returned nothing"
                end
                os.queueEvent("music_redraw")
            end
        elseif ev[1] == "http_failure" then
            if ev[2] == lastSearchUrl then
                searchPending = false
                state.status = "search failed (network / whitelist)"
                os.queueEvent("music_redraw")
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