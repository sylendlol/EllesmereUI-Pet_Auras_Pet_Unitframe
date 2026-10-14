if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIPetAuras_Options.lua
--  The Dworak > Pet Auras page, built with EllesmereUI's own widgets, and its
--  live preview in the content header: a pet frame with placeholder buffs and
--  debuffs drawn with the current settings (place, growth, size, border,
--  spacing, rows, sort order, timer font / size / outline / place, stacks).
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local PA = ns.PA
local DW = EllesmereUIDworak
local EllesmereUI = _G.EllesmereUI
if not PA then return end

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local MODULE_KEY = "PetAuras"
local AUTO = "__auto"

local function S(key) return PA.DB()[key] end

local function Prebuild()
    return EllesmereUI.IsSearchPrebuild and EllesmereUI.IsSearchPrebuild()
end

-------------------------------------------------------------------------------
--  Live preview (content header)
-------------------------------------------------------------------------------
local PV_MARGIN, PV_HINT_H, PV_MIN_H, PV_MAX_H = 14, 16, 110, 300
local preview

-- The mock pet frame: the real pet frame's size when there is one.
local function MockSize()
    local w, h = 160, 32
    local a = PA.anchorFrame
    if a then
        local aw, ah = a:GetSize()
        if aw and aw > 20 and ah and ah > 6 then w, h = aw, ah end
    end
    return min(max(w, 80), 320), min(max(h, 14), 80)
end

-- One block's rectangle in mock-frame units (origin: the mock's bottom left).
local function BlockRect(s, W, H)
    local n = PA.PlaceholderCount(s)
    local perRow = max(1, s.perRow)
    local cols, rows = min(n, perRow), ceil(n / perRow)
    local bw = cols * s.size + (cols - 1) * s.spacing
    local bh = rows * s.size + (rows - 1) * s.spacing
    local x1, y1
    if s.growX == "LEFT" then x1 = W + (s.x or 0) - bw else x1 = s.x or 0 end
    if s.side == "TOP" then y1 = H + (s.y or 0) else y1 = (s.y or 0) - bh end
    return x1, y1, x1 + bw, y1 + bh
end

-- The real pet frame's health bar color (whatever its addon paints it), so the
-- preview looks like your own pet frame. Fallback: the friendly reaction green.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return type(v) == "number" and v or nil
end

local function IsWhite(r, g, b) return r and r > 0.97 and g > 0.97 and b > 0.97 end

local function BarColor(bar)
    local ok, r, g, b = pcall(bar.GetStatusBarColor, bar)
    r, g, b = ok and Plain(r), ok and Plain(g), ok and Plain(b)
    -- Some frames keep the bar white and tint its texture instead.
    if not (r and g and b) or IsWhite(r, g, b) then
        local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if tex and tex.GetVertexColor then
            local ok2, tr, tg, tb = pcall(tex.GetVertexColor, tex)
            tr, tg, tb = ok2 and Plain(tr), ok2 and Plain(tg), ok2 and Plain(tb)
            if tr and tg and tb and not IsWhite(tr, tg, tb) then return tr, tg, tb end
        end
    end
    if r and g and b and not IsWhite(r, g, b) then return r, g, b end
end

-- The health bar: the frame's own field when it has one, else its biggest
-- status bar (a few levels deep).
local function HealthBar(f)
    for _, k in ipairs({ "Health", "health", "healthBar", "healthbar", "HealthBar" }) do
        local b = rawget(f, k)
        if type(b) == "table" and b.GetStatusBarColor then return b end
    end
    local best, bestArea
    local function scan(fr, depth)
        if depth > 4 then return end
        for _, c in ipairs({ fr:GetChildren() }) do
            if not (c.IsForbidden and c:IsForbidden()) then
                if c.GetStatusBarColor and c:IsShown() then
                    local w, h = c:GetSize()
                    local area = (w or 0) * (h or 0)
                    if area > (bestArea or 0) then best, bestArea = c, area end
                end
                scan(c, depth + 1)
            end
        end
    end
    pcall(scan, f, 1)
    return best
end

local function PetFrameColor()
    local a = PA.anchorFrame
    local bar = a and HealthBar(a)
    if bar then
        local r, g, b = BarColor(bar)
        if r then return r, g, b end
    end
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[5]
    if c then return c.r, c.g, c.b end
    return 0.0, 0.6, 0.1
end

local function PaintMock()
    local m = preview.mock
    local r, g, b = PetFrameColor()
    m.fill:SetColorTexture(r, g, b, 1)
    local name = UnitExists("pet") and UnitName("pet") or "Pet"
    m.name:SetText(name)
end

local function RefreshPreview()
    if not (preview and preview:IsShown()) then return end
    local W, H = MockSize()
    local m = preview.mock
    m:SetSize(W, H)
    local fs = max(9, min(14, floor(H * 0.42)))
    EllesmereUI.ApplyModuleFont(m.name, nil, fs, "unitFrames")
    EllesmereUI.ApplyModuleFont(m.value, nil, fs, "unitFrames")
    PaintMock()

    -- The whole picture: the mock frame plus every block that is on.
    local minX, minY, maxX, maxY = 0, 0, W, H
    local anyOff = false
    for _, key in ipairs(PA.GROUP_KEYS) do
        local s = S(key)
        local block, pool = preview.blocks[key], preview.pools[key]
        if s.enabled then
            local x1, y1, x2, y2 = BlockRect(s, W, H)
            minX, minY = min(minX, x1), min(minY, y1)
            maxX, maxY = max(maxX, x2), max(maxY, y2)
            local point, rel = PA.Geometry(s)
            block:SetSize(max(1, PA.LineWidth(s)), max(1, s.size))
            block:ClearAllPoints()
            block:SetPoint(point, m, rel, s.x or 0, s.y or 0)
            block:Show()
            PA.LayoutPlaceholders(pool, block, key, s, PA.PlaceholderCount(s))
        else
            anyOff = true
            block:Hide()
        end
    end
    local cw, ch = maxX - minX, maxY - minY
    local availW = (preview:GetWidth() or 0) - PV_MARGIN * 2
    if availW < 100 then availW = 600 end
    local scale = min(1.6, availW / cw, (PV_MAX_H - PV_MARGIN * 2 - PV_HINT_H) / ch)
    local c = preview.content
    c:SetScale(scale)
    c:SetSize(cw, ch)
    c:ClearAllPoints()
    c:SetPoint("TOP", preview, "TOP", 0, -PV_MARGIN / scale)
    m:ClearAllPoints()
    m:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", -minX, -minY)

    local hint = "Live preview with placeholder auras"
    if anyOff then hint = hint .. "  (a hidden block is off)" end
    if not PA.ok then hint = "Preview only: this client has no AuraContainer system" end
    preview.hint:SetText(hint)

    local h = max(PV_MIN_H, ceil(ch * scale) + PV_MARGIN * 2 + PV_HINT_H)
    if math.abs(preview:GetHeight() - h) > 1 then
        preview:SetHeight(h)
        local header = preview:GetParent()
        if preview.built and header and header:IsVisible() and EllesmereUI.SetContentHeaderHeightSilent then
            EllesmereUI:SetContentHeaderHeightSilent(h)
        end
    end
end
PA.OnApplied = RefreshPreview

local function BuildPreview(header)
    preview = CreateFrame("Frame", nil, header)
    preview:SetHeight(PV_MIN_H)
    preview.content = CreateFrame("Frame", nil, preview)

    local m = CreateFrame("Frame", nil, preview.content)
    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    m.bg:SetColorTexture(0.06, 0.06, 0.07, 0.95)
    m.fill = m:CreateTexture(nil, "BORDER")
    m.fill:SetPoint("TOPLEFT", 1, -1)
    m.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    if EllesmereUI.MakeBorder then EllesmereUI.MakeBorder(m, 0, 0, 0, 1, EllesmereUI.PanelPP) end
    m.name = m:CreateFontString(nil, "OVERLAY")
    m.name:SetFontObject(GameFontHighlight) -- a font before the first SetText
    m.name:SetPoint("LEFT", 6, 0)
    m.value = m:CreateFontString(nil, "OVERLAY")
    m.value:SetFontObject(GameFontHighlight)
    m.value:SetPoint("RIGHT", -6, 0)
    m.value:SetText("100%")
    preview.mock = m

    preview.blocks, preview.pools = {}, {}
    for _, key in ipairs(PA.GROUP_KEYS) do
        local b = CreateFrame("Frame", nil, preview.content)
        b:SetFrameLevel(m:GetFrameLevel() + 3)
        preview.blocks[key] = b
        preview.pools[key] = {}
    end

    preview.hint = preview:CreateFontString(nil, "OVERLAY")
    EllesmereUI.ApplyModuleFont(preview.hint, nil, 11)
    preview.hint:SetTextColor(1, 1, 1, 0.45)
    preview.hint:SetPoint("BOTTOM", preview, "BOTTOM", 0, 6)
end

local function HeaderBuilder(header, width)
    if not preview then BuildPreview(header) end
    preview:SetParent(header)
    preview:SetFrameStrata(header:GetFrameStrata())
    preview:SetFrameLevel(header:GetFrameLevel() + 5)
    preview.content:SetFrameLevel(preview:GetFrameLevel() + 1)
    preview.mock:SetFrameLevel(preview.content:GetFrameLevel() + 1)
    for _, b in pairs(preview.blocks) do b:SetFrameLevel(preview.content:GetFrameLevel() + 4) end
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", header, "TOPLEFT")
    preview:SetPoint("TOPRIGHT", header, "TOPRIGHT")
    if width and width > 0 then preview:SetWidth(width) end
    preview.built = false
    preview:Show()
    RefreshPreview()
    preview.built = true
    return preview:GetHeight()
end

-------------------------------------------------------------------------------
--  Page helpers
-------------------------------------------------------------------------------
local function Changed() PA.Apply() end

local function Refresh() EllesmereUI:RefreshPage() end

-- Reopens this page (after Pick Frame), rebuilt so the anchor list is current.
function PA.reopen()
    if DW and DW.Open(MODULE_KEY) then
        C_Timer.After(0, function()
            if EllesmereUI:IsShown() then EllesmereUI:RefreshPage(true) end
        end)
    end
end

-- "Move Auras" button in a label half (same look as the Raid Frames' Move Frames).
local function MoveButton(row, rgn)
    local btn = CreateFrame("Button", nil, row)
    btn:SetSize(140, 26)
    btn:SetPoint("RIGHT", rgn, "RIGHT", -20, 0)
    btn:SetFrameLevel(row:GetFrameLevel() + 5)
    local bbg = btn:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.077, 0.068, 0.058, 0.92)
    if EllesmereUI.MakeBorder then EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.25) end
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    EllesmereUI.ApplyModuleFont(lbl, nil, 13)
    lbl:SetPoint("CENTER")
    local function Update()
        lbl:SetText(PA.IsMoving() and "Stop Moving" or "Move Auras")
        if PA.IsMoving() then lbl:SetTextColor(PA.Accent()) else lbl:SetTextColor(1, 1, 1) end
        btn:SetAlpha((InCombatLockdown() or not PA.ok) and 0.35 or 1)
    end
    btn:SetScript("OnEnter", function(self)
        if not EllesmereUI.ShowWidgetTooltip then return end
        if InCombatLockdown() then
            EllesmereUI.ShowWidgetTooltip(self, "Not available in combat")
        else
            EllesmereUI.ShowWidgetTooltip(self, "Shows placeholder auras on your pet frame. Drag the colored "
                .. "blocks to move them, right-click a block to reset its offset, click again to lock.")
        end
    end)
    btn:SetScript("OnLeave", function() if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end end)
    btn:SetScript("OnClick", function()
        if InCombatLockdown() or not PA.ok then return end
        PA.SetMove(not PA.IsMoving())
        Update()
    end)
    if EllesmereUI.RegisterWidgetRefresh then EllesmereUI.RegisterWidgetRefresh(Update) end
    Update()
    return btn
end

local POS_VALUES  = { TOP = "Above the Pet Frame", BOTTOM = "Below the Pet Frame" }
local POS_ORDER   = { "TOP", "BOTTOM" }
local GROW_VALUES = { RIGHT = "Left to Right", LEFT = "Right to Left" }
local GROW_ORDER  = { "RIGHT", "LEFT" }
local SORT_VALUES = {
    APPLIED    = "Applied Order",
    EXPIRATION = "Remaining Time",
    NAME       = "Name",
    BLIZZARD   = "Blizzard Default",
}
local SORT_ORDER  = { "APPLIED", "EXPIRATION", "NAME", "BLIZZARD" }
local OUTLINE_VALUES = {
    ["__global"] = { text = "EUI Global Default" },
    ["none"]     = { text = "Drop Shadow" },
    ["outline"]  = { text = "Outline" },
    ["thick"]    = { text = "Thick Outline" },
}
local OUTLINE_ORDER = { "__global", "none", "outline", "thick" }
local TIMER_POINTS = { TOP = "Top", CENTER = "Center", BOTTOM = "Bottom" }
local TIMER_POINT_ORDER = { "TOP", "CENTER", "BOTTOM" }

-- Anchor To: auto, none, and every pet frame found now.
local function AnchorValues()
    local values = { [AUTO] = "Auto Detect", [PA.FREE] = "None (Free Position)" }
    local order = { AUTO, PA.FREE, "---" }
    local cur = S("frameName")
    local found = false
    for _, e in ipairs(PA.ScanPetFrames()) do
        values[e.name] = (e.label ~= e.name) and (e.label .. "  (" .. e.name .. ")") or e.name
        order[#order + 1] = e.name
        if e.name == cur then found = true end
    end
    if cur and cur ~= "" and cur ~= PA.FREE and not found then
        values[cur] = cur .. "  (not loaded)"
        order[#order + 1] = cur
    end
    if order[#order] == "---" then order[#order] = nil end
    return values, order
end

-------------------------------------------------------------------------------
--  Two columns: every row has the buff setting on the left and the matching
--  debuff setting on the right.
-------------------------------------------------------------------------------
local function Cfg(key, id, fontValues, fontOrder)
    local isDebuff = key == "debuffs"
    local Name = isDebuff and "Debuff" or "Buff"
    local offTip = "Show Pet " .. Name .. "s"
    local function G() return S(key) end
    local function Set(k, v) G()[k] = v; Changed() end
    local function off() return not G().enabled end
    local function timerOff() return off() or not G().showTimer end
    local function slider(text, k, lo, hi, tip)
        return { type = "slider", text = Name .. " " .. text, min = lo, max = hi, step = 1, tooltip = tip,
                 disabled = off, disabledTooltip = offTip,
                 getValue = function() return G()[k] end,
                 setValue = function(v) Set(k, v) end }
    end

    if id == "position" then
        return { type = "dropdown", text = Name .. " Position",
          tooltip = "Above or below the pet frame. Fine-tune it with the X / Y Offset, or drag it in Move Auras.",
          values = POS_VALUES, order = POS_ORDER,
          disabled = off, disabledTooltip = offTip,
          getValue = function() return G().side end,
          setValue = function(v)
              local s = G()
              if s.side ~= v then
                  s.side = v
                  s.x, s.y = 0, (v == "TOP") and 2 or -2
              end
              Changed()
              Refresh()
          end }
    elseif id == "grow" then
        return { type = "dropdown", text = Name .. " Growth",
          tooltip = "The side new " .. Name:lower() .. "s are added on.",
          values = GROW_VALUES, order = GROW_ORDER,
          disabled = off, disabledTooltip = offTip,
          getValue = function() return G().growX end,
          setValue = function(v) Set("growX", v) end }
    elseif id == "x" then return slider("X Offset", "x", -500, 500)
    elseif id == "y" then return slider("Y Offset", "y", -500, 500)
    elseif id == "sort" then
        return { type = "dropdown", text = Name .. " Sort Order",
          tooltip = "Applied Order: a new " .. Name:lower() .. " goes to the end of the row.\n"
              .. "Remaining Time: shortest first, permanent ones last.\n"
              .. "Blizzard Default: your own auras first.",
          values = SORT_VALUES, order = SORT_ORDER,
          disabled = off, disabledTooltip = offTip,
          getValue = function() return G().sortMethod end,
          setValue = function(v) Set("sortMethod", v) end }
    elseif id == "reverse" then
        return { type = "toggle", text = Name .. " Reverse Order",
          disabled = off, disabledTooltip = offTip,
          getValue = function() return G().sortReverse == true end,
          setValue = function(v) Set("sortReverse", v and true or false) end }
    elseif id == "filter" then
        if isDebuff then
            return { type = "toggle", text = "Only Dispellable Debuffs",
              tooltip = "Only the debuffs you can dispel.",
              disabled = off, disabledTooltip = offTip,
              getValue = function() return G().onlyDispellable == true end,
              setValue = function(v) Set("onlyDispellable", v and true or false) end }
        end
        return { type = "toggle", text = "Only My Buffs",
          tooltip = "Only the buffs you (or your pet) put on the pet.",
          disabled = off, disabledTooltip = offTip,
          getValue = function() return G().onlyMine == true end,
          setValue = function(v) Set("onlyMine", v and true or false) end }
    elseif id == "size" then return slider("Icon Size", "size", 10, 48)
    elseif id == "spacing" then return slider("Spacing", "spacing", 0, 12)
    elseif id == "perRow" then return slider("Icons Per Row", "perRow", 1, 20)
    elseif id == "max" then return slider("Max Icons", "max", 1, 40)
    elseif id == "border" then
        return slider("Border", "border", 0, 8, isDebuff
            and "Border thickness. The border shows the debuff's dispel type color." or "Border thickness.")
    elseif id == "showTimer" then
        return { type = "toggle", text = Name .. " Timer",
          tooltip = "Remaining time on the " .. Name:lower() .. " icons.",
          disabled = off, disabledTooltip = offTip,
          getValue = function() return G().showTimer ~= false end,
          setValue = function(v) Set("showTimer", v and true or false); Refresh() end }
    elseif id == "timerSize" then
        return { type = "slider", text = Name .. " Timer Size", min = 6, max = 28, step = 1,
          disabled = timerOff, disabledTooltip = Name .. " Timer",
          getValue = function() return G().timerSize end,
          setValue = function(v) Set("timerSize", v) end }
    elseif id == "timerPoint" then
        return { type = "dropdown", text = Name .. " Timer Position",
          tooltip = "Where the timer sits on the icon. The cog fine-tunes it with X / Y.",
          values = TIMER_POINTS, order = TIMER_POINT_ORDER,
          disabled = timerOff, disabledTooltip = Name .. " Timer",
          getValue = function() return G().timerPoint or "CENTER" end,
          setValue = function(v)
              local s = G()
              if s.timerPoint ~= v then s.timerPoint = v; s.timerX, s.timerY = 0, 0 end
              Changed()
          end }
    elseif id == "outline" then
        return { type = "dropdown", text = Name .. " Text Outline",
          tooltip = "Outline of the timer and the stack count.",
          values = OUTLINE_VALUES, order = OUTLINE_ORDER,
          disabled = off, disabledTooltip = offTip,
          getValue = function() return G().timerOutline or "outline" end,
          setValue = function(v) Set("timerOutline", v) end }
    elseif id == "font" then
        return { type = "dropdown", text = Name .. " Text Font",
          tooltip = "Font of the timer and the stack count. EUI Global Font follows the Unit Frames font.",
          values = fontValues, order = fontOrder,
          disabled = off, disabledTooltip = offTip,
          getValue = function()
              local v = G().timerFont or "__global"
              if not fontValues[v] then v = "__global" end
              return v
          end,
          setValue = function(v) Set("timerFont", v) end }
    elseif id == "countSize" then return slider("Stack Size", "countSize", 6, 24)
    end
end

-- Timer X / Y cog on a Timer Position half.
local function TimerCog(rgn, key)
    if Prebuild() or not (rgn and EllesmereUI.BuildInlineCog) then return end
    local Name = key == "debuffs" and "Debuff" or "Buff"
    local function G() return S(key) end
    local function timerOff() return not G().enabled or not G().showTimer end
    EllesmereUI.BuildInlineCog(rgn, {
        disabled = timerOff, disabledTooltip = Name .. " Timer",
        title = "Pet " .. Name .. " Timer",
        rows = {
            { type = "slider", label = "Timer X", min = -30, max = 30, step = 1,
              get = function() return G().timerX or 0 end, set = function(v) G().timerX = v; Changed() end },
            { type = "slider", label = "Timer Y", min = -30, max = 30, step = 1,
              get = function() return G().timerY or 0 end, set = function(v) G().timerY = v; Changed() end },
        },
    })
end

local SECTIONS = {
    { "LAYOUT", { "position", "grow", "x", "y", "sort", "reverse", "filter" } },
    { "ICONS",  { "size", "spacing", "perRow", "max", "border" } },
    { "TIMER & STACK TEXT", { "showTimer", "timerSize", "timerPoint", "outline", "font", "countSize" } },
}

local function BuildColumns(parent, y, W, fontValues, fontOrder)
    local _, h, row
    for _, sec in ipairs(SECTIONS) do
        _, h = W:Spacer(parent, y, 20); y = y - h
        _, h = W:SectionHeader(parent, sec[1], y); y = y - h
        for _, id in ipairs(sec[2]) do
            row, h = W:DualRow(parent, y,
                Cfg("buffs", id, fontValues, fontOrder),
                Cfg("debuffs", id, fontValues, fontOrder)); y = y - h
            if id == "timerPoint" and row then
                TimerCog(row._leftRegion, "buffs")
                TimerCog(row._rightRegion, "debuffs")
            end
        end
    end
    return y
end

-------------------------------------------------------------------------------
--  The page
-------------------------------------------------------------------------------
local function BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h, row
    parent._showRowDivider = true
    local prebuilding = Prebuild()
    if not prebuilding then EllesmereUI:SetContentHeader(HeaderBuilder) end

    local fontValues, fontOrder
    if EllesmereUI.BuildFontDropdownData then
        fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
    else
        fontValues, fontOrder = { ["__global"] = { text = "EUI Global Font" } }, { "__global" }
    end

    _, h = W:SectionHeader(parent, "PET AURAS", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Show Pet Buffs",
          tooltip = "Your pet's buffs next to the pet frame.",
          getValue = function() return S("buffs").enabled == true end,
          setValue = function(v) S("buffs").enabled = v and true or false; Changed(); Refresh() end },
        { type = "toggle", text = "Show Pet Debuffs",
          tooltip = "Your pet's debuffs next to the pet frame; the border shows the dispel type.",
          getValue = function() return S("debuffs").enabled == true end,
          setValue = function(v) S("debuffs").enabled = v and true or false; Changed(); Refresh() end }
    ); y = y - h

    local anchorValues, anchorOrder = AnchorValues()
    _, h = W:DualRow(parent, y,
        { type = "dropdown", text = "Anchor To", dropdownWidth = 230,
          tooltip = "The pet frame the auras sit on. Auto Detect takes EllesmereUI's pet frame, "
              .. "else another unit frame addon's, else Blizzard's. None: a free spot on the screen "
              .. "(drag it in Move Auras).",
          values = anchorValues, order = anchorOrder,
          getValue = function()
              local v = S("frameName")
              if not v or v == "" then return AUTO end
              return v
          end,
          setValue = function(v)
              PA.SetFrameName(v == AUTO and "" or v)
              RefreshPreview()
          end },
        { type = "button", text = "Pick Frame", width = 180,
          tooltip = "Hover any frame and left-click it: the auras anchor to it. Right-click or Esc cancels.",
          onClick = function()
              if InCombatLockdown() then return end
              EllesmereUI:Hide()
              PA.StartPicker()
          end }
    ); y = y - h

    row, h = W:DualRow(parent, y,
        { type = "label", text = "Aura Positions" },
        { type = "label", text = "Settings String" }
    ); y = y - h
    if not prebuilding and row then
        if row._leftRegion then MoveButton(row, row._leftRegion) end
        if row._rightRegion and EllesmereUI.BuildInlineButton then
            EllesmereUI.BuildInlineButton(row._rightRegion, "Import", function()
                EllesmereUI:ShowImportPopup(function(str)
                    local ok, err = PA.Import(str)
                    if ok then
                        PA.Print("settings imported.")
                        EllesmereUI:RefreshPage(true)
                    else
                        PA.Print("import failed: " .. tostring(err))
                    end
                end, "Import Pet Auras", "Paste a Pet Auras settings string below. It replaces the current Pet Auras settings.")
            end, { width = 90, tip = "Replace the Pet Auras settings with a pasted string." })
            EllesmereUI.BuildInlineButton(row._rightRegion, "Export", function()
                local str, err = PA.Export()
                if str then
                    EllesmereUI:ShowCopyPopup("Export Pet Auras", "Copy the string below and share it", str)
                else
                    PA.Print(tostring(err))
                end
            end, { width = 90, tip = "The Pet Auras settings as a string. EllesmereUI profile exports carry them too." })
        end
    end

    y = BuildColumns(parent, y, W, fontValues, fontOrder)

    return math.abs(y)
end

-------------------------------------------------------------------------------
--  Dworak > Pet Auras row
-------------------------------------------------------------------------------
if DW then
    DW.AddModule({
        key         = MODULE_KEY,
        title       = "Pet Auras",
        order       = 50,
        description = "Your pet's buffs and debuffs next to the pet frame.",
        pages       = { "Pet Auras" },
        buildPage   = BuildPage,
        getHeaderBuilder = function() return HeaderBuilder end,
        onPageCacheRestore = function() RefreshPreview() end,
        onModuleLeave = function() if PA.IsMoving() then PA.SetMove(false) end end,
        onReset = function()
            PA.ResetSettings()
            if EllesmereUI:IsShown() then EllesmereUI:RefreshPage(true) end
        end,
    })
end

-- The pet's name in the preview, and the real pet frame's size.
local pv = CreateFrame("Frame")
pv:RegisterUnitEvent("UNIT_PET", "player")
pv:RegisterUnitEvent("UNIT_NAME_UPDATE", "pet")
pv:SetScript("OnEvent", function() RefreshPreview() end)

-------------------------------------------------------------------------------
--  /petauras (or /pa): opens the page.  move: Move Auras.  reset: defaults.
-------------------------------------------------------------------------------
SLASH_EUIDWORAKPETAURAS1 = "/petauras"
SLASH_EUIDWORAKPETAURAS2 = "/pa"
SlashCmdList.EUIDWORAKPETAURAS = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "move" or msg == "test" then
        PA.SetMove(not PA.IsMoving())
        PA.Print(PA.IsMoving() and "Move Auras ON: drag the colored blocks, right-click resets. /pa move again to lock."
            or "Move Auras OFF.")
    elseif msg == "reset" then
        PA.ResetSettings()
        PA.Print("settings reset to defaults.")
    elseif msg == "pick" then
        PA.StartPicker()
    elseif DW then
        DW.Open(MODULE_KEY)
    else
        PA.Print("the Dworak section (EllesmereUIDworak) is off. /pa move, /pa pick, /pa reset still work.")
    end
end
