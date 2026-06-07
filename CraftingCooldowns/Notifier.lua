local addonName, ns = ...
local Addon = ns.Addon

local Notifier = Addon:NewModule("Notifier", "AceEvent-3.0", "AceTimer-3.0")
Addon.Notifier = Notifier

local POLL_INTERVAL  = 10      -- check every 10 seconds
local READY_WINDOW   = 60      -- fire if within 60s past expiry (catches offline ticks)
local SNOOZE_SECONDS = 3600    -- 1 hour snooze
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

    local now = time()

    for charKey, charData in pairs(allChars) do
        if charData and charData.cooldowns then
            for profKey, bucket in pairs(charData.cooldowns) do
                if type(bucket) == "table" then
                    for cooldownKey, rec in pairs(bucket) do
                        self:EvaluateRecord(charKey, profKey, cooldownKey, rec, now, notified)
                    end
                end
            end
        end
    end
end

function Notifier:Snooze(charKey, profKey, cooldownKey)
    local nKey = NotifyKey(charKey, profKey, cooldownKey)
    snoozed[nKey] = time() + SNOOZE_SECONDS
    local label    = GetLabel(profKey, cooldownKey)
    local charName = FormatCharName(charKey)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. label .. " on " .. charName .. " snoozed for 1 hour.")
end

function Notifier:EvaluateRecord(charKey, profKey, cooldownKey, rec, now, notified)
    -- Must be a real tracked cooldown with a duration
    if not rec or not rec.known or not rec.owned then return end
    if not rec.expiresAt or rec.expiresAt <= 0 then return end
    if not rec.duration  or rec.duration  <= 0 then return end

    local nKey     = NotifyKey(charKey, profKey, cooldownKey)
    local lastFired = notified[nKey] or 0

    -- Already fired for this specific cooldown cycle
    if lastFired == rec.expiresAt then return end

    -- Skip if the player snoozed this notification
    local snoozeUntil = snoozed[nKey]
    if snoozeUntil and now < snoozeUntil then return end

    -- Fire if: now is past expiry AND we're within the READY_WINDOW
    -- The window avoids firing for ancient cooldowns from offline alts
    -- that were ready long before the addon was even loaded.
    local secondsPast = now - rec.expiresAt
    if secondsPast >= 0 and secondsPast <= READY_WINDOW then
        self:FireNotification(charKey, profKey, cooldownKey, rec)
        notified[nKey] = rec.expiresAt
    end

    -- Edge case: cooldown is ready and has no recorded expiry in the window,
    -- but we've never fired for this expiresAt at all — mark it silently so
    -- we don't spam if the player logs in hours later with old alts ready.
    if secondsPast > READY_WINDOW then
        notified[nKey] = rec.expiresAt
    end
end

-- ── Notification output ────────────────────────────────────────────────────

function Notifier:FireNotification(charKey, profKey, cooldownKey, rec)
    local label    = GetLabel(profKey, cooldownKey)
    local charName = FormatCharName(charKey)
    local snoozeLink = "|Hccd:snooze:" .. charKey .. ":" .. profKey .. ":" .. cooldownKey
                    .. "|h|cff00ccff[Remind Me Later]|r|h"
    local msg = CHAT_PREFIX .. label .. " is ready on " .. charName .. "! " .. snoozeLink

    DEFAULT_CHAT_FRAME:AddMessage(msg)

    if SOUND_ENABLED then
        PlaySoundFile(SOUND_FILE)
    end
end

-- ── Hyperlink click handler ────────────────────────────────────────────────

hooksecurefunc("SetItemRef", function(link, text, button)
    -- link format: "ccd:snooze:CharName-Realm:profKey:cooldownKey"
    local linkType, action, charKey, profKey, cooldownKey =
        link:match("^(ccd):(snooze):([^:]+):([^:]+):([^:]+)$")
    if linkType == "ccd" and action == "snooze" and charKey and profKey and cooldownKey then
        Notifier:Snooze(charKey, profKey, cooldownKey)
    end
end)
