local addonName, ns = ...
local Addon = ns.Addon

local Notifier = Addon:NewModule("Notifier", "AceEvent-3.0", "AceTimer-3.0")
Addon.Notifier = Notifier

local POLL_INTERVAL    = 10    -- check every 10 seconds
local REMIND_INTERVAL  = 60   -- re-fire ready reminders every 60 seconds
local SNOOZE_SECONDS   = 3600 -- 1 hour snooze
local CHAT_PREFIX    = "|cff33ff99[CraftingCooldowns]|r "
local SOUND_ENABLED  = true
local SOUND_FILE     = "Sound/interface/levelup2.wav"

-- Session-only snooze table; intentionally not persisted so it clears on relog/char switch
local snoozed = {}

-- ── Helpers ────────────────────────────────────────────────────────────────

local function NotifyKey(charKey, profKey, cooldownKey)
    return charKey .. ":" .. profKey .. ":" .. cooldownKey
end

local function GetLabel(profKey, cooldownKey)
    local entries = ns.GetCooldownEntries and ns.GetCooldownEntries(profKey)
    if entries then
        for i = 1, #entries do
            if entries[i].key == cooldownKey then
                return entries[i].label
            end
        end
    end
    -- Fallback: capitalise the key
    return cooldownKey:sub(1,1):upper() .. cooldownKey:sub(2)
end

local function FormatCharName(charKey)
    local currentRealm = GetRealmName() or ""
    local name, realm  = charKey:match("^([^%-]+)%-(.+)$")
    if not name then return charKey end
    if realm == currentRealm then
        return name
    end
    return name .. " (" .. realm .. ")"
end

-- ── Module lifecycle ────────────────────────────────────────────────────────

function Notifier:OnInitialize()
    self.pollHandle = nil

    -- Notification-fired log lives in global DB so it persists across chars
    -- We only write to it from within this module
    if Addon.db and Addon.db.global then
        if not Addon.db.global.notified then
            Addon.db.global.notified = {}
        end
    end
end

function Notifier:Enable()
    if self.pollHandle then return end
    self.pollHandle = self:ScheduleRepeatingTimer("CheckCooldowns", POLL_INTERVAL)
    -- Run once immediately on login so you don't wait 10s for first check
    self:CheckCooldowns()
end

function Notifier:Disable()
    if self.pollHandle then
        self:CancelTimer(self.pollHandle)
        self.pollHandle = nil
    end
end

-- ── Core check ─────────────────────────────────────────────────────────────

function Notifier:CheckCooldowns()
    if not Addon.Database then return end
    local allChars = Addon.Database:GetAllCharacters()
    if not allChars then return end

    -- Guard: notified table must exist
    local notified = Addon.db and Addon.db.global and Addon.db.global.notified
    if not notified then return end

    local now   = time()
    local fired = 0

    for charKey, charData in pairs(allChars) do
        if charData and charData.cooldowns then
            for profKey, bucket in pairs(charData.cooldowns) do
                if type(bucket) == "table" then
                    for cooldownKey, rec in pairs(bucket) do
                        if self:EvaluateRecord(charKey, profKey, cooldownKey, rec, now, notified) then
                            fired = fired + 1
                        end
                    end
                end
            end
        end
    end

    -- Print the snooze hint once after all notifications, not once per CD
    if fired > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX
            .. "|cffaaaaaa Type |r|cffffd700/cd snooze|r|cffaaaaaa to be reminded in 1 hour.|r")
    end
end

function Notifier:Snooze(charKey, profKey, cooldownKey)
    local nKey = NotifyKey(charKey, profKey, cooldownKey)
    snoozed[nKey] = time() + SNOOZE_SECONDS

    -- Set lastFired to now so the reminder waits a full REMIND_INTERVAL after snooze expires.
    local notified = Addon.db and Addon.db.global and Addon.db.global.notified
    if notified then
        notified[nKey] = time()
    end

    local label    = GetLabel(profKey, cooldownKey)
    local charName = FormatCharName(charKey)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX
        .. "|cffffd700" .. label .. " on " .. charName .. " snoozed for 1 hour.|r")
end

function Notifier:EvaluateRecord(charKey, profKey, cooldownKey, rec, now, notified)
    if not rec or not rec.known or not rec.owned then return end

    -- A cooldown is ready if either:
    --   a) rec.ready is explicitly true (current char scanned live — expiresAt may be 0)
    --   b) expiresAt is a real timestamp that has passed (alt data from DB)
    local isReady = rec.ready == true
                 or (rec.expiresAt and rec.expiresAt > 0 and now >= rec.expiresAt)
    if not isReady then return end

    local nKey = NotifyKey(charKey, profKey, cooldownKey)

    -- Skip if snoozed
    local snoozeUntil = snoozed[nKey]
    if snoozeUntil and now < snoozeUntil then return end

    -- Re-fire every REMIND_INTERVAL seconds for as long as the cooldown stays ready.
    -- notified[nKey] stores the last time we actually fired, not the expiry time.
    local lastFired = notified[nKey] or 0
    if (now - lastFired) >= REMIND_INTERVAL then
        self:FireNotification(charKey, profKey, cooldownKey, rec)
        notified[nKey] = now
        return true  -- tells CheckCooldowns a notification fired this pass
    end
end

-- ── Notification output ────────────────────────────────────────────────────

function Notifier:FireNotification(charKey, profKey, cooldownKey, rec)
    local label      = GetLabel(profKey, cooldownKey)
    local currentKey = Addon.Database and Addon.Database.GetCharacterKey
                       and Addon.Database:GetCharacterKey()
    local isSelf     = currentKey and currentKey == charKey

    local msg
    if isSelf then
        msg = CHAT_PREFIX .. "|cff00ff00Your|r " .. label .. " is ready!"
    else
        local charName = FormatCharName(charKey)
        msg = CHAT_PREFIX .. label .. " is ready on " .. charName .. "!"
    end

    DEFAULT_CHAT_FRAME:AddMessage(msg)

    if SOUND_ENABLED then
        PlaySoundFile(SOUND_FILE)
    end
end

-- ── Snooze all ready cooldowns ─────────────────────────────────────────────
-- Called by /cd snooze from Commands.lua

function Notifier:SnoozeAll()
    if not Addon.Database then return end
    local allChars  = Addon.Database:GetAllCharacters()
    local notified  = Addon.db and Addon.db.global and Addon.db.global.notified
    if not allChars or not notified then return end

    local now   = time()
    local count = 0

    for charKey, charData in pairs(allChars) do
        if charData and charData.cooldowns then
            for profKey, bucket in pairs(charData.cooldowns) do
                if type(bucket) == "table" then
                    for cooldownKey, rec in pairs(bucket) do
                        if rec and rec.owned and rec.known then
                            local isReady = rec.ready == true
                                         or (rec.expiresAt and rec.expiresAt > 0 and now >= rec.expiresAt)
                            if isReady then
                                local nKey = NotifyKey(charKey, profKey, cooldownKey)
                                local snoozeUntil = snoozed[nKey]
                                if not snoozeUntil or now >= snoozeUntil then
                                    snoozed[nKey]  = now + SNOOZE_SECONDS
                                    notified[nKey] = now
                                    count = count + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if count > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX
            .. "|cffffd700" .. count .. " cooldown(s) snoozed for 1 hour.|r")
    else
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX
            .. "|cffaaaaaaNo ready cooldowns to snooze.|r")
    end
end