--[[ delete.lua  -  remove track files from this computer to free disk space.
The repo copies stay, so you can re-install them any time with:  install <name>

Usage:  delete <track> [track ...]   e.g.  delete osama
        delete -a                    delete every track (keeps rick.lua/install/delete)
Never touches rick.lua - the generic player is shared by all tracks. ]]

local args = {...}
if #args == 0 then
    print("usage: delete <track>...   or   delete -a")
    return
end

local removed = 0
local function rm(path)
    if fs.exists(path) then
        fs.delete(path)
        removed = removed + 1
        print("deleted " .. path)
    end
end

if args[1] == "-a" then
    for f in fs.find("*.data") do
        local n = f:sub(1, #f - 5)
        rm(n .. ".data")
        rm(n .. ".dfpwm")
    end
else
    for _, t in ipairs(args) do
        rm(t .. ".data")
        rm(t .. ".dfpwm")
    end
end

if removed == 0 then
    print("nothing to delete (files not present)")
else
    print("removed " .. removed .. " file(s)")
end