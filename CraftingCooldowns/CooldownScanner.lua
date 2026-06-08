local addonName, ns = ...

local Addon = ns.Addon

local CooldownScanner = Addon:NewModule("CooldownScanner", "AceEvent-3.0", "AceTimer-3.0")
Addon.CooldownScanner = CooldownScanner

-- ============================================================
-- FIX 3: Module-level item name cache so GetItemInfo is never
--         called more than once per itemID per session.
-- ============================================================
local itemNameCache = {}

-- ============================================================
-- FIX 1: Set of crafting spell IDs built at enable-time for
--         O(1) filter inside UNIT_SPELLCAST_SUCCEEDED.
-- ============================================================
local craftingSpellIdSet = {}

local function BuildCraftingSpellIdSet()
    wipe(craftingSpellIdSet)
    local registry = ns.GetCooldownEntries and ns.GetCooldownEntries() or ns.CooldownRegistry
    if not registry then return end
    for _, entries in pairs(registry) do
        if entries then
            for i = 1, #entries do
                local e = entries[i]
                if e and e.type == "spell" and e.spellID then
                    craftingSpellIdSet[e.spellID] = true
                end
            end
        end
    end
end

-- ============================================================
-- FIX 4: Profession cache TTL so HasProfessionBySpellId does
--         not walk the full skill list on every scan.
-- ============================================================
local PROFESSION_CACHE_TTL   = 30  -- seconds
local PERIODIC_SCAN_INTERVAL = 30  -- rescan every 30s to catch item-use cooldowns
                                    -- that don't fire a detectable bag or cast event
local CHAT_PREFIX            = "|cff33ff99[CraftingCooldowns]|r "

function CooldownScanner:OnInitialize()
    self.scanHandle      = nil
    self.scanPending     = false
    self.lastScanAt      = 0
    self.throttleSeconds = 0.75
    self.periodicHandle  = nil

    -- Raid pause state
    self.inRaid           = false
    self.raidMessageShown = false

    -- FIX 2: Bag cache state
    self.bagCache      = nil
    self.bagCacheDirty = true

    -- FIX 4: Profession cache
    self.professionCache = {}
end

-- ============================================================
-- Throttle / scheduling (unchanged logic, simplified retry)
-- ============================================================

function CooldownScanner:ScheduleScan(reason)
    -- While in a raid, only allow explicit manual scans through
    if self.inRaid and reason ~= "manual" then return end

    self.scanPending = true
    if self.scanHandle then return end

    local now         = GetTime()
    local nextAllowed = (self.lastScanAt or 0) + (self.throttleSeconds or 0)
    local delay       = (now < nextAllowed) and (nextAllowed - now) or 0

    self.scanHandle = self:ScheduleTimer("PerformScanTimerCallback", delay)
end

function CooldownScanner:EnableScanner()
    BuildCraftingSpellIdSet()

    self:RegisterEvent("PLAYER_LOGIN",           "OnLoginEvent")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",  "OnLoginEvent")
    self:RegisterEvent("RAID_ROSTER_UPDATE",     "OnRaidRosterUpdate")

    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCastEvent")
    self:RegisterEvent("BAG_UPDATE",               "OnBagUpdateEvent")
    self:RegisterEvent("BANKFRAME_OPENED",         "OnScannerBankOpened")

    -- Periodic safety-net: catches on-use item cooldowns (trinkets, rings, etc.)
    -- that don't fire BAG_UPDATE and whose internal spell ID isn't in our set.
    -- Stopped while in a raid to avoid unnecessary load during combat.
    self.periodicHandle = self:ScheduleRepeatingTimer("OnPeriodicScan", PERIODIC_SCAN_INTERVAL)

    self:ScheduleScan("enable")
end

function CooldownScanner:DisableScanner()
    self:UnregisterEvent("PLAYER_LOGIN")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("RAID_ROSTER_UPDATE")
    self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    self:UnregisterEvent("BAG_UPDATE")
    self:UnregisterEvent("BANKFRAME_OPENED")

    if self.scanHandle then
        self:CancelTimer(self.scanHandle)
    end
    if self.periodicHandle then
        self:CancelTimer(self.periodicHandle)
        self.periodicHandle = nil
    end
    self.scanHandle  = nil
    self.scanPending = false
end

-- ============================================================
-- Event handlers
-- ============================================================

-- FIX 4: Invalidate profession cache on login/zone-change so
--         rerolled or newly-trained professions are detected.
function CooldownScanner:OnLoginEvent(event, ...)
    self.professionCache = {}
    self.bagCache        = nil
    self.bagCacheDirty   = true
    self:CheckRaidState()
    self:ScheduleScan("login")
end

-- FIX 1: Only trigger a scan when the completed cast is one of
--         our tracked crafting spells, ignoring all other casts.
-- 3.3.5 UNIT_SPELLCAST_SUCCEEDED signature: unit, spellName, rank, lineID, spellID
function CooldownScanner:OnSpellCastEvent(event, unit, spellName, rank, lineID, spellId)
    if unit ~= "player" then return end
    if craftingSpellIdSet[spellId] then
        self:ScheduleScan("spellcast")
    end
end

-- Mark the bag cache dirty AND schedule a scan so item-type cooldowns
-- (Salt Shaker, MW Saltshaker, Moonlit Ring, Lattice) are picked up
-- immediately after the player uses them. The 0.75s throttle in
-- ScheduleScan collapses rapid bag-update bursts into a single scan.
function CooldownScanner:OnBagUpdateEvent(event, ...)
    self.bagCacheDirty = true
    self:ScheduleScan("bagupdate")
end

function CooldownScanner:OnScannerBankOpened(event, ...)
    self:CacheBankItems()
    self:ScheduleScan("bank")
end

function CooldownScanner:OnPeriodicScan()
    if self.inRaid then return end
    self:ScheduleScan("periodic")
end

-- ============================================================
-- Raid state management
-- ============================================================

function CooldownScanner:CheckRaidState()
    local nowInRaid = IsInRaid() and true or false

    if nowInRaid == self.inRaid then return end  -- no change
    self.inRaid = nowInRaid

    if nowInRaid then
        -- Just entered a raid
        if not self.raidMessageShown then
            self.raidMessageShown = true
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX
                .. "Paused while in a raid. Type |cffffd700/cd scan|r for a manual update.")
        end
        -- Stop the periodic timer while in raid
        if self.periodicHandle then
            self:CancelTimer(self.periodicHandle)
            self.periodicHandle = nil
        end
    else
        -- Just left the raid — reset message flag, restart periodic timer, do a fresh scan
        self.raidMessageShown = false
        if not self.periodicHandle then
            self.periodicHandle = self:ScheduleRepeatingTimer("OnPeriodicScan", PERIODIC_SCAN_INTERVAL)
        end
        self:ScheduleScan("raidleave")
    end
end

function CooldownScanner:OnRaidRosterUpdate(event, ...)
    self:CheckRaidState()
end

-- ============================================================
-- Timer callback & scan execution
-- ============================================================

function CooldownScanner:PerformScanTimerCallback()
    self.scanHandle = nil

    if not self.scanPending then return end

    local now = GetTime()
    if now < (self.lastScanAt or 0) + (self.throttleSeconds or 0) then
        -- Still throttled; reschedule for the remaining gap.
        self:ScheduleScan("retry")
        return
    end

    self.scanPending = false
    self.lastScanAt  = now

    if Addon.Database and Addon.Database.UpdateCharacter then
        Addon.Database:UpdateCharacter()
    end
    self:ScanRegistry()
    if Addon.UI and Addon.UI.RefreshDisplay then
        Addon.UI:RefreshDisplay()
    end
end

-- ============================================================
-- Profession helpers
-- ============================================================

function CooldownScanner:HasProfessionBySpellId(professionSpellId)
    local professionName = GetSpellInfo(professionSpellId)
    if not professionName then return false end

    local num = GetNumSkillLines()
    if not num or num < 1 then return false end

    for i = 1, num do
        local name, isHeader, _, rank = GetSkillLineInfo(i)
        if name == professionName and not isHeader then
            return true, rank
        end
    end
    return false
end

-- FIX 4: Wraps HasProfessionBySpellId with a 30-second TTL cache.
--         Professions never change mid-session in normal play, so
--         walking the full skill list on every scan is pure waste.
function CooldownScanner:GetCachedProfession(professionKey, professionSpellId)
    local cached = self.professionCache[professionKey]
    if cached and (GetTime() - cached.checkedAt) < PROFESSION_CACHE_TTL then
        return cached.has, cached.rank
    end
    local has, rank = self:HasProfessionBySpellId(professionSpellId)
    self.professionCache[professionKey] = { has = has, rank = rank, checkedAt = GetTime() }
    return has, rank
end

-- ============================================================
-- Spell cooldown helper (unchanged)
-- ============================================================

function CooldownScanner:GetSpellCooldownFromSpellbook(spellId)
    -- IsSpellKnown() does not exist in WoW 3.3.5 (added in Cataclysm).
    -- Determine whether the spell is known from GetSpellCooldown return values instead.
    local start, duration, enabled = GetSpellCooldown(spellId)

    local isKnown = false
    if start and start > 0 and duration and duration > 0 then
        isKnown = true
    elseif enabled == 1 then
        isKnown = true
    end

    if not isKnown then
        return { known = false, owned = false, ready = false, remaining = 0, startTime = 0, duration = 0 }
    end

    local remaining = 0
    if enabled == 1 and start and duration and duration > 0 then
        local rem = (start + duration) - GetTime()
        if rem and rem > 0 then remaining = rem end
    end

    local nowServer  = time()
    local startServer = 0

    if duration and duration > 0 then
        if remaining > 0 then
            local elapsed = duration - remaining
            if elapsed < 0 then elapsed = 0 end
            startServer = nowServer - elapsed
        elseif start and start > 0 then
            local elapsed = GetTime() - start
            if elapsed < 0 then elapsed = 0 end
            startServer = nowServer - elapsed
        end
    end

    return {
        known     = true,
        owned     = true,
        ready     = remaining <= 0,
        remaining = remaining,
        startTime = startServer,
        duration  = duration or 0,
    }
end

-- ============================================================
-- Bag / item helpers
-- ============================================================

local function ParseItemIdFromLink(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

-- FIX 2: Bag cache — rebuilt lazily only when dirty.
function CooldownScanner:GetBagCache()
    if not self.bagCacheDirty and self.bagCache then
        return self.bagCache
    end

    local cache   = {}
    local maxBag  = NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local slots = GetContainerNumSlots(bag)
        if slots and slots > 0 then
            for slot = 1, slots do
                local id = ParseItemIdFromLink(GetContainerItemLink(bag, slot))
                if id then cache[id] = true end
            end
        end
    end

    self.bagCache      = cache
    self.bagCacheDirty = false
    return cache
end

function CooldownScanner:HasItem(itemID)
    if not itemID or itemID <= 0 then
        return false, false, false, false
    end

    local equipped = false
    if IsEquippedItem then
        equipped = IsEquippedItem(itemID) and true or false
    end

    -- FIX 2: Use cached bag contents instead of scanning every slot.
    local bagCache = self:GetBagCache()
    local inBags   = bagCache[itemID] and true or false

    local inBank     = false
    local bankOpen   = BankFrame and BankFrame:IsShown() or false
    if bankOpen then
        local bankContainer = BANK_CONTAINER or -1
        local slots = GetContainerNumSlots(bankContainer)
        if slots and slots > 0 then
            for slot = 1, slots do
                local id = ParseItemIdFromLink(GetContainerItemLink(bankContainer, slot))
                if id == itemID then inBank = true; break end
            end
        end
        if not inBank then
            local numBankBags = NUM_BANKBAGSLOTS or 0
            local startBag    = (NUM_BAG_SLOTS or 4) + 1
            for bag = startBag, startBag + numBankBags do
                local slots2 = GetContainerNumSlots(bag)
                if slots2 and slots2 > 0 then
                    for slot = 1, slots2 do
                        local id = ParseItemIdFromLink(GetContainerItemLink(bag, slot))
                        if id == itemID then inBank = true; break end
                    end
                end
                if inBank then break end
            end
        end
    end

    local inBankCache = false
    if Addon.Database and Addon.Database.GetCharacterKey and Addon.Database.GetCharacterData then
        local charKey = Addon.Database:GetCharacterKey()
        if charKey then
            local c = Addon.Database:GetCharacterData(charKey)
            if c and c.bankCache and c.bankCache[itemID] then
                inBankCache = true
            end
        end
    end

    local owned = equipped or inBags or inBank or inBankCache
    return owned, equipped, inBags, (inBank or inBankCache)
end

function CooldownScanner:GetItemCooldownRemaining(itemID)
    if not itemID or itemID <= 0 then return 0, true end
    local start, duration, enabled = GetItemCooldown(itemID)
    if not enabled or enabled == 0 then return 0, true end
    if not start or not duration or duration <= 0 then return 0, true end

    local remaining = (start + duration) - GetTime()
    if remaining and remaining > 0 then
        return remaining, false
    end
    return 0, true
end

-- FIX 3: GetItemInfo result cached in itemNameCache so repeated
--         scans never pay the lookup cost for already-seen items.
function CooldownScanner:ScanItemCooldown(itemID)
    local known = itemNameCache[itemID]
    if known == nil then
        local name = GetItemInfo(itemID)
        known = name ~= nil
        if known then
            itemNameCache[itemID] = true
        end
        -- If nil, leave it out of the cache so we retry next scan
        -- (client may not have received the item data from the server yet).
    end

    local owned           = self:HasItem(itemID)
    local remaining, ready = self:GetItemCooldownRemaining(itemID)
    if not owned then
        ready     = false
        remaining = 0
    end

    return known, owned and true or false, ready and true or false, remaining or 0
end

-- ============================================================
-- Bank cache (unchanged)
-- ============================================================

function CooldownScanner:CacheBankItems()
    if not Addon.Database or not Addon.Database.GetCharacterKey or not Addon.Database.SetBankCacheItem then return end
    local charKey = Addon.Database:GetCharacterKey()
    if not charKey then return end

    local bankOpen = BankFrame and BankFrame:IsShown() or false
    if not bankOpen then return end

    local seen = {}

    local function ScanBag(bag)
        local slots = GetContainerNumSlots(bag)
        if not slots or slots <= 0 then return end
        for slot = 1, slots do
            local id = ParseItemIdFromLink(GetContainerItemLink(bag, slot))
            if id then seen[id] = true end
        end
    end

    ScanBag(BANK_CONTAINER or -1)

    local numBankBags = NUM_BANKBAGSLOTS or 0
    local startBag    = (NUM_BAG_SLOTS or 4) + 1
    for bag = startBag, startBag + numBankBags do
        ScanBag(bag)
    end

    local registry = ns.GetCooldownEntries and ns.GetCooldownEntries() or ns.CooldownRegistry
    if not registry then return end

    for _, entries in pairs(registry) do
        if entries then
            for i = 1, #entries do
                local e = entries[i]
                if e and e.type == "item" and e.itemID and e.itemID > 0 then
                    Addon.Database:SetBankCacheItem(charKey, e.itemID, seen[e.itemID] and true or false)
                end
            end
        end
    end
end

-- ============================================================
-- Core registry scan
-- ============================================================

function CooldownScanner:ScanRegistry()
    if not Addon.Database or not Addon.Database.GetCharacterKey then return end

    local charKey = Addon.Database:GetCharacterKey()
    if not charKey then return end

    local registry = nil
    if ns.GetCooldownEntries then registry = ns.GetCooldownEntries() end
    if not registry or next(registry) == nil then
        registry = ns.CooldownRegistry or Addon.CooldownRegistry or ns.Registry
    end
    if not registry or next(registry) == nil then return end

    for professionKey, entries in pairs(registry) do
        local professionSpellId = nil
        if ns.ProfessionSpellIdsByKey then
            professionSpellId = ns.ProfessionSpellIdsByKey[professionKey]
        end

        if not professionSpellId then
            if     professionKey == "tailoring"      then professionSpellId = 3908
            elseif professionKey == "leatherworking" then professionSpellId = 2108
            elseif professionKey == "alchemy"        then professionSpellId = 2259
            end
        end

        -- FIX 4: Use the cached profession lookup.
        local hasProfession, rank = false, nil
        if professionSpellId then
            hasProfession, rank = self:GetCachedProfession(professionKey, professionSpellId)
        end

        if Addon.Database and Addon.Database.SaveProfession then
            Addon.Database:SaveProfession(charKey, professionKey, hasProfession, rank)
        end

        -- FIX 4: Skip the entire entry loop if the character doesn't
        --         have this profession — no point scanning any of its spells.
        if hasProfession and entries then
            for i = 1, #entries do
                local e = entries[i]
                if e and e.key and e.type then
                    if e.type == "spell" then
                        local rec = self:GetSpellCooldownFromSpellbook(e.spellID)
                        rec.type = "spell"
                        rec.id   = e.spellID
                        Addon.Database:SaveCooldown(charKey, professionKey, e.key, rec)

                    elseif e.type == "item" then
                        local known, owned, ready, remaining = self:ScanItemCooldown(e.itemID)
                        local startTime = 0
                        local duration  = 0
                        local start, dur = GetItemCooldown(e.itemID)
                        if start and dur then
                            duration = dur
                            if dur > 0 and remaining and remaining > 0 then
                                local nowServer = time()
                                local elapsed   = dur - remaining
                                if elapsed < 0 then elapsed = 0 end
                                startTime = nowServer - elapsed
                            end
                        end

                        Addon.Database:SaveCooldown(charKey, professionKey, e.key, {
                            type      = "item",
                            id        = e.itemID,
                            known     = known,
                            owned     = owned,
                            ready     = ready,
                            remaining = remaining,
                            startTime = startTime,
                            duration  = duration or 0,
                        })
                    end
                end
            end
        elseif not hasProfession and entries then
            -- Character doesn't have this profession: save zeroed records so
            -- the UI can still display "not learned" state correctly.
            for i = 1, #entries do
                local e = entries[i]
                if e and e.key and e.type then
                    Addon.Database:SaveCooldown(charKey, professionKey, e.key, {
                        type      = e.type,
                        id        = e.type == "spell" and e.spellID or e.itemID,
                        known     = false,
                        owned     = false,
                        ready     = false,
                        remaining = 0,
                        startTime = 0,
                        duration  = 0,
                    })
                end
            end
        end
    end
end

function CooldownScanner:HasTailoring()
    local spellId = (ns.ProfessionSpellIds and ns.ProfessionSpellIds.Tailoring) or 3908
    return self:GetCachedProfession("tailoring", spellId)
end

function CooldownScanner:ScanTailoringCooldowns()
    local results  = {}
    local entries  = ns.GetCooldownEntries and ns.GetCooldownEntries(ns.ProfessionKeys.Tailoring) or nil
    if not entries then return results end
    for i = 1, #entries do
        local e = entries[i]
        if e and e.type == "spell" and e.spellID and e.key then
            local rec = self:GetSpellCooldownFromSpellbook(e.spellID)
            results[e.key] = {
                spellId   = e.spellID,
                startTime = rec.startTime or 0,
                duration  = rec.duration  or 0,
                remaining = rec.remaining or 0,
            }
        end
    end
    return results
end

function CooldownScanner:UpdateTailoringData()
    self:ScanRegistry()
end