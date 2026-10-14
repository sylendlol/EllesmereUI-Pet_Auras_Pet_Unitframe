if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIPetAuras.lua
--  Dworak > Pet Auras: your pet's buffs and debuffs next to the pet frame
--  (EllesmereUI's own pet frame, or any other unit frame addon's), in two
--  blocks that are placed separately.
--
--  * The client draws the auras itself (AuraContainer +
--    CustomAuraContainerTemplate), in combat and with secret auras too. The
--    addon never reads aura data: no taint, no Lua work per aura event.
--  * Layout and style writes happen out of combat (deferred to combat end).
--  * Settings live in the EllesmereUI profile store (EllesmereUI.Lite.NewDB),
--    like every Dworak module, so they follow EllesmereUI profiles.
--
--  Its own addon: it registers its row in the "Dworak" section through
--  EllesmereUIDworak. The page and its live preview are in
--  EllesmereUIPetAuras_Options.lua.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EllesmereUI = _G.EllesmereUI
if not (EllesmereUI and EllesmereUI.Lite) then return end

local floor, max, min = math.floor, math.max, math.min
local InCombatLockdown = InCombatLockdown

local PA = { groups = {}, moving = false }
ns.PA = PA
PA.FOLDER = ADDON_NAME

local UNIT = "pet"
local GROUP_KEY = "main"
local FREE = "__NONE__"     -- frameName: not anchored, free position on the screen
PA.FREE = FREE

-------------------------------------------------------------------------------
--  Settings (EllesmereUI profile store)
-------------------------------------------------------------------------------
local function GroupDefaults(side, y, border)
    return {
        enabled      = true,
        side         = side,       -- TOP = above the pet frame, BOTTOM = below
        growX        = "RIGHT",    -- RIGHT = left to right, LEFT = right to left
        x = 0, y = y,
        size = 20, spacing = 2, perRow = 8, max = 16,
        border       = border,     -- border thickness in pixels
        sortMethod   = "APPLIED",  -- APPLIED / EXPIRATION / NAME / BLIZZARD
        sortReverse  = false,
        showTimer    = true,
        timerFont    = "__global", -- EllesmereUI font key ("__global" = the Unit Frames font)
        timerSize    = 10,
        timerOutline = "outline",  -- __global / none (drop shadow) / outline / thick
        timerPoint   = "CENTER",   -- TOP / CENTER / BOTTOM inside the icon
        timerX = 0, timerY = 0,
        countSize    = 10,
    }
end

local DEFAULTS = {
    profile = {
        buffs     = GroupDefaults("TOP", 2, 1),
        debuffs   = GroupDefaults("BOTTOM", -2, 2),
        frameName = "",            -- "" = auto detect, FREE = no anchor, else a frame name
        imported  = false,         -- old EUIPetAurasDB settings taken over
    },
}
DEFAULTS.profile.buffs.onlyMine = false
DEFAULTS.profile.debuffs.onlyDispellable = false
PA.DEFAULTS = DEFAULTS.profile
PA.GROUP_KEYS = { "buffs", "debuffs" }

local SV_NAME = "EllesmereUIPetAurasDB"
local db = EllesmereUI.Lite.NewDB(SV_NAME, DEFAULTS)

-- The live profile table, re-opened after an EllesmereUI profile swap.
function PA.DB()
    local active = (EllesmereUIDB and EllesmereUIDB.activeProfile) or "Default"
    if db._profileName ~= active then
        db = EllesmereUI.Lite.NewDB(SV_NAME, DEFAULTS)
    end
    return db.profile
end
local DB = PA.DB

function PA.S(key) return DB()[key] end

function PA.ResetSettings()
    local d = DB()
    wipe(d)
    EllesmereUI.Lite.DeepMergeDefaults(d, DEFAULTS.profile)
    d.imported = true -- a reset never pulls the old settings in again
    PA.anchorFrame = nil
    PA.Attach()
end

function PA.Print(msg)
    EllesmereUI.Print(PA.AccentHex() .. "Pet Auras:|r " .. tostring(msg))
end

function PA.Accent()
    local a = EllesmereUI.ELLESMERE_GREEN
    if type(a) == "table" and a.r then return a.r, a.g, a.b end
    return 0.05, 0.82, 0.62
end

function PA.AccentHex()
    local r, g, b = PA.Accent()
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-------------------------------------------------------------------------------
--  Fonts (EllesmereUI font keys; "__global" = the Unit Frames font)
-------------------------------------------------------------------------------
local FONT_MODULE = "unitFrames"

local function TimerFont(s)
    local path
    if s.timerFont and s.timerFont ~= "__global" and EllesmereUI.ResolveFontName then
        path = EllesmereUI.ResolveFontName(s.timerFont)
    end
    path = path or EllesmereUI.GetFontPath(FONT_MODULE) or STANDARD_TEXT_FONT
    local flag
    if s.timerOutline == "__global" then
        flag = EllesmereUI.GetFontOutlineFlag(FONT_MODULE)
    else
        flag = EllesmereUI.OutlineFlagForMode(s.timerOutline or "outline")
    end
    return path, flag or ""
end

local function SetFontSafe(fs, path, size, flag)
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, flag == "") end
    if not fs:SetFont(path, size, flag) then
        fs:SetFont(STANDARD_TEXT_FONT, size, EllesmereUI.StripSlugFlag and EllesmereUI.StripSlugFlag(flag) or "")
    end
    if flag == "" then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

function PA.StyleTimer(cd, s)
    cd:SetHideCountdownNumbers(not s.showTimer)
    local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
    if not fs then return end
    local path, flag = TimerFont(s)
    SetFontSafe(fs, path, s.timerSize or 10, flag)
    fs:ClearAllPoints()
    local p = s.timerPoint or "CENTER"
    fs:SetPoint(p, cd, p, s.timerX or 0, s.timerY or 0)
end

function PA.StyleCount(fs, s)
    local path, flag = TimerFont(s)
    SetFontSafe(fs, path, s.countSize or 10, flag)
end

function PA.Inset(tex, parent, px)
    tex:ClearAllPoints()
    if PixelUtil then
        PixelUtil.SetPoint(tex, "TOPLEFT", parent, "TOPLEFT", px, -px)
        PixelUtil.SetPoint(tex, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", -px, px)
    else
        tex:SetPoint("TOPLEFT", parent, "TOPLEFT", px, -px)
        tex:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -px, px)
    end
end

-------------------------------------------------------------------------------
--  Block geometry: the corner of the block that sits on the pet frame, the
--  pet frame's corner, and the growth directions.
-------------------------------------------------------------------------------
function PA.Geometry(s)
    local vert  = (s.side == "TOP") and "BOTTOM" or "TOP"
    local horiz = (s.growX == "LEFT") and "RIGHT" or "LEFT"
    return vert .. horiz, (s.side == "TOP" and "TOP" or "BOTTOM") .. horiz,
        (s.growX == "LEFT") and -1 or 1, (s.side == "TOP") and 1 or -1
end

function PA.LineWidth(s)
    return s.perRow * s.size + (s.perRow - 1) * s.spacing
end

-------------------------------------------------------------------------------
--  Pet frame: auto detect, a chosen frame, or none (free position)
-------------------------------------------------------------------------------
-- EllesmereUI's own pet frame first.
local KNOWN_NAMES = {
    "EllesmereUIUnitFrames_Pet", "EllesmereUI_PetFrame", "EllesmereUIPetFrame",
    "EUI_PetFrame", "EUIPetFrame", "oUF_EllesmereUIPet", "oUF_EllesmereUI_Pet",
}

-- Friendly names for the pet frames of popular unit frame addons.
local KNOWN_LABELS = {
    EllesmereUIUnitFrames_Pet = "EllesmereUI",
    PetFrame                  = "Blizzard default",
    ElvUF_Pet                 = "ElvUI",
    SUFUnitpet                = "Shadowed Unit Frames",
    PitBull4_Frames_Pet       = "PitBull 4",
    XPerl_Player_Pet          = "Z-Perl",
    UUF_Pet                   = "Unhalted Unit Frames",
    oUF_Pet                   = "oUF",
    LUFUnitpet                = "Luna Unit Frames",
    TukuiPetFrame             = "Tukui",
}

local function SafeName(f)
    local ok, name = pcall(f.GetName, f)
    return ok and name or nil
end

function PA.IsPetUnitFrame(f)
    if f.IsForbidden and f:IsForbidden() then return false end
    local ok, unit = pcall(f.GetAttribute, f, "unit")
    return ok and unit == "pet"
end

function PA.FrameLabel(name)
    if not name then return "unnamed frame" end
    if KNOWN_LABELS[name] then return KNOWN_LABELS[name] end
    if name:find("Ellesmere") or name:find("^EUI") then return "EllesmereUI" end
    if name:find("^ElvUF") then return "ElvUI" end
    if name:find("^SUF") then return "Shadowed Unit Frames" end
    return name
end

-- Every named frame that shows the "pet" unit, best first:
-- EllesmereUI > other addons > Blizzard default.
function PA.ScanPetFrames()
    local list, seen = {}, {}
    local function add(f, rank)
        local name = f and SafeName(f)
        if name and not seen[name] then
            seen[name] = true
            list[#list + 1] = { frame = f, name = name, label = PA.FrameLabel(name), rank = rank }
        end
    end
    for i = 1, #KNOWN_NAMES do add(_G[KNOWN_NAMES[i]], 1) end
    local f = EnumerateFrames()
    while f do
        if PA.IsPetUnitFrame(f) then
            local name = SafeName(f)
            if name and name ~= "PetFrame" and (f:GetWidth() or 0) > 20 then
                add(f, (name:find("Ellesmere") or name:find("^EUI")) and 1 or 2)
            end
        end
        f = EnumerateFrames(f)
    end
    if PetFrame then add(PetFrame, 3) end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.name < b.name
    end)
    return list
end

local function FindPetFrame()
    local wanted = DB().frameName
    if wanted == FREE then return nil end
    if wanted and wanted ~= "" then
        -- A chosen frame: wait for it rather than jump to another one.
        return _G[wanted]
    end
    local list = PA.ScanPetFrames()
    return list[1] and list[1].frame or nil
end

function PA.GetAnchorName()
    return PA.anchorFrame and (SafeName(PA.anchorFrame) or "unnamed frame") or nil
end

-------------------------------------------------------------------------------
--  Real aura buttons (the client calls this once per button it creates)
-------------------------------------------------------------------------------
local DISPEL_STYLE_PRESERVE =
    (Enum and Enum.CustomAuraButtonDispelTypeTextureStyle and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset) or 3

local function MakeInitializer(key)
    local isDebuff = key == "debuffs"
    return function(button)
        local s = DB()[key]
        button:SetSize(s.size, s.size)

        local border = button:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints()
        border:SetColorTexture(0, 0, 0, 1)

        -- Debuffs: the client colors the border by dispel type (combat too).
        if isDebuff then
            local dispel = button:CreateTexture(nil, "BORDER")
            dispel:SetAllPoints()
            dispel:SetColorTexture(1, 1, 1, 1)
            button:AddDispelTypeTexture(dispel, {
                style = DISPEL_STYLE_PRESERVE,
                showWhenHarmful = true,
                showWithoutDispelType = true,
            })
        end

        local icon = button:CreateTexture(nil, "ARTWORK")
        PA.Inset(icon, button, s.border)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button:SetIcon(icon)
        button.dwpaIcon = icon

        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetReverse(true)
        cd:SetDrawEdge(false)
        PA.StyleTimer(cd, s)
        button:SetDurationCooldown(cd)
        button.dwpaCooldown = cd

        local overlay = CreateFrame("Frame", nil, button)
        overlay:SetAllPoints()
        overlay:SetFrameLevel(cd:GetFrameLevel() + 2)
        local count = overlay:CreateFontString(nil, "OVERLAY")
        count:SetPoint("BOTTOMRIGHT", 1, 0)
        PA.StyleCount(count, s)
        button:SetApplicationCount(count)
        button.dwpaCount = count
    end
end

local function FilterFor(key, s)
    if key == "debuffs" then
        -- RAID_PLAYER_DISPELLABLE = what you can dispel (plain RAID = raid-relevant).
        return s.onlyDispellable and "HARMFUL|RAID_PLAYER_DISPELLABLE" or "HARMFUL"
    end
    return s.onlyMine and "HELPFUL|PLAYER" or "HELPFUL"
end

local function LayoutOptions(s)
    return { elementSpacing = s.spacing, lineSpacing = s.spacing, elementWidth = s.size, elementHeight = s.size }
end

local SORT_METHODS = {
    APPLIED    = "AuraInstanceIDOnly",  -- order of application: new auras go to the end
    EXPIRATION = "ExpirationOnly",      -- shortest remaining first, permanent last
    NAME       = "NameOnly",
    BLIZZARD   = "Default",             -- Blizzard default (your own auras first)
}

local function SortArgs(s)
    local M, D = AuraContainerSortMethod, AuraContainerSortDirection
    if not (M and D) then return nil, nil end
    local m = M[SORT_METHODS[s.sortMethod] or "AuraInstanceIDOnly"] or M.Default
    return m, s.sortReverse and D.Reverse or D.Normal
end

-------------------------------------------------------------------------------
--  Placeholder auras: move mode on the real pet frame, and the options preview
-------------------------------------------------------------------------------
-- { spellID, duration (0 = permanent), stacks, dispel type }
local PLACEHOLDERS = {
    buffs = {
        { 136, 10, 0 }, { 774, 12, 0 }, { 21562, 0, 0 }, { 1126, 0, 0 },
        { 19574, 15, 0 }, { 272790, 8, 3 }, { 1459, 0, 0 }, { 6673, 0, 0 },
        { 53480, 12, 0 }, { 1022, 10, 0 }, { 264667, 40, 0 }, { 1044, 10, 0 },
    },
    debuffs = {
        { 589, 18, 0, "Magic" }, { 980, 18, 0, "Curse" }, { 2818, 12, 3, "Poison" },
        { 55095, 24, 0, "Disease" }, { 772, 15, 0, nil }, { 118, 8, 0, "Magic" },
        { 702, 120, 0, "Curse" }, { 3409, 12, 0, "Poison" }, { 34914, 21, 0, "Magic" },
        { 6788, 15, 0, nil }, { 8680, 12, 2, "Poison" }, { 1490, 120, 0, "Curse" },
    },
}
PA.PLACEHOLDER_MAX = 12

local FALLBACK_DISPEL = {
    Magic = { 0.20, 0.60, 1.00 }, Curse = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 }, Poison = { 0.00, 0.60, 0.00 }, None = { 0.80, 0.00, 0.00 },
}
local function DispelColor(dtype)
    if AuraUtil and AuraUtil.GetAuraBorderColor then
        local ok, c = pcall(AuraUtil.GetAuraBorderColor, dtype)
        if ok and c and c.GetRGB then return c:GetRGB() end
    end
    local c = FALLBACK_DISPEL[dtype or "None"] or FALLBACK_DISPEL.None
    return c[1], c[2], c[3]
end

local function SpellIcon(id)
    local tex
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, id)
        if ok then tex = t end
    end
    if not tex and GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, id)
        if ok then tex = t end
    end
    return tex or 134400
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and type(n) == "string" then return n end
    end
    return tostring(id)
end

-- The placeholders in the order the real auras would sort (a fixed fake
-- "applied" order; Remaining Time by duration, permanent last; Name A-Z).
local sortedCache = {}
local function SortedPlaceholders(key, s)
    local ck = key .. (s.sortMethod or "") .. (s.sortReverse and "R" or "")
    local list = sortedCache[ck]
    if list then return list end
    list = {}
    for i, d in ipairs(PLACEHOLDERS[key]) do list[i] = d end
    local idx = {}
    for i, d in ipairs(list) do idx[d] = i end
    if s.sortMethod == "EXPIRATION" then
        table.sort(list, function(a, b)
            local da = a[2] > 0 and a[2] or math.huge
            local db2 = b[2] > 0 and b[2] or math.huge
            if da ~= db2 then return da < db2 end
            return idx[a] < idx[b]
        end)
    elseif s.sortMethod == "NAME" then
        table.sort(list, function(a, b)
            local na, nb = SpellName(a[1]), SpellName(b[1])
            if na ~= nb then return na < nb end
            return idx[a] < idx[b]
        end)
    end
    if s.sortReverse then
        local n = #list
        for i = 1, floor(n / 2) do list[i], list[n - i + 1] = list[n - i + 1], list[i] end
    end
    sortedCache[ck] = list
    return list
end

local function PH_OnCooldownDone(self)
    if self.dur and self.dur > 0 and self:IsVisible() then self:SetCooldown(GetTime(), self.dur) end
end

local function NewPlaceholder(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.cd:SetReverse(true)
    b.cd:SetDrawEdge(false)
    b.cd:SetScript("OnCooldownDone", PH_OnCooldownDone)
    local ov = CreateFrame("Frame", nil, b)
    ov:SetAllPoints()
    ov:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.count = ov:CreateFontString(nil, "OVERLAY")
    b.count:SetPoint("BOTTOMRIGHT", 1, 0)
    b:EnableMouse(false)
    b:Hide()
    return b
end

-- How many placeholders a group shows.
function PA.PlaceholderCount(s)
    return min(s.max, PA.PLACEHOLDER_MAX)
end

-- Lays n placeholder icons out in `block` (whose corner `point` is the flow
-- corner), the way the client lays out the real ones. pool: the icon list.
function PA.LayoutPlaceholders(pool, block, key, s, n)
    local list = SortedPlaceholders(key, s)
    local point, _, gx, gy = PA.Geometry(s)
    local step = s.size + s.spacing
    local perRow = max(1, s.perRow)
    for i = 1, n do
        local b = pool[i]
        if not b then b = NewPlaceholder(block); pool[i] = b end
        local d = list[((i - 1) % #list) + 1]
        if b.data ~= d then
            b.data = d
            b.icon:SetTexture(SpellIcon(d[1]))
            b.cd.dur = d[2]
            if key == "debuffs" then
                b.border:SetColorTexture(DispelColor(d[4] or "None"))
            else
                b.border:SetColorTexture(0, 0, 0, 1)
            end
            b.fresh = true
        end
        local col = (i - 1) % perRow
        local row = floor((i - 1) / perRow)
        b:SetSize(s.size, s.size)
        b:ClearAllPoints()
        b:SetPoint(point, block, point, col * step * gx, row * step * gy)
        PA.Inset(b.icon, b, s.border)
        PA.StyleTimer(b.cd, s)
        PA.StyleCount(b.count, s)
        b.count:SetText((d[3] or 0) > 1 and d[3] or "")
        if b.fresh or not b:IsShown() then
            b.fresh = nil
            b:Show()
            if b.cd.dur > 0 then
                -- staggered start, so different remaining times show
                b.cd:SetCooldown(GetTime() - (i * 1.7) % b.cd.dur, b.cd.dur)
            else
                b.cd:Clear()
            end
        end
    end
    for i = n + 1, #pool do pool[i]:Hide() end
end

-------------------------------------------------------------------------------
--  Blocks: a mover frame per group (the drag handle in move mode) holding the
--  AuraContainer and the placeholders.
-------------------------------------------------------------------------------
local pendingApply, pendingAttach = false, false

local function PositionMover(g, s)
    local m = g.mover
    local point, rel = PA.Geometry(s)
    local lineW = PA.LineWidth(s)
    m:SetSize(max(1, lineW), max(1, s.size))
    m:ClearAllPoints()
    local a = PA.anchorFrame
    if a then
        m:SetPoint(point, a, rel, s.x or 0, s.y or 0)
    else
        m.freeBase = g.isDebuff and -150 or -100
        m:SetPoint(point, UIParent, "CENTER", s.x or 0, (s.y or 0) + m.freeBase)
    end
    m.label:ClearAllPoints()
    if s.side == "TOP" then
        m.label:SetPoint("BOTTOM", m, "TOP", 0, 3)
    else
        m.label:SetPoint("TOP", m, "BOTTOM", 0, -3)
    end
    return point, lineW
end

local function RestyleExisting(c, s)
    local n = c:GetAuraGroupFrameCount(GROUP_KEY)
    for i = 1, n do
        local b = c:GetAuraGroupFrame(GROUP_KEY, i)
        if b then
            b:SetSize(s.size, s.size)
            if b.dwpaIcon then PA.Inset(b.dwpaIcon, b, s.border) end
            if b.dwpaCooldown then PA.StyleTimer(b.dwpaCooldown, s) end
            if b.dwpaCount then PA.StyleCount(b.dwpaCount, s) end
        end
    end
end

local function ApplyGroup(g)
    local s = DB()[g.key]
    local c = g.container
    local FD = AnchorUtil.FlowDirection
    local point, lineW = PositionMover(g, s)
    local _, _, gx, gy = PA.Geometry(s)

    c:ClearAllPoints()
    c:SetPoint(point, g.mover, point, 0, 0)
    c:SetFlowLayoutAnchorPoint(point)
    c:SetFlowLayoutGrowthDirection(gx > 0 and FD.Right or FD.Left, gy > 0 and FD.Up or FD.Down)
    c:SetFlowLayoutMaximumLineSize(lineW + 0.5)
    c:SetAuraGroupFilterString(GROUP_KEY, FilterFor(g.key, s))
    c:SetAuraGroupMaxFrameCount(GROUP_KEY, s.max)
    c:SetAuraGroupLayout(GROUP_KEY, LayoutOptions(s))
    local m, d = SortArgs(s)
    if m and d then c:SetAuraGroupSortMethod(GROUP_KEY, m, d) end
    c:SetEnabled(s.enabled)
    c:SetShown(s.enabled)
    -- Move mode hides the real auras by alpha (our own holder frame), so
    -- combat can bring them back at once without touching the container.
    g.holder:SetAlpha(PA.moving and 0 or 1)
    pcall(RestyleExisting, c, s)
end

local function PaintMover(g)
    if g.isDebuff then
        g.mover.bg:SetColorTexture(1, 0.2, 0.2, 0.25)
    else
        local r, gg, b = PA.Accent()
        g.mover.bg:SetColorTexture(r, gg, b, 0.25)
    end
end

-- In move mode with no pet out (the pet frame hidden), the blocks sit on
-- UIParent at the pet frame's place and scale, so they can still be dragged.
local function ParentMovers()
    local a = PA.anchorFrame
    local loose = (PA.moving and not (a and a:IsVisible())) or not a
    for _, key in ipairs(PA.GROUP_KEYS) do
        local m = PA.groups[key].mover
        if loose then
            m:SetParent(UIParent)
            m:SetScale(a and (a:GetEffectiveScale() / UIParent:GetEffectiveScale()) or 1)
            m:SetFrameStrata(PA.moving and "DIALOG" or "MEDIUM")
        else
            m:SetParent(a)
            m:SetScale(1)
            m:SetFrameStrata(a:GetFrameStrata())
            m:SetFrameLevel(a:GetFrameLevel() + 5)
        end
    end
end

function PA.ApplyNow()
    if not PA.ok then
        if PA.OnApplied then PA.OnApplied() end -- the options preview still follows
        return
    end
    if InCombatLockdown() then pendingApply = true return end
    pendingApply = false
    ParentMovers()
    local S = DB()
    for _, key in ipairs(PA.GROUP_KEYS) do
        local g = PA.groups[key]
        local ok, err = pcall(ApplyGroup, g)
        if not ok and not PA.errShown then
            PA.errShown = true
            PA.Print("Error: " .. tostring(err))
        end
        local s = S[key]
        local show = PA.moving and s.enabled
        PA.LayoutPlaceholders(g.ph, g.mover, key, s, show and PA.PlaceholderCount(s) or 0)
        g.mover:EnableMouse(show)
        g.mover.bg:SetShown(show)
        g.mover.label:SetShown(show)
        if show then PaintMover(g) end
    end
    if PA.OnApplied then PA.OnApplied() end
end

-- Coalesced: at most once per frame (sliders, drags).
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
    self:Hide()
    PA.ApplyNow()
end)
function PA.Apply()
    driver:Show()
end

-------------------------------------------------------------------------------
--  Move mode: placeholders on the pet frame, both blocks draggable
-------------------------------------------------------------------------------
local function Mover_OnDragStart(self)
    if PA.moving and not InCombatLockdown() then self:StartMoving() end
end

local function Mover_OnDragStop(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(false)
    local s = DB()[self.key]
    local a = PA.anchorFrame
    local ms, us = self:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if a and self:GetParent() == a then
        local x = (s.growX == "LEFT") and (self:GetRight() - a:GetRight()) or (self:GetLeft() - a:GetLeft())
        local y = (s.side == "TOP") and (self:GetBottom() - a:GetTop()) or (self:GetTop() - a:GetBottom())
        s.x, s.y = floor(x + 0.5), floor(y + 0.5)
    elseif a then
        -- Loose on UIParent at the pet frame's scale: compare in screen units.
        local as = a:GetEffectiveScale()
        local px = ((s.growX == "LEFT") and self:GetRight() or self:GetLeft()) * ms
        local py = ((s.side == "TOP") and self:GetBottom() or self:GetTop()) * ms
        local ax = ((s.growX == "LEFT") and a:GetRight() or a:GetLeft()) * as
        local ay = ((s.side == "TOP") and a:GetTop() or a:GetBottom()) * as
        s.x, s.y = floor((px - ax) / as + 0.5), floor((py - ay) / as + 0.5)
    else
        local cx, cy = UIParent:GetCenter()
        local px = ((s.growX == "LEFT") and self:GetRight() or self:GetLeft()) * ms / us
        local py = ((s.side == "TOP") and self:GetBottom() or self:GetTop()) * ms / us
        s.x = floor(px - cx + 0.5)
        s.y = floor(py - cy - (self.freeBase or 0) + 0.5)
    end
    PA.ApplyNow()
    PA.RefreshOptionWidgets()
end

local function Mover_OnMouseUp(self, button)
    if button == "RightButton" and PA.moving and not InCombatLockdown() then
        local s = DB()[self.key]
        s.x, s.y = PA.DEFAULTS[self.key].x, PA.DEFAULTS[self.key].y
        PA.ApplyNow()
        PA.RefreshOptionWidgets()
    end
end

local function Mover_OnEnter(self)
    if not PA.moving then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(self.key == "debuffs" and "Pet Debuffs" or "Pet Buffs")
    GameTooltip:AddLine("Drag to move. Right-click: reset the offset.", 1, 1, 1)
    GameTooltip:Show()
end

function PA.IsMoving() return PA.moving end

function PA.SetMove(state)
    state = state and true or false
    if state and InCombatLockdown() then
        PA.Print("Move Auras is not available in combat.")
        return
    end
    if PA.moving == state then return end
    PA.moving = state
    PA.ApplyNow()
    PA.RefreshOptionWidgets()
end

function PA.RefreshOptionWidgets()
    if EllesmereUI.IsShown and EllesmereUI:IsShown() and EllesmereUI.RefreshPage then
        pcall(EllesmereUI.RefreshPage, EllesmereUI)
    end
end

local function CreateGroups()
    for _, key in ipairs(PA.GROUP_KEYS) do
        local s = DB()[key]
        local g = { key = key, isDebuff = key == "debuffs", ph = {} }

        local m = CreateFrame("Frame", "EllesmereUIPetAuras_" .. key, UIParent)
        m.key = key
        m.bg = m:CreateTexture(nil, "BACKGROUND", nil, -8)
        m.bg:SetPoint("TOPLEFT", -2, 2)
        m.bg:SetPoint("BOTTOMRIGHT", 2, -2)
        m.bg:Hide()
        m.label = m:CreateFontString(nil, "OVERLAY")
        EllesmereUI.ApplyModuleFont(m.label, nil, 11)
        m.label:SetText(g.isDebuff and "Pet Debuffs" or "Pet Buffs")
        m.label:Hide()
        m:SetMovable(true)
        m:SetClampedToScreen(true)
        m:RegisterForDrag("LeftButton")
        m:EnableMouse(false)
        m:SetScript("OnDragStart", Mover_OnDragStart)
        m:SetScript("OnDragStop", Mover_OnDragStop)
        m:SetScript("OnMouseUp", Mover_OnMouseUp)
        m:SetScript("OnEnter", Mover_OnEnter)
        m:SetScript("OnLeave", function() GameTooltip:Hide() end)
        g.mover = m

        g.holder = CreateFrame("Frame", nil, m)
        g.holder:SetAllPoints(m)
        local c = CreateFrame("AuraContainer", nil, g.holder, "CustomAuraContainerTemplate")
        c:SetUnit(UNIT)
        local sm, sd = SortArgs(s)
        c:AddAuraGroup(GROUP_KEY, FilterFor(key, s), {
            sortMethod      = sm,
            sortDirection   = sd,
            maxFrameCount   = s.max,
            initializeFrame = MakeInitializer(key),
            layout          = LayoutOptions(s),
        })
        g.container = c
        PA.groups[key] = g
    end
end

-------------------------------------------------------------------------------
--  Attach to the pet frame
-------------------------------------------------------------------------------
local hooked = {}

function PA.Attach()
    if not PA.ok then return false end
    if InCombatLockdown() then pendingAttach = true return PA.anchorFrame ~= nil end
    local f = FindPetFrame()
    PA.anchorFrame = f
    if f and not hooked[f] then
        hooked[f] = true
        -- In move mode the blocks follow the pet frame showing / hiding.
        f:HookScript("OnShow", function() if PA.moving then PA.Apply() end end)
        f:HookScript("OnHide", function() if PA.moving then PA.Apply() end end)
    end
    PA.ApplyNow()
    return f ~= nil or DB().frameName == FREE
end

-- name: "" = auto detect, PA.FREE = no anchor, else a frame name.
function PA.SetFrameName(name)
    DB().frameName = name or ""
    PA.anchorFrame = nil
    return PA.Attach()
end

-------------------------------------------------------------------------------
--  Frame picker: hover a frame, left-click picks it, right-click / Esc cancels
-------------------------------------------------------------------------------
local picker

local function FocusFrame()
    if GetMouseFoci then
        local foci = GetMouseFoci()
        return foci and foci[1]
    elseif GetMouseFocus then
        return GetMouseFocus()
    end
end

-- From the hovered region up to the best frame: a "pet" unit frame when there
-- is one, otherwise the outermost named frame below UIParent.
local function Candidate(f)
    local best
    for _ = 1, 30 do
        if not f or f == UIParent or f == WorldFrame then break end
        if f.IsForbidden and f:IsForbidden() then return nil end
        if f == picker then return nil end
        local name = SafeName(f)
        if PA.IsPetUnitFrame(f) and name then return f, name end
        if name and not name:find("^EllesmereUIPetAuras") then best = f end
        local ok, parent = pcall(f.GetParent, f)
        f = ok and parent or nil
    end
    if best then return best, SafeName(best) end
end

local function StopPicker(selected)
    if not picker then return end
    picker:Hide()
    if selected then
        PA.SetFrameName(selected)
        PA.Print("Anchored to " .. PA.FrameLabel(selected) .. " (" .. selected .. ").")
    end
    if PA.reopen then PA.reopen() end
end

function PA.StartPicker()
    if InCombatLockdown() then
        PA.Print("Pick Frame is not available in combat.")
        return
    end
    if not picker then
        picker = CreateFrame("Frame", nil, UIParent)
        picker:SetFrameStrata("TOOLTIP")
        picker:SetAllPoints(UIParent)
        picker:Hide()

        local hl = CreateFrame("Frame", nil, picker)
        hl.bg = hl:CreateTexture(nil, "BACKGROUND")
        hl.bg:SetAllPoints()
        if EllesmereUI.MakeBorder then hl.border = EllesmereUI.MakeBorder(hl, 1, 1, 1, 1) end
        hl:Hide()
        picker.hl = hl

        local banner = CreateFrame("Frame", nil, picker)
        banner:SetSize(560, 52)
        banner:SetPoint("TOP", 0, -120)
        banner.bg = banner:CreateTexture(nil, "BACKGROUND")
        banner.bg:SetAllPoints()
        banner.bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
        if EllesmereUI.MakeBorder then banner.border = EllesmereUI.MakeBorder(banner, 1, 1, 1, 1) end
        banner.title = banner:CreateFontString(nil, "OVERLAY")
        EllesmereUI.ApplyModuleFont(banner.title, nil, 14)
        banner.title:SetPoint("TOP", 0, -9)
        banner.title:SetText("Hover your pet frame and left-click it.   Right-click or Esc: cancel")
        banner.info = banner:CreateFontString(nil, "OVERLAY")
        EllesmereUI.ApplyModuleFont(banner.info, nil, 12)
        banner.info:SetPoint("BOTTOM", 0, 9)
        picker.banner = banner

        picker:RegisterEvent("PLAYER_REGEN_DISABLED")
        picker:SetScript("OnEvent", function(self) if self:IsShown() then StopPicker(nil) end end)
        picker:EnableKeyboard(true)
        picker:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                StopPicker(nil)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
        -- The picker takes no mouse: it reads what is under the cursor and
        -- watches the buttons, so hovering works on every frame.
        picker:SetScript("OnUpdate", function(self)
            local target, name = Candidate(FocusFrame())
            self.targetName = name
            if target then
                self.hl:ClearAllPoints()
                self.hl:SetPoint("TOPLEFT", target, "TOPLEFT", -2, 2)
                self.hl:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 2, -2)
                self.hl:Show()
                local mark = PA.IsPetUnitFrame(target) and ("   " .. PA.AccentHex() .. "pet unit frame|r") or ""
                self.banner.info:SetText(PA.FrameLabel(name) .. "  |cff888888" .. name .. "|r" .. mark)
            else
                self.hl:Hide()
                self.banner.info:SetText("|cff888888no frame under the cursor|r")
            end
            local left, right = IsMouseButtonDown("LeftButton"), IsMouseButtonDown("RightButton")
            if self.armed then
                if right then StopPicker(nil)
                elseif left and self.targetName then StopPicker(self.targetName) end
            elseif not left and not right then
                self.armed = true -- the click that opened the picker is released
            end
        end)
    end
    local r, g, b = PA.Accent()
    picker.hl.bg:SetColorTexture(r, g, b, 0.15)
    if picker.hl.border and picker.hl.border.SetColor then picker.hl.border:SetColor(r, g, b, 1) end
    if picker.banner.border and picker.banner.border.SetColor then picker.banner.border:SetColor(r, g, b, 1) end
    if PA.moving then PA.SetMove(false) end
    picker.armed = false
    picker.targetName = nil
    picker:Show()
end

-------------------------------------------------------------------------------
--  Export / import (only the Pet Auras settings; EllesmereUI profile exports
--  carry them too)
-------------------------------------------------------------------------------
local EXPORT_PREFIX = "EUIPA2:"
local OLD_PREFIX = "EUIPA1:"

local ENUMS = {
    side         = { TOP = true, BOTTOM = true },
    growX        = { LEFT = true, RIGHT = true },
    sortMethod   = { APPLIED = true, EXPIRATION = true, NAME = true, BLIZZARD = true },
    timerPoint   = { TOP = true, CENTER = true, BOTTOM = true },
    timerOutline = { __global = true, none = true, outline = true, thick = true },
}
local RANGES = {
    x = { -500, 500 }, y = { -500, 500 },
    size = { 8, 64 }, spacing = { 0, 20 }, perRow = { 1, 40 }, max = { 1, 40 },
    border = { 0, 8 }, timerSize = { 6, 28 }, countSize = { 6, 24 },
    timerX = { -30, 30 }, timerY = { -30, 30 },
}
-- Values from the standalone version (Blizzard font flags).
local OLD_OUTLINE = {
    [""] = "none", OUTLINE = "outline", THICKOUTLINE = "thick",
    MONOCHROME = "outline", ["OUTLINE, MONOCHROME"] = "outline",
}

local function FontKnown(name)
    if type(name) ~= "string" then return false end
    if name == "__global" then return true end
    if not EllesmereUI.BuildFontDropdownData then return false end
    local values = EllesmereUI.BuildFontDropdownData()
    return values and values[name] ~= nil
end

local function SanitizeGroup(src, def)
    local out = {}
    for k, d in pairs(def) do
        local v = src[k]
        if k == "timerOutline" and OLD_OUTLINE[v] then v = OLD_OUTLINE[v] end
        if type(v) ~= type(d) then
            v = d
        elseif ENUMS[k] and not ENUMS[k][v] then
            v = d
        elseif type(v) == "number" then
            if v ~= v then v = d end -- NaN
            local r = RANGES[k]
            if r then v = max(r[1], min(r[2], v)) end
            if k ~= "x" and k ~= "y" and k ~= "timerX" and k ~= "timerY" then v = floor(v + 0.5) end
        elseif k == "timerFont" and not FontKnown(v) then
            v = "__global"
        end
        out[k] = v
    end
    return out
end

local function Sanitize(src)
    local d = PA.DEFAULTS
    local out = {
        buffs   = SanitizeGroup(type(src.buffs) == "table" and src.buffs or {}, d.buffs),
        debuffs = SanitizeGroup(type(src.debuffs) == "table" and src.debuffs or {}, d.debuffs),
        frameName = "",
    }
    local fn = src.frameName
    if fn == FREE or (type(fn) == "string" and #fn <= 128 and fn:match("^[%w_%.]+$")) then
        out.frameName = fn
    end
    return out
end

-- Writes sanitized settings into the active profile.
local function Store(data)
    local d = DB()
    for _, key in ipairs(PA.GROUP_KEYS) do
        wipe(d[key])
        for k, v in pairs(data[key]) do d[key][k] = v end
    end
    d.frameName = data.frameName
    d.imported = true
end

local function EncodingOK()
    local E = C_EncodingUtil
    return E and E.SerializeCBOR and E.DeserializeCBOR and E.CompressString and E.DecompressString
        and E.EncodeBase64 and E.DecodeBase64
end

function PA.Export()
    if not EncodingOK() then return nil, "this client has no C_EncodingUtil, export is not available." end
    local E = C_EncodingUtil
    local payload = { data = Sanitize(DB()) }
    local ok, res = pcall(function()
        return EXPORT_PREFIX .. E.EncodeBase64(E.CompressString(E.SerializeCBOR(payload)))
    end)
    if not ok then return nil, "export failed: " .. tostring(res) end
    return res
end

-- Replaces the Pet Auras settings of the active profile. true or nil, error.
function PA.Import(str)
    if not EncodingOK() then return nil, "this client has no C_EncodingUtil, import is not available." end
    str = (str or ""):gsub("%s+", "")
    local body
    if str:sub(1, #EXPORT_PREFIX) == EXPORT_PREFIX then body = str:sub(#EXPORT_PREFIX + 1)
    elseif str:sub(1, #OLD_PREFIX) == OLD_PREFIX then body = str:sub(#OLD_PREFIX + 1)
    else return nil, "this is not a Pet Auras string." end
    local E = C_EncodingUtil
    local ok, payload = pcall(function()
        return E.DeserializeCBOR(E.DecompressString(E.DecodeBase64(body)))
    end)
    if not ok or type(payload) ~= "table" or type(payload.data) ~= "table" then
        return nil, "the string is damaged or incomplete."
    end
    Store(Sanitize(payload.data))
    PA.SetFrameName(DB().frameName)
    return true
end

-------------------------------------------------------------------------------
--  One-time takeover of the standalone version's settings (EUIPetAurasDB).
--  The old folder keeps only its .toc, which loads that saved table.
-------------------------------------------------------------------------------
local function ImportOld()
    local d = DB()
    if d.imported then return end
    local root = _G.EUIPetAurasDB
    if type(root) ~= "table" then return end -- old version not here (yet): try again next login
    d.imported = true
    local src
    if type(root.profiles) == "table" then
        local charKey = (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
        local name = type(root.chars) == "table" and root.chars[charKey]
        src = (name and root.profiles[name]) or root.profiles.Default
    elseif type(root.buffs) == "table" then
        src = root -- flat (version 2) layout
    end
    if type(src) ~= "table" then return end
    Store(Sanitize(src))
    PA.Print("took over the settings of the standalone Pet Auras. You can delete the "
        .. "|cffffffffEllesmereUI_PetAuras|r folder.")
end

-------------------------------------------------------------------------------
--  Boot
-------------------------------------------------------------------------------
local function HasAuraContainer()
    return AnchorUtil and AnchorUtil.FlowDirection and CustomAuraContainerGroupDefaultOptions ~= nil
end

local tries = 0
local function TryAttach()
    if PA.Attach() then return end
    tries = tries + 1
    if tries < 10 then
        C_Timer.After(2, TryAttach)
    else
        PA.Print("no pet frame found. Pick one under Dworak > Pet Auras (Anchor To, or Pick Frame).")
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        if not HasAuraContainer() then
            PA.Print("this client has no AuraContainer system; Pet Auras is off.")
            return
        end
        ImportOld()
        local ok, err = pcall(CreateGroups)
        if not ok then
            PA.Print("could not create the aura blocks: " .. tostring(err))
            return
        end
        PA.ok = true
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterUnitEvent("UNIT_PET", "player")
        if EllesmereUI.RegisterOnHide then
            EllesmereUI:RegisterOnHide(function() if PA.moving then PA.SetMove(false) end end)
        end
        if EllesmereUI.RegAccent then
            EllesmereUI.RegAccent({ type = "callback", fn = function() PA.Apply() end })
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        tries = 0
        C_Timer.After(1, TryAttach)
    elseif event == "UNIT_PET" then
        if not PA.anchorFrame then PA.Attach() end
        if PA.moving then PA.Apply() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if PA.moving then
            -- Combat ends move mode now: only our own frames are touched
            -- here; the full apply runs at combat end.
            PA.moving = false
            pendingApply = true
            for _, key in ipairs(PA.GROUP_KEYS) do
                local g = PA.groups[key]
                g.mover:StopMovingOrSizing()
                g.mover:EnableMouse(false)
                g.mover.bg:Hide()
                g.mover.label:Hide()
                for _, b in ipairs(g.ph) do b:Hide() end
                g.holder:SetAlpha(1)
            end
            PA.RefreshOptionWidgets()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingAttach then pendingAttach = false; PA.Attach()
        elseif pendingApply then PA.ApplyNow() end
    end
end)
