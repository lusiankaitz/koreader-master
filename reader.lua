#!./luajit

require "defaults"
pcall(dofile, "defaults.persistent.lua")
package.path = "?.lua;common/?.lua;frontend/?.lua"
package.cpath = "?.so;common/?.so;common/?.dll;/usr/lib/lua/?.so"

local ffi = require("ffi")
if ffi.os == "Windows" then
    ffi.cdef[[
        int _putenv(const char *envvar);
    ]]
    ffi.C._putenv("PATH=libs;common;")
    --ffi.C._putenv("EMULATE_READER_W=480")
    --ffi.C._putenv("EMULATE_READER_H=600")
end

local DocSettings = require("docsettings")
local _ = require("gettext")
-- read settings and check for language override
-- has to be done before requiring other files because
-- they might call gettext on load
G_reader_settings = DocSettings:open(".reader")
local lang_locale = G_reader_settings:readSetting("language")
if lang_locale then
    _.changeLang(lang_locale)
end

-- option parsing:
local longopts = {
    debug = "d",
    profile = "p",
    help = "h",
}

local function showusage()
    print("usage: ./reader.lua [OPTION] ... path")
    print("Read all the books on your E-Ink reader")
    print("")
    print("-d               start in debug mode")
    print("-p               enable Lua code profiling")
    print("-h               show this usage help")
    print("")
    print("If you give the name of a directory instead of a file path, a file")
    print("chooser will show up and let you select a file")
    print("")
    print("If you don't pass any path, the last viewed document will be opened")
    print("")
    print("This software is licensed under the AGPLv3.")
    print("See http://github.com/koreader/koreader for more info.")
    return
end

-- should check DEBUG option in arg and turn on DEBUG before loading other
-- modules, otherwise DEBUG in some modules may not be printed.
local DEBUG = require("dbg")

local Profiler = nil
local ARGV = arg
local argidx = 1
while argidx <= #ARGV do
    local arg = ARGV[argidx]
    argidx = argidx + 1
    if arg == "--" then break end
    -- parse longopts
    if arg:sub(1,2) == "--" then
        local opt = longopts[arg:sub(3)]
        if opt ~= nil then arg = "-"..opt end
    end
    -- code for each option
    if arg == "-h" then
        return showusage()
    elseif arg == "-d" then
        DEBUG:turnOn()
    elseif arg == "-p" then
        Profiler = require("jit.p")
        Profiler.start("la")
    else
        -- not a recognized option, should be a filename
        argidx = argidx - 1
        break
    end
end

local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Device = require("device")
local Screen = require("device").screen
local Font = require("ui/font")

-- read some global reader setting here:
-- font
local fontmap = G_reader_settings:readSetting("fontmap")
if fontmap ~= nil then
    Font.fontmap = fontmap
end
-- last file
local last_file = G_reader_settings:readSetting("lastfile")
if last_file and lfs.attributes(last_file, "mode") ~= "file" then
    last_file = nil
end
-- load last opened file
local open_last = G_reader_settings:readSetting("open_last")
-- night mode
if G_reader_settings:readSetting("night_mode") then
    Screen:toggleNightMode()
end

-- restore kobo frontlight settings
if Device:isKobo() then
    local powerd = Device:getPowerDevice()
    if powerd and powerd.restore_settings then
        local intensity = G_reader_settings:readSetting("frontlight_intensity")
        intensity = intensity or powerd.flIntensity
        powerd:setIntensityWithoutHW(intensity)
        -- powerd:setIntensity(intensity)
    end
end

if ARGV[argidx] and ARGV[argidx] ~= "" then
    local file = nil
    if lfs.attributes(ARGV[argidx], "mode") == "file" then
        file = ARGV[argidx]
    elseif open_last and last_file then
        file = last_file
    end
    -- if file is given in command line argument or open last document is set true
    -- the given file or the last file is opened in the reader
    if file then
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(file)
    -- we assume a directory is given in command line argument
    -- the filemanger will show the files in that path
    else
        local FileManager = require("apps/filemanager/filemanager")
        FileManager:showFiles(ARGV[argidx])
    end
    UIManager:run()
elseif last_file then
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(last_file)
    UIManager:run()
else
    return showusage()
end

local function exitReader()
    local ReaderActivityIndicator = require("apps/reader/modules/readeractivityindicator")

    G_reader_settings:close()

    -- Close lipc handles
    ReaderActivityIndicator:coda()

    -- shutdown hardware abstraction
    Device:exit()

    if Profiler then Profiler.stop() end
    os.exit(0)
end

exitReader()