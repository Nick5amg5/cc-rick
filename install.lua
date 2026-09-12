--[[ install.lua  -  download the rick video/audio player into this computer.

SET UP (edit once):
   Change BASE to the URL prefix where rick.data, rick.dfpwm and rick.lua
   are hosted. For a GitHub gist it looks like:
       https://gist.githubusercontent.com/YOURUSERNAME/GISTID/raw

RUN:
   wget <base>/install.lua   (or paste this program in somehow)
   install

That will fetch the three files and tell you to run  rick  to play. ]]

local BASE = "https://raw.githubusercontent.com/Nick5amg5/cc-rick/HEAD/"

local FILES = { "rick.lua", "rick.data", "rick.dfpwm" }

if BASE == "" then
    print("Set BASE at the top of install.lua first.")
    return
end

if BASE:sub(-1) ~= "/" then
    BASE = BASE .. "/"
end

if not http then
    print("The http API is disabled on this server (config option).")
    print("Copy rick.data, rick.dfpwm and rick.lua into the computer instead.")
    return
end

for _, name in ipairs(FILES) do
    if fs.exists(name) then
        print("already have " .. name)
    else
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
end

print()
print("Done. Put a monitor next to the computer and a speaker nearby,")
print("then run:   rick")