local addonName, ns = ...

ns.ProfessionKeys = {
  Tailoring = "tailoring",
  Leatherworking = "leatherworking",
  Alchemy = "alchemy",
}

ns.ProfessionSpellIds = {
  Tailoring = 3908,
  Leatherworking = 2108,
  Alchemy = 2259,
}

ns.ProfessionSpellIdsByKey = {
  [ns.ProfessionKeys.Tailoring] = ns.ProfessionSpellIds.Tailoring,
  [ns.ProfessionKeys.Leatherworking] = ns.ProfessionSpellIds.Leatherworking,
  [ns.ProfessionKeys.Alchemy] = ns.ProfessionSpellIds.Alchemy,
}

ns.CooldownRegistry = {
  [ns.ProfessionKeys.Tailoring] = {
    { key = "mooncloth",             label = "Mooncloth",   type = "spell", spellID = 18560 },
    { key = "signetMoonlitWater",    label = "Moonlit Ring", type = "item",  itemID  = 60603 },
  },
  [ns.ProfessionKeys.Leatherworking] = {
    { key = "saltShaker", label = "Salt Shaker", type = "item", itemID = 15846 },
    { key = "customTrinket", label = "MW Saltshaker", type = "item", itemID = 60571 },
  },
  [ns.ProfessionKeys.Alchemy] = {
    { key = "transmuteArcanite", label = "Arcanite", type = "spell", spellID = 17187 },
    { key = "alchemyItem", label = "Lattice", type = "item", itemID = 60686 },
  },
}

function ns.RegisterCooldown(professionKey, entry)
  if not professionKey or not entry then return end
  if not ns.CooldownRegistry[professionKey] then
    ns.CooldownRegistry[professionKey] = {}
  end
  table.insert(ns.CooldownRegistry[professionKey], entry)
end

function ns.GetCooldownEntries(professionKey)
  if professionKey then
    return ns.CooldownRegistry[professionKey] or {}
  end
  return ns.CooldownRegistry
end

ns.CommandAliases = {
  "cd",
  "ccd",
  "craftingcooldown",
  "craftingcd",
}
