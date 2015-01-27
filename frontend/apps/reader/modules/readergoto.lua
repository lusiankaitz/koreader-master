local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Event = require("ui/event")
local DEBUG = require("dbg")
local _ = require("gettext")

local ReaderGoto = InputContainer:new{
    goto_menu_title = _("Go to"),
    goto_dialog_title = _("Go to Page or Location"),
}

function ReaderGoto:init()
    self.ui.menu:registerToMainMenu(self)
end

function ReaderGoto:addToMainMenu(tab_item_table)
    -- insert goto command to main reader menu
    table.insert(tab_item_table.navi, {
        text = self.goto_menu_title,
        callback = function()
            self:onShowGotoDialog()
        end,
    })
end

function ReaderGoto:onShowGotoDialog()
    DEBUG("show goto dialog")
    self.goto_dialog = InputDialog:new{
        title = self.goto_dialog_title,
        input_hint = "(1 - "..self.document:getPageCount()..")",
        buttons = {
            {    
                {
                    text = _("Cancel"),
                    enabled = true,
                    callback = function()
                        self:close()
                    end,
                },
                {
                    text = _("Page"),
                    enabled = self.document.info.has_pages,
                    callback = function()
                        self:gotoPage()
                    end,
                },
                {
                    text = _("Location"),
                    enabled = not self.document.info.has_pages,
                    callback = function()
                        self:gotoLocation()
                    end,
                },
            },
        },
        input_type = "number",
        enter_callback = self.document.info.has_pages 
            and function() self:gotoPage() end 
            or function() self:gotoLocation() end,
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.2,
    }
    self.goto_dialog:onShowKeyboard()
    UIManager:show(self.goto_dialog)
end

function ReaderGoto:close()
    self.goto_dialog:onClose()
    UIManager:close(self.goto_dialog)
end

function ReaderGoto:gotoPage()
    local number = tonumber(self.goto_dialog:getInputText())
    if number then
        self.ui:handleEvent(Event:new("GotoPage", number))
    end
    self:close()
    return true
end

function ReaderGoto:gotoLocation()
    local number = tonumber(self.goto_dialog:getInputText())
    if number then
        self.ui:handleEvent(Event:new("GotoPage", number))
    end
    self:close()
    return true
end

return ReaderGoto
