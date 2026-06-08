local addonName, ns = ...

-- FIX: Create the addon object exactly ONCE.
local Addon = LibStub("AceAddon-3.0"):NewAddon("CraftingCooldowns", "AceEvent-3.0", "AceTimer-3.0", "AceConsole-3.0")
ns.Addon = Addon

-- Keep the rest of your file exactly as it is:
function Addon:OnInitialize()
    ---print("|cffff0000[CC Debug]|r: core.lua Pre self.initialized")
    if self.initialized then return end
    self.initialized = true
    ---print("|cffff0000[CC Debug]|r: Core.lua OnInitialize is FIRING!")
if Addon.Notifier then
    Addon.Notifier:OnInitialize()
    Addon.Notifier:Enable()
end
    if Addon.Database then
        ---print("|cffffaa00[CC Debug]|r: Initializing Database...")
        Addon.Database:OnInitialize()
    else
        ---print("|cffff0000[CC Debug]|r: ERROR - Addon.Database is NIL!")
    end

    if Addon.UI then
        ---print("|cffffaa00[CC Debug]|r: Initializing UI...")
        Addon.UI:Initialize()
    else
        ---print("|cffff0000[CC Debug]|r: ERROR - Addon.UI is NIL!")
    end
    
    local scanner = self:GetModule("CooldownScanner", true)
    if scanner then
        ---print("|cffffaa00[CC Debug]|r: Enabling Scanner Module...")
        scanner:EnableScanner()
    else
        ---print("|cffff0000[CC Debug]|r: ERROR - CooldownScanner module is NIL!")
    end
    
    ---print("|cffff0000[CC Debug]|r: Core.lua OnInitialize FINISHED.")
end

-- Ace3 automatically enables modules when the main addon enables,
-- but since you want explicit control over the CooldownScanner sequence:
function Addon:OnEnable()
    -- Safe module fetching using the classic 3.3.5a Ace3 API
    local CooldownScanner = self:GetModule("CooldownScanner", true)
    if CooldownScanner and CooldownScanner.EnableScanner then
        CooldownScanner:EnableScanner()
    end
end

function Addon:OnDisable()
    local CooldownScanner = self:GetModule("CooldownScanner", true)
if Addon.Notifier then
    Addon.Notifier:Disable()
end
    if CooldownScanner and CooldownScanner.DisableScanner then
        CooldownScanner:DisableScanner()
    end
end