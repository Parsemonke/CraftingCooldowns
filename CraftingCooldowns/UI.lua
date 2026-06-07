local addonName, ns = ...

local Addon = ns.Addon

-- Create this file as an official Ace3 module so Core.lua can boot it
local UI = Addon:NewModule("UI")
Addon.UI = UI

function UI:Initialize()
    ---print("|cff00ffff[CC Debug]|r: UI:Initialize() has started execution!")
    self.columns = {
        { key = "character", label = "Character", width = 140, defaultWidth = 140 },
        { key = "mooncloth", label = "Mooncloth", width = 80, defaultWidth = 80, profession = ns.ProfessionKeys.Tailoring },
        { key = "saltShaker", label = "Salt Shaker", width = 90, defaultWidth = 90, profession = ns.ProfessionKeys.Leatherworking },
        { key = "customTrinket", label = "Trinket CD", width = 80, defaultWidth = 80, profession = ns.ProfessionKeys.Leatherworking },
        { key = "transmuteArcanite", label = "Arcanite", width = 80, defaultWidth = 80, profession = ns.ProfessionKeys.Alchemy },
        { key = "alchemyItem", label = "Alchemy Item", width = 90, defaultWidth = 90, profession = ns.ProfessionKeys.Alchemy },
    }
    self.rows = {}
    self.renderedRows = {} -- Table to recycle font strings
    ---print("|cff00ffff[CC Debug]|r: Calling CreateMainWindow()...")
    self:CreateMainWindow()
    ---print("|cff00ffff[CC Debug]|r: UI:Initialize() finished successfully!")
end

local function ApplyBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 0,
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0.08, 0.08, 0.08, 0.92)
    frame:SetBackdropBorderColor(0.18, 0.18, 0.18, 1)
end

function UI:RestorePosition()
    if not Addon.db or not Addon.db.profile or not Addon.db.profile.ui then return end
    local p = Addon.db.profile.ui
    self.frame:ClearAllPoints()
    self.frame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER", p.x or 0, p.y or 0)
    self.frame:SetScale(p.scale or 1)
end

function UI:SavePosition()
    if not Addon.db or not Addon.db.profile or not Addon.db.profile.ui then return end
    local p = Addon.db.profile.ui
    local point, _, relativePoint, x, y = self.frame:GetPoint(1)
    p.point = point
    p.relativePoint = relativePoint
    p.x = x
    p.y = y
end

-- Rebuilds data from the database and maps it into UI.rows
function UI:RefreshDisplay()
    self.rows = {}

    local charTable = nil
    if Addon.Database and Addon.Database.db and Addon.Database.db.global then
        charTable = Addon.Database.db.global.characters
    elseif Addon.db and Addon.db.global then
        charTable = Addon.db.global.characters
    end

    if not charTable or next(charTable) == nil then
        table.insert(self.rows, { character = "|cffaaaaaaNo Characters|r" })
        self:UpdateScrollFrame()
        return
    end

    -- Track which columns are actively displaying real cooldown tracking data
    local activeColumns = { character = true }

    for charKey, charData in pairs(charTable) do
        local displayName = charKey:match("([^-]+)") or charKey

        -- Generate text entries
        local mText = self:GetCooldownText(charKey, ns.ProfessionKeys.Tailoring, "mooncloth")
        local sText = self:GetCooldownText(charKey, ns.ProfessionKeys.Leatherworking, "saltShaker")
        local cText = self:GetCooldownText(charKey, ns.ProfessionKeys.Leatherworking, "customTrinket")
        local tText = self:GetCooldownText(charKey, ns.ProfessionKeys.Alchemy, "transmuteArcanite")
        local aText = self:GetCooldownText(charKey, ns.ProfessionKeys.Alchemy, "alchemyItem")

        -- Skip characters that have no tracked cooldowns at all
        if mText == "-" and sText == "-" and cText == "-" and tText == "-" and aText == "-" then
            -- no relevant professions on this char — omit from the list
        else
            -- Flag column as active if it's showing something other than an empty dash
            if mText ~= "-" then activeColumns["mooncloth"] = true end
            if sText ~= "-" then activeColumns["saltShaker"] = true end
            if cText ~= "-" then activeColumns["customTrinket"] = true end
            if tText ~= "-" then activeColumns["transmuteArcanite"] = true end
            if aText ~= "-" then activeColumns["alchemyItem"] = true end

            table.insert(self.rows, {
                character = displayName,
                mooncloth = mText,
                saltShaker = sText,
                customTrinket = cText,
                transmuteArcanite = tText,
                alchemyItem = aText,
            })
        end
    end

    table.sort(self.rows, function(a, b) return a.character < b.character end)

    -- DYNAMIC WIDTH RECALCULATION
    local newWindowWidth = 0
    for _, col in ipairs(self.columns) do
        if activeColumns[col.key] then
            col.width = col.defaultWidth or 100 -- Restore original size configurations smoothly
        else
            col.width = 0 -- Collapse unused columns completely
        end
        newWindowWidth = newWindowWidth + col.width
    end

    -- Update window frame wrapper dimensions snugly to match active columns
    if self.frame then
        local targetWidth = newWindowWidth + 38
        if targetWidth < 220 then targetWidth = 220 end -- Keep a safe minimum width for title string
        self.frame:SetWidth(targetWidth)
    end

    self:UpdateScrollFrame()
end

-- Dynamically handles the generation of FontStrings inside the scrolling child frame
function UI:UpdateScrollFrame()
    local rowHeight = 20
    local startY = 0

    -- 1. REALIGN THE HEADER FONTSTRINGS MATCHING NEW WIDTH ENTRIES
    local headerXOffset = 0
    if self.headerTexts then
        for i = 1, #self.columns do
            local col = self.columns[i]
            local fs = self.headerTexts[i]
            
            if fs then
                if col.width == 0 then
                    fs:Hide()
                else
                    fs:ClearAllPoints()
                    fs:SetPoint("LEFT", self.header, "LEFT", headerXOffset, 0)
                    fs:SetWidth(col.width)
                    fs:Show()
                    
                    headerXOffset = headerXOffset + col.width
                end
            end
        end
    end

    -- 2. Hide all old rows from the visible display area to clear artifacts
    for _, textGroup in ipairs(self.renderedRows) do
        for _, fs in pairs(textGroup) do
            fs:Hide()
        end
    end

    -- 3. Render each row entry
    for rowIndex, rowData in ipairs(self.rows) do
        if not self.renderedRows[rowIndex] then
            self.renderedRows[rowIndex] = {}
        end

        local xOffset = 0
        for colIndex, col in ipairs(self.columns) do
            local fs = self.renderedRows[rowIndex][col.key]
            
            if not fs then
                fs = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                self.renderedRows[rowIndex][col.key] = fs
            end

            -- If the column width is 0, completely drop the font string from view
            if col.width == 0 then
                fs:Hide()
            else
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", self.content, "TOPLEFT", xOffset, -(startY + ((rowIndex - 1) * rowHeight) + 10))
                fs:SetWidth(col.width)
                fs:SetJustifyH(col.key == "character" and "LEFT" or "CENTER")
                
                -- Set the row content text data cleanly
                fs:SetText(rowData[col.key] or "-")
                fs:Show()

                xOffset = xOffset + col.width
            end
        end
    end

    -- Update scrolling canvas dimensions based on row counts
    local totalHeight = #self.rows * rowHeight + 10
    self.content:SetHeight(totalHeight < 1 and 1 or totalHeight)
end

function UI:CreateMainWindow()
    local frame = CreateFrame("Frame", "CraftingCooldownsFrame", UIParent)
    self.frame = frame

    frame:SetSize(560, 260)
    ApplyBackdrop(frame)
    
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(f)
        if Addon.db and Addon.db.profile and Addon.db.profile.ui and not Addon.db.profile.ui.locked then
            f:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        UI:SavePosition()
    end)

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        UI:Toggle()
    end)
    self.closeBtn = closeBtn

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    title:SetText("CraftingCooldowns")
    self.title = title

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -30)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -30)
    header:SetHeight(18)
    self.header = header

    self.headerTexts = {}
    local x = 0
    for i = 1, #self.columns do
        local col = self.columns[i]
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH(col.key == "character" and "LEFT" or "CENTER")
        fs:SetPoint("LEFT", header, "LEFT", x, 0)
        fs:SetWidth(col.width)
        fs:SetText(col.label)
        self.headerTexts[i] = fs
        x = x + col.width
    end
    self.totalWidth = x
    local w = (self.totalWidth or 560) + 48
    if w < 560 then w = 560 end
    frame:SetWidth(w)

    local scroll = CreateFrame("ScrollFrame", "CraftingCooldownsScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 10)
    self.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetWidth(self.totalWidth or 1)
    content:SetHeight(1)
    scroll:SetScrollChild(content)
    self.content = content

    self:RestorePosition()

    if Addon.db and Addon.db.profile and Addon.db.profile.ui and Addon.db.profile.ui.shown then
        frame:Show()
        self:RefreshDisplay()
    else
        frame:Hide()
    end
end

-- Handles opening/closing the UI panel frame cleanly
function UI:Toggle()
    if not self.frame then
        self:CreateMainWindow()
    end

    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:RefreshDisplay()   
        self.frame:Show()
    end
end

function UI:GetCooldownText(charKey, professionKey, cooldownKey)
    if not Addon.Database or not Addon.Database.GetCharacterData then return "-" end
    
    local charData = Addon.Database:GetCharacterData(charKey)
    if not charData or not charData.cooldowns then return "-" end

    local bucket = charData.cooldowns[professionKey]
    if not bucket then return "-" end

    local cd = bucket[cooldownKey]
    if not cd then return "-" end

    -- GATING RULE: If you don't own the item, or don't know the spell, it's NOT ready!
    if cd.type == "spell" and not cd.known then return "-" end
    if cd.type == "item" and not cd.owned then return "-" end

    -- Determine readiness based on real timestamps
    local nowServer = time()
    local expiresAt = cd.expiresAt or ((cd.startTime or 0) + (cd.duration or 0))
    local remaining = expiresAt - nowServer

    if cd.ready == true or remaining <= 0 then
        return "|cff00ff00Ready|r"
    end

    -- Calculate D:H:M
    local days = math.floor(remaining / 86400)
    local hours = math.floor((remaining % 86400) / 3600)
    local minutes = math.floor((remaining % 3600) / 60)

    -- Build the string only for relevant units (e.g., skip days if 0)
    local result = ""
    if days > 0 then
        result = string.format("%dd:%02dh:%02dm", days, hours, minutes)
    elseif hours > 0 then
        result = string.format("%dh:%02dm", hours, minutes)
    else
        result = string.format("%dm", minutes)
    end
    
    return result
end
