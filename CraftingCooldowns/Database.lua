local addonName, ns = ...

local AceDB = LibStub("AceDB-3.0")

local Addon = ns.Addon
local Database = Addon:NewModule("Database")
Addon.Database = Database

local defaults = {
  global = {
    characters = {
    },
  },
  profile = {
    ui = {
      shown = false,
      point = "CENTER",
      relativePoint = "CENTER",
      x = 0,
      y = 0,
      scale = 1,
      locked = false,
    },
  },
}

local function EnsureCharacter(db, charKey)
  local chars = db.global.characters
  local c = chars[charKey]
  if not c then
    c = {
      lastScan = 0,
      professions = {},
      cooldowns = {
        tailoring = {},
        leatherworking = {},
        alchemy = {},
      },
      bankCache = {},
    }
    chars[charKey] = c
  end
  if not c.professions then c.professions = {} end
  if not c.cooldowns then c.cooldowns = {} end
  if not c.cooldowns.tailoring then c.cooldowns.tailoring = {} end
  if not c.cooldowns.leatherworking then c.cooldowns.leatherworking = {} end
  if not c.bankCache then c.bankCache = {} end
  if not c.lastScan then c.lastScan = 0 end
  return c
end

function Database:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("CraftingCooldownsDB", defaults, true)
    Addon.db = self.db
    
    -- Now you can safely call your database update methods
    self:UpdateCharacter()
end

local function SplitCharacterKey(charKey)
  if not charKey then return nil, nil end
  local name, realm = charKey:match("^([^%-]+)%-(.+)$")
  return name, realm
end

function Database:GetCharacterKey()
  local name = UnitName("player")
  local realm = GetRealmName()
  if not name or not realm then return nil end
  return name .. "-" .. realm
end

function Database:UpdateCharacter()
  if not self.db then return end

  local charKey = self:GetCharacterKey()
  if not charKey then return end

  local c = EnsureCharacter(self.db, charKey)
  local name, realm = SplitCharacterKey(charKey)
  c.name = name
  c.realm = realm
  c.class = select(2, UnitClass("player"))
  local faction = UnitFactionGroup("player")
  c.faction = faction or "Unknown"
  c.lastSeen = time()
end

function Database:DeleteCharacter(charKey)
  if not self.db or not charKey then return end
  self.db.global.characters[charKey] = nil
end

function Database:SaveProfession(charKey, professionKey, isKnown, rank)
  if not self.db or not charKey or not professionKey then return end
  local c = EnsureCharacter(self.db, charKey)

  local p = c.professions[professionKey]
  if not p then
    p = {}
    c.professions[professionKey] = p
  end

  if isKnown == nil then isKnown = true end
  p.known = isKnown and true or false
  if rank ~= nil then p.rank = rank end

  c.lastScan = time()
end

function Database:SaveCooldown(charKey, professionKey, cooldownKey, startTime, duration, remaining, id, known, owned, ready, cooldownType)
  if not self.db or not charKey or not professionKey or not cooldownKey then return end
  local c = EnsureCharacter(self.db, charKey)

  local bucket = c.cooldowns[professionKey]
  if not bucket then
    bucket = {}
    c.cooldowns[professionKey] = bucket
  end

  local r = bucket[cooldownKey]
  if not r then
    r = {}
    bucket[cooldownKey] = r
  end

  if type(startTime) == "table" then
    local rec = startTime
    r.startTime = rec.startTime or 0
    r.duration = rec.duration or 0
    r.remaining = rec.remaining or 0
    r.expiresAt = (r.startTime or 0) + (r.duration or 0)
    r.updatedAt = time()
    if rec.id ~= nil then r.id = rec.id end
    if rec.type ~= nil then r.type = rec.type end
    if rec.known ~= nil then r.known = rec.known and true or false end
    if rec.owned ~= nil then r.owned = rec.owned and true or false end
    if rec.ready ~= nil then r.ready = rec.ready and true or false end
    c.lastScan = r.updatedAt
    return
  end

  if not startTime then startTime = 0 end
  if not duration then duration = 0 end
  if not remaining then remaining = 0 end

  r.startTime = startTime
  r.duration = duration
  r.remaining = remaining
  r.expiresAt = startTime + duration
  r.updatedAt = time()
  if id ~= nil then r.id = id end
  if cooldownType ~= nil then r.type = cooldownType end
  if known ~= nil then r.known = known and true or false end
  if owned ~= nil then r.owned = owned and true or false end
  if ready ~= nil then r.ready = ready and true or false end

  c.lastScan = r.updatedAt
end

function Database:SetBankCacheItem(charKey, itemID, owned)
  if not self.db or not charKey or not itemID then return end
  local c = EnsureCharacter(self.db, charKey)
  if owned then
    c.bankCache[itemID] = true
  else
    c.bankCache[itemID] = nil
  end
end

function Database:GetCharacterData(charKey)
  if not self.db or not charKey then return nil end
  local chars = self.db.global.characters
  return chars and chars[charKey] or nil
end

function Database:GetAllCharacters()
  if not self.db then return {} end
  return self.db.global.characters or {}
end

function Database:GetCharacters()
  if not self.db then return {} end
  local chars = self.db.global.characters or {}
  local curRealm = GetRealmName() or ""

  local list = {}
  for charKey, charData in pairs(chars) do
    local name, realm = SplitCharacterKey(charKey)
    list[#list + 1] = {
      key = charKey,
      name = name or charKey,
      realm = realm or "",
      data = charData,
    }
  end

  table.sort(list, function(a, b)
    local aCur = a.realm == curRealm
    local bCur = b.realm == curRealm
    if aCur ~= bCur then
      return aCur
    end
    if a.realm ~= b.realm then
      return a.realm < b.realm
    end
    return a.name < b.name
  end)

  return list
end
