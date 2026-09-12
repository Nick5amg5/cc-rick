--[[ install.lua  -  download the CC video/audio player and tracks into this computer.

SET UP:
   BASE is already set to your GitHub host. If you host elsewhere, change it to
   the URL prefix where rick.lua, <track>.data and <track>.dfpwm are hosted.

RUN:
   wget <base>/install.lua install
   install              -> installs the default track (rick)
   install intro        -> installs track "intro" (intro.data / intro.dfpwm)
   install a b          -> installs several tracks
   install -f           -> force re-download (overwrite what's already there)

Then run  rick  to play, or  rick intro  /  rick <name>  for a specific track.
With more than one track and no name, rick shows a picker. ]]

local BASE = "https://raw.githubusercontent.com/Nick5amg5/cc-rick/HEAD/"

local args = {...}
local force = false
local tracks = {}
for _, a in ipairs(args) do
    if a == "-f" then
        force = true
    else
        tracks[#tracks + 1] = a
    end
end
if #tracks == 0 then
    tracks = { "rick" }
end

if BASE == "" then
    print("Set BASE at the top of install.lua first.")
    return
end

if BASE:sub(-1) ~= "/" then
    BASE = BASE .. "/"
end

if not http then
    print("The http API is disabled on this server (config option).")
    print("Copy the files into the computer instead.")
    return
end

local function fetch(name)
    if fs.exists(name) and not force then
        print("already have " .. name)
        return
    end
    io.write("downloading " .. name .. " ... ")
    local resp = http.get(BASE .. name, nil, false, { timeout = 240000 })
    if not resp then
        print("FAILED")
        error("Could not reach " .. BASE .. name)
    end
    local data = resp.readAll()
    resp.close()
    local f = assert(fs.open(name, "wb"))
    f.write(data)
    f.close()
    print("saved " .. #data .. " bytes")
end

fetch("rick.lua")  -- generic player (always)
for _, t in ipairs(tracks) do
    fetch(t .. ".data")
    fetch(t .. ".dfpwm")
end

print()
print("Done. Put a monitor next to the computer and a speaker nearby,")
print("then run:   rick   (or  rick <name>)")