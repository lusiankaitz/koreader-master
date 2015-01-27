local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/networkmgr")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Device = require("device")
local DEBUG = require("dbg")
local T = require("ffi/util").template
local _ = require("gettext")

local OTAManager = {
    ota_servers = {
        "http://vislab.bjmu.edu.cn:80/apps/koreader/ota/",
        "http://koreader.ak-team.com:80/",
        "http://hal9k.ifsc.usp.br:80/koreader/",
    },
    ota_channels = {
        "nightly",
    },
    zsync_template = "koreader-%s-latest-%s.zsync",
    installed_package = "ota/koreader.installed.tar",
    package_indexfile = "ota/package.index",
    updated_package = "ota/koreader.updated.tar",
}

function OTAManager:getOTAModel()
    if Device:isKindle() then
        return "kindle"
    elseif Device:isKobo() then
        return "kobo"
    elseif Device:isPocketBook() then
        return "pocketbook"
    else
        return ""
    end
end

function OTAManager:getOTAServer()
    return G_reader_settings:readSetting("ota_server") or self.ota_servers[1]
end

function OTAManager:setOTAServer(server)
    DEBUG("Set OTA server:", server)
    G_reader_settings:saveSetting("ota_server", server)
end

function OTAManager:getOTAChannel()
    return G_reader_settings:readSetting("ota_channel") or self.ota_channels[1]
end

function OTAManager:setOTAChannel(channel)
    DEBUG("Set OTA channel:", channel)
    G_reader_settings:saveSetting("ota_channel", channel)
end

function OTAManager:getZsyncFilename()
    return self.zsync_template:format(self:getOTAModel(), self:getOTAChannel())
end

function OTAManager:checkUpdate()
    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local zsync_file = self:getZsyncFilename()
    local ota_zsync_file = self:getOTAServer() .. zsync_file
    local local_zsync_file = "ota/" .. zsync_file
    -- download zsync file from OTA server
    local r, c, h = http.request{
        url = ota_zsync_file,
        sink = ltn12.sink.file(io.open(local_zsync_file, "w"))}
    -- prompt users to turn on Wifi if network is unreachable
    if c ~= 200 then return end
    -- parse OTA package version
    local ota_package = nil
    local zsync = io.open(local_zsync_file, "r")
    if zsync then
        for line in zsync:lines() do
            ota_package = line:match("^Filename:%s*(.-)%s*$")
            if ota_package then break end
        end
        zsync:close()
    end
    local normalized_version = function(rev)
        local year, month, revision = rev:match("v(%d%d%d%d)%.(%d%d)-?(%d*)")
        return tonumber(year .. month .. string.format("%.4d", revision or "0"))
    end
    local local_ok, local_version = pcall(function()
        local rev_file = io.open("git-rev", "r")
        if rev_file then
            local rev = rev_file:read()
            rev_file:close()
            return normalized_version(rev)
        end
    end)
    local ota_ok, ota_version = pcall(function()
        return normalized_version(ota_package)
    end)
    -- return ota package version if package on OTA server has version
    -- larger than the local package version
    if local_ok and ota_ok and ota_version and local_version and
        ota_version > local_version then
        return ota_version, local_version
    elseif ota_version and ota_version == local_version then
        return 0
    end
end

function OTAManager:fetchAndProcessUpdate()
    local ota_version, local_version = OTAManager:checkUpdate()
    if ota_version == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Your KOReader is up to date."),
        })
    elseif ota_version == nil then
        UIManager:show(InfoMessage:new{
            text = _("OTA server is not available."),
        })
    elseif ota_version then
        UIManager:show(ConfirmBox:new{
            text = T(
                _("Do you want to update?\nInstalled version: %1\nAvailable version: %2"),
                local_version,
                ota_version
            ),
            ok_callback = function()
                UIManager:show(InfoMessage:new{
                    text = _("Downloading may take several minutes..."),
                    timeout = 3,
                })
                UIManager:scheduleIn(1, function()
                    if OTAManager:zsync() == 0 then
                        UIManager:show(InfoMessage:new{
                            text = _("KOReader will be updated on next restart."),
                        })
                    else
                        UIManager:show(ConfirmBox:new{
                            text = _("Error updating KOReader. Would you like to delete temporary files?"),
                            ok_callback = function()
                                os.execute("rm ota/ko*")
                            end,
                        })
                    end
                end)
            end
        })
    end
end

function OTAManager:_buildLocalPackage()
    -- TODO: validate the installed package?
    local installed_package = lfs.currentdir() .. "/" .. self.installed_package
    if lfs.attributes(installed_package, "mode") == "file" then
        return 0
    end
    return os.execute(string.format(
        "./tar cvf %s -C .. -T %s --no-recursion",
        self.installed_package, self.package_indexfile))
end

function OTAManager:zsync()
    if self:_buildLocalPackage() == 0 then
        return os.execute(string.format(
        "./zsync -i %s -o %s -u %s %s",
        self.installed_package, self.updated_package,
        self:getOTAServer(), "ota/" .. self:getZsyncFilename()
        ))
    end
end

function OTAManager:genServerList()
    local servers = {}
    for _, server in ipairs(self.ota_servers) do
        local server_item = {
            text = server,
            checked_func = function() return self:getOTAServer() == server end,
            callback = function() self:setOTAServer(server) end
        }
        table.insert(servers, server_item)
    end
    return servers
end

function OTAManager:genChannelList()
    local channels = {}
    for _, channel in ipairs(self.ota_channels) do
        local channel_item = {
            text = channel,
            checked_func = function() return self:getOTAChannel() == channel end,
            callback = function() self:setOTAChannel(channel) end
        }
        table.insert(channels, channel_item)
    end
    return channels
end

function OTAManager:getOTAMenuTable()
    return {
        text = _("OTA update"),
        sub_item_table = {
            {
                text = _("Check for update"),
                callback = function()
                    if NetworkMgr:getWifiStatus() == false then
                        NetworkMgr:promptWifiOn()
                    else
                        OTAManager.fetchAndProcessUpdate()
                    end
                end
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("OTA server"),
                        sub_item_table = self:genServerList()
                    },
                    {
                        text = _("OTA channel"),
                        sub_item_table = self:genChannelList()
                    },
                }
            },
        }
    }
end

return OTAManager
