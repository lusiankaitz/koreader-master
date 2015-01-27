local InputContainer = require("ui/widget/container/inputcontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Event = require("ui/event")
local DEBUG = require("dbg")
local T = require("ffi/util").template
local _ = require("gettext")

local ReaderTypeset = InputContainer:new{
    css_menu_title = _("Set render style"),
    css = nil,
    internal_css = true,
}

function ReaderTypeset:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderTypeset:onReadSettings(config)
    self.css = config:readSetting("css")
    if self.css and self.css ~= "" then
        self.ui.document:setStyleSheet(self.css)
    else
        self.ui.document:setStyleSheet(self.ui.document.default_css)
        self.css = self.ui.document.default_css
    end

    self.embedded_css = config:readSetting("embedded_css")
    if self.embedded_css == nil then
        -- default to enable embedded css
        -- note that it's a bit confusing here:
        -- global settins store 0/1, while document settings store false/true
        -- we leave it that way for now to maintain backwards compatibility
        local global = G_reader_settings:readSetting("copt_embedded_css")
        self.embedded_css = (global == nil or global == 1) and true or false
    end
    self.ui.document:setEmbeddedStyleSheet(self.embedded_css and 1 or 0)

    -- set page margins
    self:onSetPageMargins(
        config:readSetting("copt_page_margins") or
        G_reader_settings:readSetting("copt_page_margins") or
        DCREREADER_CONFIG_MARGIN_SIZES_MEDIUM)

    -- default to enable floating punctuation
    -- the floating punctuation should not be boolean value for the following
    -- expression otherwise a false value will never be returned but numerical
    -- values will survive this expression
    self.floating_punctuation = config:readSetting("floating_punctuation") or
        G_reader_settings:readSetting("floating_punctuation") or 1
    self:toggleFloatingPunctuation(self.floating_punctuation)
end

function ReaderTypeset:onSaveSettings()
    self.ui.doc_settings:saveSetting("css", self.css)
    self.ui.doc_settings:saveSetting("embedded_css", self.embedded_css)
    self.ui.doc_settings:saveSetting("floating_punctuation", self.floating_punctuation)
end

function ReaderTypeset:onToggleEmbeddedStyleSheet(toggle)
    self:toggleEmbeddedStyleSheet(toggle)
    return true
end

function ReaderTypeset:genStyleSheetMenu()
    local file_list = {
        {
            text = _("clear all external styles"),
            callback = function()
                self:setStyleSheet(nil)
            end
        },
        {
            text = _("Auto"),
            callback = function()
                self:setStyleSheet(self.ui.document.default_css)
            end
        },
    }
    for f in lfs.dir("./data") do
        if lfs.attributes("./data/"..f, "mode") == "file" and string.match(f, "%.css$") then
            table.insert(file_list, {
                text = f,
                callback = function()
                    self:setStyleSheet("./data/"..f)
                end
            })
        end
    end
    return file_list
end

function ReaderTypeset:setStyleSheet(new_css)
    if new_css ~= self.css then
        --DEBUG("setting css to ", new_css)
        self.css = new_css
        if new_css == nil then
            new_css = ""
        end
        self.ui.document:setStyleSheet(new_css)
        self.ui:handleEvent(Event:new("UpdatePos"))
    end
end

function ReaderTypeset:setEmbededStyleSheetOnly()
    if self.css ~= nil then
        -- clear applied css
        self.ui.document:setStyleSheet("")
        self.ui.document:setEmbeddedStyleSheet(1)
        self.css = nil
        self.ui:handleEvent(Event:new("UpdatePos"))
    end
end

function ReaderTypeset:toggleEmbeddedStyleSheet(toggle)
    if not toggle then
        self.embedded_css = false
        self:setStyleSheet(self.ui.document.default_css)
        self.ui.document:setEmbeddedStyleSheet(0)
    else
        self.embedded_css = true
        --self:setStyleSheet(self.ui.document.default_css)
        self.ui.document:setEmbeddedStyleSheet(1)
    end
    self.ui:handleEvent(Event:new("UpdatePos"))
end

function ReaderTypeset:toggleFloatingPunctuation(toggle)
    -- for some reason the toggle value read from history files may stay boolean
    -- and there seems no more elegant way to convert boolean values to numbers
    if toggle == true then
        toggle = 1
    elseif toggle == false then
        toggle = 0
    end
    self.ui.document:setFloatingPunctuation(toggle)
    self.ui:handleEvent(Event:new("UpdatePos"))
end

function ReaderTypeset:addToMainMenu(tab_item_table)
    -- insert table to main reader menu
    table.insert(tab_item_table.typeset, {
        text = self.css_menu_title,
        sub_item_table = self:genStyleSheetMenu(),
    })
    table.insert(tab_item_table.typeset, {
        text = _("Floating punctuation"),
        checked_func = function() return self.floating_punctuation == 1 end,
        callback = function()
            self.floating_punctuation = self.floating_punctuation == 1 and 0 or 1
            self:toggleFloatingPunctuation(self.floating_punctuation)
    end,
        hold_callback = function() self:makeDefaultFloatingPunctuation() end,
    })
end

function ReaderTypeset:makeDefaultFloatingPunctuation()
    local toggler = self.floating_punctuation == 1 and _("On") or _("Off")
    UIManager:show(ConfirmBox:new{
        text = T(
            _("Set default floating punctuation to %1?"),
            toggler
        ),
        ok_callback = function()
            G_reader_settings:saveSetting("floating_punctuation", self.floating_punctuation)
        end,
    })
end

function ReaderTypeset:onSetPageMargins(margins)
    local left = Screen:scaleBySize(margins[1])
    local top = Screen:scaleBySize(margins[2])
    local right = Screen:scaleBySize(margins[3])
    local bottom = Screen:scaleBySize(margins[4])
    self.ui.document:setPageMargins(left, top, right, bottom)
    self.ui:handleEvent(Event:new("UpdatePos"))
    return true
end

return ReaderTypeset
