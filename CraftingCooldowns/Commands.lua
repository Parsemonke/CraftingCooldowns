local addonName, ns = ...   

-- Grab the master addon structure
local Addon = ns.Addon

-- Create the official Ace3 Command module framework
local Commands = Addon:NewModule("Commands", "AceConsole-3.0")
Addon.Commands = Commands

-- This callback is handled automatically by Core.lua's boot-up cycle
function Commands:OnInitialize()
    -- Register the main handler command using the list provided in constants.lua
    if ns.CommandAliases then
        for _, alias in ipairs(ns.CommandAliases) do
            -- FIX: Change Addon: to self: so AceConsole looks inside this file for the handler!
            self:RegisterChatCommand(alias, "HandleSlashCommand")
        end
    end
end

-- This handles the execution whenever a player types your slash commands in game chat
function Commands:HandleSlashCommand(input)
    input = input and input:trim():lower() or ""

    if input == "snooze" then
        if Addon.Notifier and Addon.Notifier.SnoozeAll then
            Addon.Notifier:SnoozeAll()
        end
    elseif input == "scan" or input == "update" then
        local scanner = Addon:GetModule("CooldownScanner", true)
        if scanner and scanner.EnableScanner then
            ---print("|cff33ff99CraftingCooldowns|r: Forces manual profession cooldown validation...")
            scanner:ScheduleScan("manual")
        end
    elseif input == "reset" then
        if Addon.db and Addon.db.ResetDB then
            Addon.db:ResetDB()
            ---print("|cff33ff99CraftingCooldowns|r: Database tracking configurations have been reset.")
            ReloadUI()
        end
    else
        if Addon.UI and Addon.UI.Toggle then
            Addon.UI:Toggle()
        else
            ---print("|cff33ff99CraftingCooldowns|r: UI component not fully loaded yet.")
        end
    end
end