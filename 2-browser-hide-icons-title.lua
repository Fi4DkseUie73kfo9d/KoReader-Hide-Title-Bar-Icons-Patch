local _ = require("gettext")
local userpatch = require("userpatch")

local function getMenuItem(menu, ...) -- path
    local function findItem(sub_items, texts)
        local find = {}
        local texts = type(texts) == "table" and texts or { texts }
        -- stylua: ignore
        for _, text in ipairs(texts) do find[text] = true end
        for _, item in ipairs(sub_items) do
            local text = item.text or (item.text_func and item.text_func())
            if text and find[text] then return item end
        end
    end

    local sub_items, item
    for _, texts in ipairs { ... } do -- walk path
        sub_items = (item or menu).sub_item_table
        if not sub_items then return end
        item = findItem(sub_items, texts)
        if not item then return end
    end
    return item
end

local function patchFileManager(plugin)
    local FileManager = require("apps/filemanager/filemanager")
    local BookInfoManager = require("bookinfomanager")

    -- Setting helper
    function BooleanSetting(text, name, default)
        self = { text = text }
        self.get = function()
            local setting = BookInfoManager:getSetting(name)
            if default then return not setting end 
            return setting
        end
        self.toggle = function() return BookInfoManager:toggleSetting(name) end
        return self
    end

    local settings = {
        hide_icons = BooleanSetting(_("Hide Titlebar icons"), "folder_hide_titlebar_icons", true),
        hide_path = BooleanSetting(_("Hide directory path"), "folder_hide_path_text", true),
    }

    -- 1. Intercept setupLayout
    local orig_FileManager_setupLayout = FileManager.setupLayout
    function FileManager:setupLayout()
        local TitleBar = require("ui/widget/titlebar")
        local orig_TitleBar_new = TitleBar.new
        
        TitleBar.new = function(cls, args)
            TitleBar.new = orig_TitleBar_new
            
            if settings.hide_icons.get() then
                -- Hide Home
                args.left_icon = nil
                args.left_icon_tap_callback = nil
                args.left_icon_hold_callback = nil
                
                -- Hide Plus (only if it is a 'plus')
                if args.right_icon == "plus" then
                    args.right_icon = nil
                    args.right_icon_tap_callback = nil
                end
            end
            
            return orig_TitleBar_new(cls, args)
        end

        orig_FileManager_setupLayout(self)
    end
    
    -- 2. Intercept onToggleSelectMode
    local orig_FileManager_onToggleSelectMode = FileManager.onToggleSelectMode
    function FileManager:onToggleSelectMode(do_refresh)
        orig_FileManager_onToggleSelectMode(self, do_refresh)
        if not self.selected_files and settings.hide_icons.get() then
            self.title_bar:setRightIcon(nil)
        end
    end

    -- 3. Intercept updateTitleBarPath
    local orig_FileManager_updateTitleBarPath = FileManager.updateTitleBarPath
    function FileManager:updateTitleBarPath(path)
        if settings.hide_path.get() then
            self.title_bar:setSubTitle("")
        else
            orig_FileManager_updateTitleBarPath(self, path)
        end
    end

    -- 4. Add settings to menu
    local orig_CoverBrowser_addToMainMenu = plugin.addToMainMenu
    if orig_CoverBrowser_addToMainMenu then
        function plugin:addToMainMenu(menu_items)
            orig_CoverBrowser_addToMainMenu(self, menu_items)
            if menu_items.filebrowser_settings == nil then return end

            local item = getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"))
            if item then
                item.sub_item_table[#item.sub_item_table].separator = true
                for i, setting in pairs(settings) do
                    if not getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"), setting.text) then
                        table.insert(item.sub_item_table, {
                            text = setting.text,
                            checked_func = function() return setting.get() end,
                            callback = function()
                                setting.toggle()
                                if FileManager.instance then
                                    FileManager.instance:reinit()
                                end
                            end,
                        })
                    end
                end
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchFileManager)