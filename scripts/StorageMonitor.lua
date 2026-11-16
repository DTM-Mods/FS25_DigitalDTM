-- Digital DTM (FS25_DigitalDTM, DTM Mods): a placeable screen that shows the nearest silo, production or animal storage
-- live: used and total capacity, percent full, and every product with its own colour and bar.
--
-- The model holds a dark "screen" texture with the panels baked in. Everything that changes is drawn on
-- top of it on the client only: text with renderText3D every frame (depth tested), bars as copies of the
-- model's hidden glowing rectangle (barTemplate), placed and coloured by the script. Nothing is drawn on
-- a dedicated server.
--
-- Screen coordinates ("design units"): u from 0 (left) to 1.6 (right), v from 0 (top) to 1 (bottom).
-- The screen node sits in the centre of the glass, x right, y up, z out of the glass towards the viewer.

StorageMonitor = {}
StorageMonitor.MOD_NAME = g_currentModName
StorageMonitor.MOD_DIR = g_currentModDirectory
StorageMonitor.SAVE_KEY = (g_currentModName or "FS25_DigitalDTM") .. ".storageMonitor"
StorageMonitor.instances = {}

StorageMonitor.DESIGN_W = 1.6               -- screen aspect is 16:10
StorageMonitor.PAGE_TIME = 8000             -- ms per page, when not everything fits
StorageMonitor.MANUAL_PAUSE = 30000         -- ms the pages stay put after page up / down
StorageMonitor.DATA_INTERVAL = 1000         -- ms between fill level reads while someone is close
StorageMonitor.SCAN_INTERVAL = 15000        -- ms between looks for the storages around
StorageMonitor.SEARCH_RADIUS = 40           -- m; storages further away are not offered
StorageMonitor.PICK_TOLERANCE = 5           -- m a picked building may be from the remembered spot
StorageMonitor.MAX_PICK = 20                -- storages offered in the pick list
StorageMonitor.SIZE_WIDTHS = {0.8, 1.2, 1.6, 2.0, 2.4, 3.0, 3.6, 4.2, 4.8, 6.0}  -- m; screen sizes to choose from
StorageMonitor.GLASS_GLOW = 0.25            -- the screen's own glow (lightControl) at normal brightness
StorageMonitor.TITLE_MAX = 40               -- characters of a custom title
-- brightness levels: bars, screen glow and text are multiplied by factor
StorageMonitor.BRIGHTNESS = {
    {key = "storageMonitor_bright1", fallback = "Very dim", factor = 0.4},
    {key = "storageMonitor_bright2", fallback = "Dim", factor = 0.7},
    {key = "storageMonitor_bright3", fallback = "Normal", factor = 1.0},
    {key = "storageMonitor_bright4", fallback = "Bright", factor = 1.5},
    {key = "storageMonitor_bright5", fallback = "Very bright", factor = 2.2},
}
StorageMonitor.DEFAULT_BRIGHTNESS = 3
-- what the screen shows: the storage itself, or today's prices of what is in it
StorageMonitor.MODES = {
    {key = "storageMonitor_mode1", fallback = "Storage"},
    {key = "storageMonitor_mode2", fallback = "Prices"},
}
StorageMonitor.MODE_PRICES = 2
-- alerts: off, on the screen, on the screen and as a game message for the farm
StorageMonitor.ALERT_LEVELS = {
    {key = "storageMonitor_alerts1", fallback = "Off"},
    {key = "storageMonitor_alerts2", fallback = "On the screen"},
    {key = "storageMonitor_alerts3", fallback = "On the screen and as a message"},
}
StorageMonitor.DEFAULT_ALERTS = 2
StorageMonitor.ALERT_FULL = 90              -- % a silo / shed / tank counts as nearly full
StorageMonitor.ALERT_LOW = 0.10             -- ratio animal food, water, straw count as low
StorageMonitor.ALERT_REPEAT = 600000        -- ms before the same message is shown again
StorageMonitor.ALERT_CYCLE = 3000           -- ms each alert stays in the footer when there are several
StorageMonitor.MIN_LEVEL = 1                -- products below this many litres are not listed
StorageMonitor.FARM_PICK = -9999999         -- the pick position that means "all silos of my farm"
StorageMonitor.FINANCE_PICK = -8888888      -- the pick position that means "my farm's money"
-- rates: a sample of the levels every HISTORY_STEP in-game hours, kept for HISTORY_SPAN hours; a rate needs
-- RATE_MIN_SPAN hours of samples
StorageMonitor.HISTORY_STEP = 5 / 60
StorageMonitor.HISTORY_SPAN = 2
StorageMonitor.RATE_MIN_SPAN = 0.25
StorageMonitor.PRICE_INTERVAL = 10000       -- ms between price reads (shared by all monitors)
-- performance: monitors out of sight read their storage less often, and at most MAX_DRAWN are drawn
StorageMonitor.FAR_DATA_INTERVAL = 10000    -- ms between reads of a monitor nobody is near (rates, alerts)
StorageMonitor.MID_DATA_INTERVAL = 2500     -- ms between reads beyond half the draw distance
StorageMonitor.FAR_SCAN_INTERVAL = 120000   -- ms between looks for storages around a monitor nobody is near
StorageMonitor.MAX_DRAWN = 8
StorageMonitor.PANEL_ROWS = 3               -- rows of production lines / conditions in the top panel
StorageMonitor.OFFSET_BAR = 0.004           -- metres in front of the glass: bars
StorageMonitor.BAR_GLOW = 0.2               -- glow strength of the bars (emitColor = colour x this); 1.0
                                            -- washed every colour out to white in the game
StorageMonitor.OFFSET_TEXT = 0.009          -- metres in front of the glass: text

-- The list shrinks its text and adds columns until every product fits; only past 3 columns at the
-- smallest text it pages. Text size = row height x TEXT_PER_ROW (design units).
StorageMonitor.TEXT_PER_ROW = 0.62
StorageMonitor.LIST_FIT = {
    {cols = 1, minText = 0.027},
    {cols = 2, minText = 0.024},
    {cols = 3, minText = 0.018},
}

-- Layout, in design units. tools/make_textures.py bakes the panels at the same places (tests compare).
StorageMonitor.LAYOUT = {
    header      = {0.000, 0.000, 1.600, 0.105},
    capPanel    = {0.035, 0.130, 1.565, 0.370},
    listPanel   = {0.035, 0.395, 1.565, 0.905},
    footer      = {0.000, 0.930, 1.600, 1.000},
    listHeadV   = 0.440,
    listTopV    = 0.468,
    listBottomV = 0.899,
    listInnerU  = {0.065, 1.535},
    colGap      = 0.050,
    rowH        = 0.062,
    rowHMax     = 0.072,
    stackBar    = {0.420, 0.235, 1.530, 0.285},
    rowBarU     = {0.700, 1.170},
    rowBarHalfH = 0.011,
    pageBar     = {0.600, 0.962, 1.000, 0.968},
}

-- colours (r, g, b, a)
-- colours (r, g, b, a) of the theme being drawn; applyTheme fills them in from THEMES
StorageMonitor.COLORS = {
    text      = {0.90, 0.95, 1.00, 1},
    dim       = {0.50, 0.58, 0.69, 1},
    accent    = {0.22, 0.88, 1.00, 1},
    track     = {0.10, 0.15, 0.24, 1},
    stackFree = {0.10, 0.16, 0.26, 1},
    headText  = {0.90, 0.95, 1.00, 1},
    headAccent = {0.22, 0.88, 1.00, 1},
    ok        = {0.20, 0.83, 0.60, 1},
    warn      = {0.98, 0.75, 0.14, 1},
    full      = {0.97, 0.44, 0.44, 1},
    input     = {0.38, 0.65, 0.98, 1},
    output    = {0.98, 0.70, 0.30, 1},
}

-- Colour themes: a screen texture (tools/make_textures.py, same order) and the colours drawn on it.
-- monoPercent: percentages in the text colour (pale product colours do not read on a light screen).
StorageMonitor.THEMES = {
    {id = "night", key = "storageMonitor_theme1", fallback = "Night blue", texture = "textures/screen_night.dds", colors = {}},
    {id = "field", key = "storageMonitor_theme2", fallback = "DTM green", texture = "textures/screen_field.dds", colors = {
        text = {0.96, 0.95, 0.91, 1}, dim = {0.55, 0.68, 0.58, 1}, accent = {0.85, 0.64, 0.25, 1},
        track = {0.12, 0.25, 0.19, 1}, stackFree = {0.11, 0.23, 0.17, 1},
        headText = {0.96, 0.95, 0.91, 1}, headAccent = {0.85, 0.64, 0.25, 1}}},
    {id = "amber", key = "storageMonitor_theme3", fallback = "Amber terminal", texture = "textures/screen_amber.dds", colors = {
        text = {1.00, 0.70, 0.18, 1}, dim = {0.62, 0.42, 0.12, 1}, accent = {1.00, 0.80, 0.30, 1},
        track = {0.20, 0.13, 0.04, 1}, stackFree = {0.16, 0.10, 0.03, 1},
        headText = {1.00, 0.75, 0.25, 1}, headAccent = {1.00, 0.80, 0.30, 1}}},
    {id = "light", key = "storageMonitor_theme4", fallback = "Daylight", texture = "textures/screen_light.dds", monoPercent = true, colors = {
        text = {0.10, 0.14, 0.20, 1}, dim = {0.36, 0.42, 0.52, 1}, accent = {0.00, 0.45, 0.80, 1},
        track = {0.80, 0.84, 0.90, 1}, stackFree = {0.82, 0.86, 0.91, 1},
        headText = {0.95, 0.97, 1.00, 1}, headAccent = {0.55, 0.80, 1.00, 1},
        ok = {0.05, 0.55, 0.35, 1}, warn = {0.80, 0.50, 0.00, 1}, full = {0.80, 0.15, 0.15, 1}}},
}
-- the night theme is the defaults above
for key, value in pairs(StorageMonitor.COLORS) do
    StorageMonitor.THEMES[1].colors[key] = value
end

-- Product colours by fill type name. Anything not listed gets a colour from PALETTE by its name.
StorageMonitor.FILLTYPE_COLORS = {
    WHEAT = {0.93, 0.76, 0.33}, BARLEY = {0.85, 0.66, 0.36}, OAT = {0.89, 0.83, 0.58}, RYE = {0.72, 0.58, 0.38},
    CANOLA = {0.98, 0.90, 0.20}, SORGHUM = {0.80, 0.42, 0.25}, MAIZE = {1.00, 0.78, 0.10}, CORN = {1.00, 0.78, 0.10},
    SUNFLOWER = {1.00, 0.84, 0.00}, SOYBEAN = {0.86, 0.80, 0.55}, POTATO = {0.76, 0.58, 0.40},
    SUGARBEET = {0.92, 0.88, 0.80}, SUGARBEET_CUT = {0.88, 0.82, 0.72}, SUGARCANE = {0.56, 0.80, 0.36},
    COTTON = {0.97, 0.97, 0.97}, RICE = {0.95, 0.93, 0.85}, RICELONGGRAIN = {0.95, 0.92, 0.80},
    PEA = {0.55, 0.80, 0.35}, SPINACH = {0.20, 0.62, 0.30}, GREENBEAN = {0.35, 0.72, 0.30},
    CARROT = {1.00, 0.55, 0.15}, PARSNIP = {0.93, 0.88, 0.70}, BEETROOT = {0.70, 0.12, 0.35},
    ONION = {0.86, 0.68, 0.45}, GRAPE = {0.55, 0.25, 0.60}, OLIVE = {0.50, 0.55, 0.20},
    GRASS_WINDROW = {0.40, 0.80, 0.30}, DRYGRASS_WINDROW = {0.80, 0.80, 0.45}, STRAW = {0.95, 0.85, 0.50},
    SILAGE = {0.55, 0.65, 0.25}, CHAFF = {0.63, 0.85, 0.25}, WOODCHIPS = {0.72, 0.52, 0.32},
    ALFALFA_WINDROW = {0.45, 0.75, 0.35}, CLOVER_WINDROW = {0.50, 0.82, 0.45},
    FORAGE = {0.65, 0.70, 0.30}, FORAGE_MIXING = {0.60, 0.65, 0.35}, MINERAL_FEED = {0.75, 0.75, 0.80},
    PIGFOOD = {0.90, 0.60, 0.65}, SEEDS = {0.55, 0.82, 0.50}, FERTILIZER = {0.70, 0.85, 1.00},
    LIQUIDFERTILIZER = {0.45, 0.75, 1.00}, HERBICIDE = {0.75, 0.55, 0.95}, LIME = {0.92, 0.92, 0.88},
    WATER = {0.25, 0.60, 1.00}, MILK = {0.98, 0.98, 1.00}, GOATMILK = {0.95, 0.95, 0.90},
    BUFFALOMILK = {0.96, 0.96, 0.92}, DIESEL = {0.85, 0.75, 0.25}, DEF = {0.55, 0.85, 1.00},
    METHANE = {0.60, 0.90, 0.85}, ELECTRICCHARGE = {0.40, 0.85, 1.00},
    LIQUIDMANURE = {0.55, 0.42, 0.25}, MANURE = {0.48, 0.36, 0.22}, DIGESTATE = {0.45, 0.38, 0.28},
    SLURRY = {0.55, 0.42, 0.25}, EGG = {0.98, 0.92, 0.80}, WOOL = {0.95, 0.95, 0.95}, HONEY = {1.00, 0.70, 0.10},
    FLOUR = {0.98, 0.96, 0.90}, SUGAR = {1.00, 1.00, 1.00}, SUNFLOWER_OIL = {1.00, 0.85, 0.30},
    CANOLA_OIL = {0.95, 0.85, 0.25}, BUTTER = {1.00, 0.92, 0.55}, CHEESE = {1.00, 0.82, 0.35},
}
StorageMonitor.PALETTE = {
    {0.98, 0.55, 0.35}, {0.40, 0.85, 0.60}, {0.45, 0.70, 1.00}, {0.95, 0.80, 0.30}, {0.85, 0.50, 0.95},
    {0.35, 0.90, 0.90}, {1.00, 0.60, 0.75}, {0.70, 0.90, 0.40}, {1.00, 0.72, 0.40}, {0.60, 0.65, 1.00},
    {0.55, 0.95, 0.75}, {0.95, 0.45, 0.55},
}

local LAYOUT = StorageMonitor.LAYOUT
local COLORS = StorageMonitor.COLORS

-- puts the colours of theme index into COLORS (missing ones from the night theme)
function StorageMonitor.applyTheme(index)
    local theme = StorageMonitor.THEMES[index] or StorageMonitor.THEMES[1]
    local night = StorageMonitor.THEMES[1].colors
    for key in pairs(night) do
        COLORS[key] = theme.colors[key] or night[key]
    end
    return theme
end

-- ---------------------------------------------------------------------------------------------------
-- small helpers (pure Lua, tested offline)
-- ---------------------------------------------------------------------------------------------------

function StorageMonitor.log(fmt, ...)
    print(string.format("[StorageMonitor] " .. fmt, ...))
end

-- stable colour for a fill type name
function StorageMonitor.colorForName(name)
    name = tostring(name or "")
    local known = StorageMonitor.FILLTYPE_COLORS[name]
    if known ~= nil then
        return known
    end
    local h = 0
    for i = 1, #name do
        h = (h * 31 + string.byte(name, i)) % 1000003
    end
    return StorageMonitor.PALETTE[(h % #StorageMonitor.PALETTE) + 1]
end

-- colour for a fill percentage (0..100)
function StorageMonitor.levelColor(percent)
    if percent >= 90 then
        return COLORS.full
    elseif percent >= 75 then
        return COLORS.warn
    end
    return COLORS.ok
end

-- whole percent of value/total; 0 without a total; never shows 100 before it really is full
function StorageMonitor.percent(value, total)
    if total == nil or total <= 0 then
        return 0
    end
    local p = math.max(0, value or 0) / total * 100
    if p >= 99.5 and value < total then
        return 99
    end
    if p > 0 and p < 1 then
        return 1
    end
    return math.floor(p + 0.5)
end

-- 1234567 -> "1,234,567"
function StorageMonitor.groupDigits(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local sign = ""
    if string.sub(s, 1, 1) == "-" then
        sign, s = "-", string.sub(s, 2)
    end
    local out = s
    while true do
        local replaced, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
        out = replaced
        if count == 0 then
            break
        end
    end
    return sign .. out
end

function StorageMonitor.formatVolume(litres)
    if g_i18n ~= nil and g_i18n.formatVolume ~= nil then
        return g_i18n:formatVolume(math.floor((litres or 0) + 0.5), 0)
    end
    return StorageMonitor.groupDigits(litres) .. " l"
end

function StorageMonitor.formatMoney(amount)
    amount = math.floor((amount or 0) + 0.5)
    local sign = amount < 0 and "-" or ""
    amount = math.abs(amount)
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        return sign .. g_i18n:formatMoney(amount, 0, true, true)
    end
    return sign .. "$" .. StorageMonitor.groupDigits(amount)
end

-- 1234 -> "1.2k", 2500000 -> "2.5M" (short numbers for narrow columns)
function StorageMonitor.shortNumber(n)
    local a = math.abs(n or 0)
    local sign = (n or 0) < 0 and "-" or ""
    if a >= 1000000 then
        return string.format("%s%.1fM", sign, a / 1000000)
    elseif a >= 10000 then
        return string.format("%s%dk", sign, math.floor(a / 1000 + 0.5))
    elseif a >= 1000 then
        return string.format("%s%.1fk", sign, a / 1000)
    end
    return string.format("%s%d", sign, math.floor(a + 0.5))
end

-- a rate in litres per in-game hour: "+18,000 l/h"
function StorageMonitor.formatRate(perHour)
    local sign = perHour >= 0 and "+" or "-"
    return sign .. StorageMonitor.formatVolume(math.abs(perHour)) .. "/h"
end

-- in-game hours: "40 min", "6 h", "2.5 days"
function StorageMonitor.formatDuration(hours)
    local T = StorageMonitor.getText
    if hours < 1 then
        return string.format(T("storageMonitor_minutes", "%d min"), math.max(1, math.floor(hours * 60 + 0.5)))
    elseif hours < 10 then
        return string.format(T("storageMonitor_hours", "%s h"), string.format("%.1f", hours))
    elseif hours < 48 then
        return string.format(T("storageMonitor_hours", "%s h"), string.format("%d", math.floor(hours + 0.5)))
    end
    return string.format(T("storageMonitor_days", "%s days"), string.format("%.1f", hours / 24))
end

-- in-game time in hours since the start of the savegame, or nil
function StorageMonitor.gameHours()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil or type(env.dayTime) ~= "number" then
        return nil
    end
    local day = env.currentMonotonicDay or env.currentDay or 0
    return day * 24 + env.dayTime / 3600000
end

function StorageMonitor.getText(key, fallback)
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return fallback or key
end

-- storages of a station table: values or keys, whichever are the Storage objects
local function eachStorage(t, fn)
    if type(t) ~= "table" then
        return
    end
    for k, v in pairs(t) do
        local storage = nil
        if type(v) == "table" and v.getFillLevels ~= nil then
            storage = v
        elseif type(k) == "table" and k.getFillLevels ~= nil then
            storage = k
        end
        if storage ~= nil then
            fn(storage)
        end
    end
end
StorageMonitor.eachStorage = eachStorage

--- Builds what the screen shows from a list of sources.
-- source = {storage = Storage} or {levels = {[fillTypeIndex] = litres}, capacity = number|nil}
-- roles  = {[fillTypeIndex] = "in"|"out"} (productions), or nil
-- Shared-capacity storages (Storage.capacity set) count their capacity once; the others add up their
-- per-product capacities. Returns {items, used, capacity, count}.
--- Whether a Storage shares one capacity across all its products. Storage.capacity is set on every storage
-- (100,000 by default, also on productions with a capacity per product), so it only counts as shared when
-- every per-product capacity equals it and the contents fit in it. (A fermenting silo, a production with
-- 5,000,000 l per product, showed 4141 % before this.)
function StorageMonitor.isSharedCapacity(storage, fillLevels)
    local cap = storage.capacity
    if type(cap) ~= "number" or cap <= 0 then
        return false
    end
    for _, c in pairs(storage.capacities or {}) do
        if type(c) == "number" and math.abs(c - cap) > 0.5 then
            return false
        end
    end
    local total = 0
    for _, level in pairs(fillLevels or {}) do
        total = total + (tonumber(level) or 0)
    end
    return total <= cap + 1
end

-- the fill type a bunker silo shows: what goes in while filling, silage once it is closed
function StorageMonitor.bunkerFillType(b)
    local state = b.state
    if BunkerSilo ~= nil and (state == BunkerSilo.STATE_CLOSED or state == BunkerSilo.STATE_FERMENTED
        or state == BunkerSilo.STATE_DRAIN) then
        return b.outputFillType
    end
    return b.inputFillType
end

function StorageMonitor.buildSnapshot(sources, roles, fillTypeInfo)
    local levels, itemCaps, counts = {}, {}, {}
    local used, capacity = 0, 0

    for _, src in ipairs(sources) do
        local fillLevels, shared, perType = nil, nil, nil
        if src.bunker ~= nil then
            fillLevels = {}
            local ft = StorageMonitor.bunkerFillType(src.bunker)
            if ft ~= nil then
                fillLevels[ft] = tonumber(src.bunker.fillLevel) or 0
            end
        elseif src.objects ~= nil then
            -- bale / pallet shed: on clients each group holds ONE sample object and numObjects, so the
            -- litres are the sample's fill level x numObjects (as on the server)
            fillLevels = {}
            for _, info in ipairs(src.objects.objectInfos or {}) do
                local sample = info.objects ~= nil and info.objects[1] or nil
                local attributes = sample ~= nil and (sample.palletAttributes or sample.baleAttributes or sample.baleObject) or nil
                local ft = attributes ~= nil and attributes.fillType or nil
                local num = tonumber(info.numObjects) or 0
                if ft ~= nil then
                    fillLevels[ft] = (fillLevels[ft] or 0) + (tonumber(attributes.fillLevel) or 0) * num
                    counts[ft] = (counts[ft] or 0) + num
                end
            end
        elseif src.heap ~= nil then
            -- a manure heap without getFillLevels: one product and one capacity
            local heap = src.heap
            fillLevels = {}
            local ft = heap.fillTypeIndex
            if ft ~= nil and heap.getFillLevel ~= nil then
                fillLevels[ft] = tonumber(heap:getFillLevel(ft)) or 0
            end
            local cap = tonumber(heap.capacity)
            if cap == nil and heap.getCapacity ~= nil then
                cap = tonumber(heap:getCapacity(ft))
            end
            if cap ~= nil and cap > 0 then
                shared = cap
            end
        elseif src.storage ~= nil then
            local storage = src.storage
            fillLevels = storage:getFillLevels() or {}
            if StorageMonitor.isSharedCapacity(storage, fillLevels) then
                shared = storage.capacity
            else
                perType = storage.capacities or {}
            end
        else
            fillLevels = src.levels or {}
            if type(src.capacity) == "number" and src.capacity > 0 then
                shared = src.capacity
            end
        end

        if shared ~= nil then
            capacity = capacity + shared
        end
        for fillType, level in pairs(fillLevels) do
            level = tonumber(level) or 0
            levels[fillType] = (levels[fillType] or 0) + level
            used = used + level
            if shared ~= nil then
                itemCaps[fillType] = (itemCaps[fillType] or 0) + shared
            elseif perType ~= nil and type(perType[fillType]) == "number" then
                itemCaps[fillType] = (itemCaps[fillType] or 0) + perType[fillType]
                -- a capacity per product: count the room of the products that are in it (a production
                -- takes 13 kinds of grass; their empty room would make every percent tiny)
                if level >= StorageMonitor.MIN_LEVEL then
                    capacity = capacity + perType[fillType]
                end
            end
        end
    end

    local items = {}
    for fillType, level in pairs(levels) do
        local role = roles ~= nil and roles[fillType] or nil
        if level >= StorageMonitor.MIN_LEVEL or role ~= nil then      -- a production's inputs show even when empty
            local info = fillTypeInfo(fillType)
            if info ~= nil then
                local cap = itemCaps[fillType]
                table.insert(items, {
                    fillType = fillType,
                    name = info.name,
                    title = info.title,
                    level = level,
                    capacity = cap,
                    percent = StorageMonitor.percent(level, cap),
                    color = StorageMonitor.colorForName(info.name),
                    role = roles ~= nil and roles[fillType] or nil,
                    icon = info.icon,
                    missing = (role == "in" or role == "inout") and level < StorageMonitor.MIN_LEVEL,
                    count = counts[fillType],
                })
            end
        end
    end
    table.sort(items, function(a, b)
        if math.abs(a.level - b.level) > 0.5 then
            return a.level > b.level
        end
        return tostring(a.title) < tostring(b.title)
    end)

    return {items = items, used = used, capacity = capacity, count = #items}
end

--- Remembers the levels of a snapshot every HISTORY_STEP in-game hours (the last HISTORY_SPAN hours) and
-- puts the rates into it: snapshot.rate (all products, litres per in-game hour), item.rate, snapshot.foodRate.
-- history is the monitor's table; it starts again when the storage changes or the time jumps.
function StorageMonitor.updateRates(history, snapshot, now, key, food)
    if now == nil then
        return
    end
    local samples = history.samples
    local last = samples ~= nil and samples[#samples] or nil
    if samples == nil or history.key ~= key or last == nil or now < last.t - 1e-6
        or now - last.t > StorageMonitor.HISTORY_SPAN then
        samples = {}
        history.samples, history.key = samples, key
    end
    last = samples[#samples]
    if last == nil or now - last.t >= StorageMonitor.HISTORY_STEP - 1e-6 then
        local levels = {}
        for _, item in ipairs(snapshot.items) do
            levels[item.fillType] = item.level
        end
        table.insert(samples, {t = now, used = snapshot.used, levels = levels, food = food})
        while #samples > 1 and now - samples[1].t > StorageMonitor.HISTORY_SPAN + 1e-6 do
            table.remove(samples, 1)
        end
    end
    local first = samples[1]
    local span = now - first.t
    if span < StorageMonitor.RATE_MIN_SPAN - 1e-6 then
        return
    end
    snapshot.rate = (snapshot.used - first.used) / span
    for _, item in ipairs(snapshot.items) do
        local before = first.levels[item.fillType]
        if before ~= nil then
            item.rate = (item.level - before) / span
        end
    end
    if food ~= nil and first.food ~= nil then
        snapshot.foodRate = (food - first.food) / span
    end
end

-- hours until a level reaches 0 (falling) or the capacity (rising); nil when it does not change
function StorageMonitor.hoursLeft(level, capacity, rate)
    if rate == nil or math.abs(rate) < 1 then
        return nil
    end
    if rate < 0 then
        return math.max(0, level) / -rate, "empty"
    elseif capacity ~= nil and capacity > 0 then
        return math.max(0, capacity - level) / rate, "full"
    end
    return nil
end

--- How the product list fits the panel: as many columns and as small text as needed to show everything
-- at once; only past 3 columns at the smallest text does it page. Returns
-- {cols, rows, rowH, size, perPage, pages}.
function StorageMonitor.computeListLayout(count)
    local L = LAYOUT
    local avail = L.listBottomV - L.listTopV
    local n = math.max(1, count)
    for _, fit in ipairs(StorageMonitor.LIST_FIT) do
        local rows = math.ceil(n / fit.cols)
        local rowH = math.min(L.rowHMax, avail / rows)
        local size = rowH * StorageMonitor.TEXT_PER_ROW
        if size >= fit.minText - 1e-9 then
            return {cols = fit.cols, rows = rows, rowH = rowH, size = size, perPage = rows * fit.cols, pages = 1}
        end
    end
    local last = StorageMonitor.LIST_FIT[#StorageMonitor.LIST_FIT]
    local rows = math.max(1, math.floor(avail / (last.minText / StorageMonitor.TEXT_PER_ROW) + 1e-9))
    local rowH = avail / rows
    local perPage = rows * last.cols
    return {cols = last.cols, rows = rows, rowH = rowH, size = rowH * StorageMonitor.TEXT_PER_ROW, perPage = perPage,
            pages = math.ceil(n / perPage)}
end

-- left and right edge of list column c
function StorageMonitor.columnBounds(layout, c)
    local L = LAYOUT
    local inner = L.listInnerU[2] - L.listInnerU[1]
    local w = (inner - L.colGap * (layout.cols - 1)) / layout.cols
    local x0 = L.listInnerU[1] + (c - 1) * (w + L.colGap)
    return x0, x0 + w
end

-- ---------------------------------------------------------------------------------------------------
-- specialization
-- ---------------------------------------------------------------------------------------------------

function StorageMonitor.prerequisitesPresent(specializations)
    return true
end

function StorageMonitor.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", StorageMonitor)
    SpecializationUtil.registerEventListener(placeableType, "onPostFinalizePlacement", StorageMonitor)
    SpecializationUtil.registerEventListener(placeableType, "onDelete", StorageMonitor)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream", StorageMonitor)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream", StorageMonitor)
end

function StorageMonitor.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "storageMonitorTriggerCallback", StorageMonitor.storageMonitorTriggerCallback)
    SpecializationUtil.registerFunction(placeableType, "setStorageMonitorSettings", StorageMonitor.setStorageMonitorSettings)
    SpecializationUtil.registerFunction(placeableType, "setStorageMonitorSize", StorageMonitor.setStorageMonitorSize)
    SpecializationUtil.registerFunction(placeableType, "getStorageMonitorSettings", StorageMonitor.getStorageMonitorSettings)
    SpecializationUtil.registerFunction(placeableType, "rescanStorageMonitor", StorageMonitor.rescanStorageMonitor)
end

function StorageMonitor.registerOverwrittenFunctions(placeableType)
    SpecializationUtil.registerOverwrittenFunction(placeableType, "updateInfo", StorageMonitor.updateInfo)
end

function StorageMonitor.registerXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("StorageMonitor")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor#screenNode", "Centre of the screen glass, z towards the viewer")
    schema:register(XMLValueType.FLOAT, basePath .. ".storageMonitor#width", "Screen width in metres (height is width / 1.6)", 2.4)
    schema:register(XMLValueType.FLOAT, basePath .. ".storageMonitor#drawDistance", "Distance up to which the screen is drawn", 45)
    schema:register(XMLValueType.FLOAT, basePath .. ".storageMonitor#searchRadius", "Storages further away are not shown", StorageMonitor.SEARCH_RADIUS)
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor#playerTrigger", "Trigger for the monitor's actions")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor#barTemplate", "Hidden 1 x 1 m glowing rectangle, copied for every bar")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor#iconTemplate", "Hidden 1 x 1 m rectangle with UVs, copied for every product icon")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor#glassNode", "The screen glass (theme texture, glow)")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor#collisions", "Group of collisions, one per screen size, named collision_<width in cm>")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor.back#screenNode", "Second screen on the back (two-sided billboard)")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor.back#barTemplate", "Bar template of the back screen")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor.back#iconTemplate", "Icon template of the back screen")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor.back#glassNode", "Glass of the back screen")
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor.mount#node", "Node scaled to the chosen screen size")
    schema:register(XMLValueType.STRING, basePath .. ".storageMonitor.mount#mode", "silo: grows upwards from its bottom edge, z kept; ground: grows from the ground", "ground")
    schema:register(XMLValueType.FLOAT, basePath .. ".storageMonitor.mount#bottom", "Height of the screen's bottom edge above the ground", 2)
    schema:register(XMLValueType.FLOAT, basePath .. ".storageMonitor.mount#lowerExtent", "Mount node to the model's bottom edge at size 1", 0.85)
    schema:setXMLSpecializationType()
end

function StorageMonitor.initSpecialization()
    local schema = Placeable.xmlSchemaSavegame
    local key = "placeables.placeable(?)." .. StorageMonitor.SAVE_KEY
    schema:register(XMLValueType.BOOL, key .. "#picked", "A storage was picked (else the nearest is shown)", false)
    schema:register(XMLValueType.FLOAT, key .. "#pickX", "Position of the picked storage", 0)
    schema:register(XMLValueType.FLOAT, key .. "#pickZ", "Position of the picked storage", 0)
    schema:register(XMLValueType.BOOL, key .. "#connected", "Also show the silos connected to it", false)
    schema:register(XMLValueType.FLOAT, key .. "#size", "Screen width in metres")
    schema:register(XMLValueType.INT, key .. "#brightness", "Brightness level 1..5", StorageMonitor.DEFAULT_BRIGHTNESS)
    schema:register(XMLValueType.INT, key .. "#theme", "Colour theme 1..4", 1)
    schema:register(XMLValueType.STRING, key .. "#title", "Custom title, empty = the storage's name", "")
    schema:register(XMLValueType.INT, key .. "#mode", "1 = the storage, 2 = prices", 1)
    schema:register(XMLValueType.INT, key .. "#alerts", "1 = off, 2 = on the screen, 3 = also as a message", StorageMonitor.DEFAULT_ALERTS)
end

function StorageMonitor:onLoad(savegame)
    self.spec_storageMonitor = {}
    local spec = self.spec_storageMonitor
    local xmlFile = self.xmlFile

    spec.screenNode = xmlFile:getValue("placeable.storageMonitor#screenNode", nil, self.components, self.i3dMappings)
    spec.width = xmlFile:getValue("placeable.storageMonitor#width", 2.4)
    spec.height = spec.width / StorageMonitor.DESIGN_W
    spec.drawDistance = xmlFile:getValue("placeable.storageMonitor#drawDistance", 45)
    spec.searchRadius = xmlFile:getValue("placeable.storageMonitor#searchRadius", StorageMonitor.SEARCH_RADIUS)
    spec.playerTrigger = xmlFile:getValue("placeable.storageMonitor#playerTrigger", nil, self.components, self.i3dMappings)
    spec.barTemplate = xmlFile:getValue("placeable.storageMonitor#barTemplate", nil, self.components, self.i3dMappings)
    spec.iconTemplate = xmlFile:getValue("placeable.storageMonitor#iconTemplate", nil, self.components, self.i3dMappings)
    spec.glassNode = xmlFile:getValue("placeable.storageMonitor#glassNode", nil, self.components, self.i3dMappings)
    -- one collision per screen size (a static body cannot be scaled); the one that fits is switched on
    spec.collisions = {}
    local group = xmlFile:getValue("placeable.storageMonitor#collisions", nil, self.components, self.i3dMappings)
    if group ~= nil then
        for i = 0, getNumOfChildren(group) - 1 do
            local child = getChildAt(group, i)
            local cm = tonumber(string.match(getName(child) or "", "^collision_(%d+)$"))
            if cm ~= nil then
                table.insert(spec.collisions, {node = child, width = cm / 100})
            end
        end
    end
    -- the screens: the front one, and a second one on the back of a two-sided billboard; each has its own
    -- templates, glass, bars and icons
    spec.faces = {{screenNode = spec.screenNode, barTemplate = spec.barTemplate, iconTemplate = spec.iconTemplate,
                   glassNode = spec.glassNode, bars = {}, icons = {}}}
    local backScreen = xmlFile:getValue("placeable.storageMonitor.back#screenNode", nil, self.components, self.i3dMappings)
    if backScreen ~= nil then
        table.insert(spec.faces, {screenNode = backScreen,
            barTemplate = xmlFile:getValue("placeable.storageMonitor.back#barTemplate", nil, self.components, self.i3dMappings),
            iconTemplate = xmlFile:getValue("placeable.storageMonitor.back#iconTemplate", nil, self.components, self.i3dMappings),
            glassNode = xmlFile:getValue("placeable.storageMonitor.back#glassNode", nil, self.components, self.i3dMappings),
            bars = {}, icons = {}})
    end
    spec.bars = spec.faces[1].bars
    spec.icons = spec.faces[1].icons

    spec.mountNode = xmlFile:getValue("placeable.storageMonitor.mount#node", nil, self.components, self.i3dMappings)
    spec.mountMode = xmlFile:getValue("placeable.storageMonitor.mount#mode", "ground")
    spec.mountBottom = xmlFile:getValue("placeable.storageMonitor.mount#bottom", 2)
    spec.mountLowerExtent = xmlFile:getValue("placeable.storageMonitor.mount#lowerExtent", 0.85)
    spec.sizeScale = 1
    spec.mountWidth = spec.width

    -- what players set in the monitor's menu (synced and saved as one)
    spec.pick = nil                 -- {x, z} of the picked storage, nil = the nearest
    spec.connected = false
    spec.brightness = StorageMonitor.DEFAULT_BRIGHTNESS
    spec.theme = 1
    spec.title = ""
    spec.mode = 1
    spec.alerts = StorageMonitor.DEFAULT_ALERTS
    spec.history = {}
    spec.alertList = {}
    spec.alertKnown = nil           -- alerts seen at the last read (nil: no read yet, nothing is announced)
    spec.alertTime = 0
    spec.distance = math.huge
    self:setStorageMonitorSize(spec.width)
    StorageMonitor.applyLook(self)
    spec.candidates = {}
    spec.candidateCount = 0
    spec.target = nil
    spec.snapshot = nil
    spec.layout = StorageMonitor.computeListLayout(0)
    spec.page = 1
    spec.pageTime = 0
    spec.manualTime = 0
    spec.dataTimer = math.huge
    spec.scanTimer = math.huge
    spec.isNear = false
    spec.frame = nil
    spec.rowCache = {}

    if spec.screenNode == nil then
        StorageMonitor.log("Warning: no screenNode in %s", tostring(self.configFileName))
    end

    if self.isClient and spec.playerTrigger ~= nil then
        addTrigger(spec.playerTrigger, "storageMonitorTriggerCallback", self)
        spec.activatable = StorageMonitorActivatable.new(self)
    end
end

function StorageMonitor:onPostFinalizePlacement(savegame)
    local spec = self.spec_storageMonitor
    if spec == nil then
        return
    end
    table.insert(StorageMonitor.instances, self)
    spec.scanTimer = math.huge      -- look for a storage on the next update
end

function StorageMonitor:onDelete()
    local spec = self.spec_storageMonitor
    if spec == nil then
        return
    end
    for i = #StorageMonitor.instances, 1, -1 do
        if StorageMonitor.instances[i] == self then
            table.remove(StorageMonitor.instances, i)
        end
    end
    if StorageMonitor.activeMonitor == self then
        StorageMonitor.activeMonitor = nil
    end
    if spec.playerTrigger ~= nil and self.isClient then
        removeTrigger(spec.playerTrigger)
    end
    if spec.activatable ~= nil and g_currentMission ~= nil and g_currentMission.activatableObjectsSystem ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
    end
end

function StorageMonitor:loadFromXMLFile(xmlFile, key)
    local spec = self.spec_storageMonitor
    if spec == nil then
        return
    end
    local settings = self:getStorageMonitorSettings()
    if xmlFile:getValue(key .. "#picked", false) then
        settings.pick = {xmlFile:getValue(key .. "#pickX", 0), xmlFile:getValue(key .. "#pickZ", 0)}
    end
    settings.connected = xmlFile:getValue(key .. "#connected", false) == true
    settings.size = xmlFile:getValue(key .. "#size", settings.size)
    settings.brightness = xmlFile:getValue(key .. "#brightness", settings.brightness)
    settings.theme = xmlFile:getValue(key .. "#theme", settings.theme)
    settings.title = xmlFile:getValue(key .. "#title", "") or ""
    settings.mode = xmlFile:getValue(key .. "#mode", settings.mode)
    settings.alerts = xmlFile:getValue(key .. "#alerts", settings.alerts)
    self:setStorageMonitorSettings(settings, true)
end

function StorageMonitor:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_storageMonitor
    if spec == nil then
        return
    end
    xmlFile:setValue(key .. "#picked", spec.pick ~= nil)
    if spec.pick ~= nil then
        xmlFile:setValue(key .. "#pickX", spec.pick[1])
        xmlFile:setValue(key .. "#pickZ", spec.pick[2])
    end
    xmlFile:setValue(key .. "#connected", spec.connected)
    xmlFile:setValue(key .. "#size", spec.mountWidth)
    xmlFile:setValue(key .. "#brightness", spec.brightness)
    xmlFile:setValue(key .. "#theme", spec.theme)
    if spec.title ~= "" then
        xmlFile:setValue(key .. "#title", spec.title)
    end
    xmlFile:setValue(key .. "#mode", spec.mode)
    xmlFile:setValue(key .. "#alerts", spec.alerts)
end

-- the monitor's settings as a new table: change it and pass it to setStorageMonitorSettings
function StorageMonitor:getStorageMonitorSettings()
    local spec = self.spec_storageMonitor
    local pick = spec.pick ~= nil and {spec.pick[1], spec.pick[2]} or nil
    return {pick = pick, connected = spec.connected, size = spec.mountWidth, brightness = spec.brightness,
            theme = spec.theme, title = spec.title, mode = spec.mode, alerts = spec.alerts}
end

function StorageMonitor.writeSettings(streamId, settings)
    streamWriteBool(streamId, settings.pick ~= nil)
    if settings.pick ~= nil then
        streamWriteFloat32(streamId, settings.pick[1])
        streamWriteFloat32(streamId, settings.pick[2])
    end
    streamWriteBool(streamId, settings.connected == true)
    streamWriteFloat32(streamId, settings.size or 0)
    streamWriteUInt8(streamId, settings.brightness or StorageMonitor.DEFAULT_BRIGHTNESS)
    streamWriteUInt8(streamId, settings.theme or 1)
    streamWriteString(streamId, settings.title or "")
    streamWriteUInt8(streamId, settings.mode or 1)
    streamWriteUInt8(streamId, settings.alerts or StorageMonitor.DEFAULT_ALERTS)
end

function StorageMonitor.readSettings(streamId)
    local settings = {}
    if streamReadBool(streamId) then
        settings.pick = {streamReadFloat32(streamId), streamReadFloat32(streamId)}
    end
    settings.connected = streamReadBool(streamId)
    settings.size = streamReadFloat32(streamId)
    settings.brightness = streamReadUInt8(streamId)
    settings.theme = streamReadUInt8(streamId)
    settings.title = streamReadString(streamId)
    settings.mode = streamReadUInt8(streamId)
    settings.alerts = streamReadUInt8(streamId)
    return settings
end

function StorageMonitor:onWriteStream(streamId, connection)
    StorageMonitor.writeSettings(streamId, self:getStorageMonitorSettings())
end

function StorageMonitor:onReadStream(streamId, connection)
    self:setStorageMonitorSettings(StorageMonitor.readSettings(streamId), true)
end

-- resizes the screen to the given width in metres (clamped to SIZE_WIDTHS). A silo mount grows upwards from
-- its bottom edge and keeps its depth; a free-standing monitor grows from the ground, posts and all. Its
-- collision only fits the bought size, so it is switched off at any other size.
function StorageMonitor:setStorageMonitorSize(width)
    local spec = self.spec_storageMonitor
    if spec.mountNode == nil or width == nil or width <= 0 then
        return
    end
    local widths = StorageMonitor.SIZE_WIDTHS
    spec.mountWidth = math.max(widths[1], math.min(widths[#widths], width))
    spec.sizeScale = spec.mountWidth / spec.width
    local s = spec.sizeScale
    local x, y, z = getTranslation(spec.mountNode)
    if spec.mountMode == "silo" then
        setScale(spec.mountNode, s, s, 1)
        y = spec.mountBottom + spec.mountLowerExtent * s
    else
        setScale(spec.mountNode, s, s, s)
    end
    setTranslation(spec.mountNode, x, y, z)
    if setRigidBodyType ~= nil and RigidBodyType ~= nil then
        for _, c in ipairs(spec.collisions or {}) do
            local wanted = math.abs(c.width - spec.mountWidth) < 0.01 and RigidBodyType.STATIC or RigidBodyType.NONE
            if c.type ~= wanted then
                pcall(setRigidBodyType, c.node, wanted)
                c.type = wanted
            end
        end
    end
    spec.frame = nil
    for _, face in ipairs(spec.faces or {}) do
        face.frame = nil
    end
    spec.rowCache = {}
    spec.headerTitle = nil
end

-- brightness factor of the monitor (1 = normal)
function StorageMonitor.brightnessFactor(spec)
    local level = StorageMonitor.BRIGHTNESS[spec.brightness or StorageMonitor.DEFAULT_BRIGHTNESS]
    return level ~= nil and level.factor or 1
end

-- the screen texture of the theme and the screen's glow; the game's glowShader "staticLight" glows with its
-- texture, lightControl sets how much
function StorageMonitor:applyLook()
    local spec = self.spec_storageMonitor
    if getMaterial == nil then
        return
    end
    local theme = StorageMonitor.THEMES[spec.theme] or StorageMonitor.THEMES[1]
    for _, face in ipairs(spec.faces or {}) do
        local glass = face.glassNode
        if glass ~= nil then
            if face.glassMaterial == nil then
                face.glassMaterial = getMaterial(glass, 0)
            end
            local material = face.glassMaterial
            if spec.theme ~= 1 and setMaterialDiffuseMapFromFile ~= nil and StorageMonitor.MOD_DIR ~= nil then
                StorageMonitor.themeMaterials = StorageMonitor.themeMaterials or {}
                local cached = StorageMonitor.themeMaterials[theme.id]
                if cached == nil then
                    local ok, result = pcall(setMaterialDiffuseMapFromFile, face.glassMaterial, StorageMonitor.MOD_DIR .. theme.texture, true, true, false)
                    if ok and result ~= nil and result ~= 0 then
                        cached = result
                        StorageMonitor.themeMaterials[theme.id] = cached
                    else
                        StorageMonitor.log("Warning: theme texture %s not loaded", tostring(theme.texture))
                        StorageMonitor.themeMaterials[theme.id] = false
                    end
                end
                material = cached or material
            end
            if face.appliedMaterial ~= material then
                setMaterial(glass, material, 0)
                face.appliedMaterial = material
            end
            setShaderParameter(glass, "lightControl", StorageMonitor.GLASS_GLOW * StorageMonitor.brightnessFactor(spec), 0, 0, 0, false)
        end
    end
end

-- settings: see getStorageMonitorSettings. pick: {x, z} of the storage to show, or nil for the nearest;
-- connected: also show the silos connected to it; size: screen width in metres; brightness: 1..5;
-- theme: 1..4; title: custom title or "" for the storage's own name
function StorageMonitor:setStorageMonitorSettings(settings, noEventSend)
    local spec = self.spec_storageMonitor
    spec.pick = settings.pick
    spec.connected = settings.connected == true
    spec.brightness = math.max(1, math.min(#StorageMonitor.BRIGHTNESS, math.floor(settings.brightness or StorageMonitor.DEFAULT_BRIGHTNESS)))
    spec.theme = math.max(1, math.min(#StorageMonitor.THEMES, math.floor(settings.theme or 1)))
    local title = tostring(settings.title or "")
    if utf8Strlen ~= nil and utf8Substr ~= nil and utf8Strlen(title) > StorageMonitor.TITLE_MAX then
        title = utf8Substr(title, 0, StorageMonitor.TITLE_MAX)
    elseif #title > StorageMonitor.TITLE_MAX * 4 then
        title = string.sub(title, 1, StorageMonitor.TITLE_MAX * 4)
    end
    spec.title = title
    spec.mode = math.max(1, math.min(#StorageMonitor.MODES, math.floor(settings.mode or 1)))
    spec.alerts = math.max(1, math.min(#StorageMonitor.ALERT_LEVELS, math.floor(settings.alerts or StorageMonitor.DEFAULT_ALERTS)))
    self:setStorageMonitorSize(settings.size)
    StorageMonitor.applyLook(self)
    spec.headerTitle = nil
    spec.rowCache = {}
    spec.scanTimer = math.huge
    spec.page = 1
    spec.pageTime = 0
    StorageMonitorSettingsEvent.sendEvent(self, self:getStorageMonitorSettings(), noEventSend)
end

function StorageMonitor:storageMonitorTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    local spec = self.spec_storageMonitor
    if spec.activatable == nil or g_localPlayer == nil or otherId ~= g_localPlayer.rootNode then
        return
    end
    if onEnter then
        g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
        StorageMonitor.activeMonitor = self
    elseif onLeave then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
        if StorageMonitor.activeMonitor == self then
            StorageMonitor.activeMonitor = nil
        end
    end
end

function StorageMonitor:updateInfo(superFunc, infoTable)
    superFunc(self, infoTable)
    local spec = self.spec_storageMonitor
    if spec == nil then
        return
    end
    local text
    if spec.target ~= nil then
        text = spec.target.title
    else
        text = StorageMonitor.getText("storageMonitor_noStorage", "No storage nearby")
    end
    table.insert(infoTable, {title = StorageMonitor.getText("storageMonitor_showing", "Showing"), text = text})
end

-- ---------------------------------------------------------------------------------------------------
-- finding the storage to show (client side; every client finds the same one)
-- ---------------------------------------------------------------------------------------------------

local function nodePosition(node)
    if node == nil or node == 0 or (entityExists ~= nil and not entityExists(node)) then
        return nil
    end
    local x, y, z = getWorldTranslation(node)
    return {x, y, z}
end

local function getPlayerFarmId()
    if g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
        return g_localPlayer.farmId
    end
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        return g_currentMission:getFarmId()
    end
    return 1
end
StorageMonitor.getPlayerFarmId = getPlayerFarmId

local function placeableName(placeable, fallback)
    if placeable ~= nil and placeable.getName ~= nil then
        local ok, name = pcall(placeable.getName, placeable)
        if ok and name ~= nil and name ~= "" then
            return name
        end
    end
    return fallback
end

-- the player's farm may see this storage (own farm, or open to everyone)
local function isAccessible(storage, farmId)
    if storage.getOwnerFarmId == nil then
        return true
    end
    local owner = storage:getOwnerFarmId()
    local everyone = AccessHandler ~= nil and AccessHandler.EVERYONE or 0
    return owner == nil or owner == farmId or owner == everyone
end

-- stations a storage is connected to (keys or values of storage.loadingStations / unloadingStations)
local function eachStation(storage, fn)
    for _, field in ipairs({"loadingStations", "unloadingStations"}) do
        local t = storage[field]
        if type(t) == "table" then
            for k, v in pairs(t) do
                local station = (type(k) == "table" and k) or (type(v) == "table" and v) or nil
                if station ~= nil then
                    fn(station)
                end
            end
        end
    end
end

--- Storages of the placeable plus every storage that shares a loading or unloading station with them
-- (a silo and its extensions). Returns the list; the placeable's own storages come first.
function StorageMonitor.connectedStorages(own, farmId)
    local seen, list = {}, {}
    local function add(storage)
        if not seen[storage] and isAccessible(storage, farmId) then
            seen[storage] = true
            table.insert(list, storage)
        end
    end
    for _, storage in ipairs(own) do
        add(storage)
    end
    for _, storage in ipairs(own) do
        eachStation(storage, function(station)
            eachStorage(station.sourceStorages, add)
            eachStorage(station.targetStorages, add)
        end)
    end
    return list
end

--- Every storage this monitor could show, nearest first: {name, distance, storages, extra, roles, owner}.
-- One entry per building: a silo, a silo extension, a production, an animal pen. Connected silos are
-- separate entries; the "connected" setting adds them to the one shown.
function StorageMonitor:collectStorageCandidates()
    local spec = self.spec_storageMonitor
    local mission = g_currentMission
    if mission == nil then
        return {}
    end
    local mx, _, mz = getWorldTranslation(self.rootNode)
    local farmId = getPlayerFarmId()
    local byOwner, order, owned = {}, {}, {}

    local function candidateFor(owner, name)
        local c = byOwner[owner]
        if c == nil then
            c = {owner = owner, name = name, distance = math.huge, storages = {}, extra = {}, roles = nil, kind = "silo"}
            byOwner[owner] = c
            table.insert(order, c)
        end
        return c
    end
    local function near(c, pos)
        if pos ~= nil then
            if c.anchor == nil then
                c.anchor = {pos[1], pos[3]}     -- where the building is: what a pick remembers
            end
            local d = math.sqrt((pos[1] - mx) ^ 2 + (pos[3] - mz) ^ 2)
            if d < c.distance then
                c.distance = d
            end
        end
    end
    local function addStorage(c, storage)
        if not owned[storage] then
            owned[storage] = c
            table.insert(c.storages, storage)
            near(c, nodePosition(storage.rootNode))
        end
    end

    -- buildings with storages: silos, silo extensions, animal pens, productions
    local placeables = mission.placeableSystem ~= nil and mission.placeableSystem.placeables or {}
    local hives = nil       -- the farm's beehives, one entry for all of them
    for _, p in ipairs(placeables) do
        local ownHive = p ~= self and (p.spec_beehive ~= nil or p.spec_beehivePalletSpawner ~= nil)
            and p.getOwnerFarmId ~= nil and p:getOwnerFarmId() == farmId
        if ownHive then
            if hives == nil then
                hives = candidateFor("beehives", StorageMonitor.getText("storageMonitor_beehives", "Beehives"))
                hives.kind, hives.hives, hives.spawners = "beehive", {}, {}
            end
            table.insert(p.spec_beehive ~= nil and hives.hives or hives.spawners, p)
            near(hives, nodePosition(p.rootNode))
        end
        if p ~= self and not ownHive then
            local storages = {}
            local function take(storage)
                if type(storage) == "table" and storage.getFillLevels ~= nil and isAccessible(storage, farmId) then
                    table.insert(storages, storage)
                end
            end
            if p.spec_silo ~= nil and type(p.spec_silo.storages) == "table" then
                for _, storage in pairs(p.spec_silo.storages) do
                    take(storage)
                end
            end
            if p.spec_siloExtension ~= nil then
                take(p.spec_siloExtension.storage)
            end
            if p.spec_husbandry ~= nil then
                take(p.spec_husbandry.storage)
            end
            local pp = p.spec_productionPoint ~= nil and p.spec_productionPoint.productionPoint or nil
            if pp ~= nil then
                take(pp.storage)
            end
            local ownFarm = p.getOwnerFarmId ~= nil and p:getOwnerFarmId() == farmId
            local food = p.spec_husbandryFood
            local hasFood = food ~= nil and type(food.fillLevels) == "table" and ownFarm
            local isHusbandry = (p.spec_husbandryAnimals ~= nil or p.spec_husbandry ~= nil) and ownFarm
            -- bunker silos (no Storage: their level is the heap) and bale / pallet sheds
            local bunkers = {}
            if ownFarm and p.spec_bunkerSilo ~= nil and p.spec_bunkerSilo.bunkerSilo ~= nil then
                bunkers = {p.spec_bunkerSilo.bunkerSilo}
            elseif ownFarm and p.spec_multiBunkerSilo ~= nil and type(p.spec_multiBunkerSilo.bunkerSilos) == "table" then
                bunkers = p.spec_multiBunkerSilo.bunkerSilos
            end
            local objectStorage = ownFarm and p.spec_objectStorage or nil
            -- a manure heap: a Storage when it has getFillLevels, else read through its own functions
            local heap = p.spec_manureHeap ~= nil and p.spec_manureHeap.manureHeap or nil
            local heapSource = nil
            if heap ~= nil and type(heap) == "table" then
                if heap.getFillLevels ~= nil then
                    take(heap)
                elseif isAccessible(heap, farmId) then
                    heapSource = {heap = heap}
                    owned[heap] = true
                end
            end

            if #storages > 0 or hasFood or isHusbandry or #bunkers > 0 or objectStorage ~= nil or heapSource ~= nil then
                local c = candidateFor(p, placeableName(p, "Storage"))
                near(c, nodePosition(p.rootNode))
                c.placeable = p
                if heap ~= nil and pp == nil and not isHusbandry then
                    c.kind = "manure"
                    if heapSource ~= nil then
                        table.insert(c.extra, heapSource)
                    end
                end
                if pp ~= nil then
                    c.kind, c.pp = "production", pp
                    c.greenhouse = p.spec_greenhouse
                elseif isHusbandry then
                    c.kind = "husbandry"
                elseif #bunkers > 0 then
                    c.kind, c.bunkers = "bunker", bunkers
                    for _, b in ipairs(bunkers) do
                        table.insert(c.extra, {bunker = b})
                    end
                elseif objectStorage ~= nil then
                    c.kind, c.objectStorage = "objects", objectStorage
                    table.insert(c.extra, {objects = objectStorage})
                end
                for _, storage in ipairs(storages) do
                    addStorage(c, storage)
                end
                if hasFood then
                    table.insert(c.extra, {levels = food.fillLevels, capacity = tonumber(food.capacity)})
                end
                if pp ~= nil and #storages > 0 then
                    c.roles = c.roles or {}
                    for fillType in pairs(pp.inputFillTypeIds or {}) do
                        c.roles[fillType] = "in"
                    end
                    for fillType in pairs(pp.outputFillTypeIds or {}) do
                        c.roles[fillType] = (c.roles[fillType] == "in") and "inout" or "out"
                    end
                end
            end
        end
    end

    -- storages of other mods' buildings, found through their stations
    local storageSystem = mission.storageSystem
    local function addStations(stations, field)
        if type(stations) ~= "table" then
            return
        end
        for _, station in pairs(stations) do
            if type(station) == "table" and not station.isSellingPoint then
                eachStorage(station[field], function(storage)
                    if not owned[storage] and isAccessible(storage, farmId) then
                        local owner = station.owningPlaceable or station
                        local fallback = station.getName ~= nil and station:getName() or "Storage"
                        local c = candidateFor(owner, placeableName(station.owningPlaceable, fallback))
                        near(c, nodePosition(owner.rootNode))
                        near(c, nodePosition(station.rootNode))
                        addStorage(c, storage)
                    end
                end)
            end
        end
    end
    if storageSystem ~= nil then
        if storageSystem.getLoadingStations ~= nil then
            addStations(storageSystem:getLoadingStations(), "sourceStorages")
        end
        if storageSystem.getUnloadingStations ~= nil then
            addStations(storageSystem:getUnloadingStations(), "targetStorages")
        end
    end

    local result = {}
    for _, c in ipairs(order) do
        if c.distance <= spec.searchRadius and c.anchor ~= nil then
            table.insert(result, c)
        end
    end
    table.sort(result, function(a, b)
        if math.abs(a.distance - b.distance) > 0.01 then
            return a.distance < b.distance
        end
        return tostring(a.name) < tostring(b.name)
    end)

    -- last in the list, only when picked: every silo and silo extension of the farm together
    local all = {}
    for _, c in ipairs(order) do
        if c.kind == "silo" and c.placeable ~= nil
            and (c.placeable.spec_silo ~= nil or c.placeable.spec_siloExtension ~= nil) then
            for _, storage in ipairs(c.storages) do
                table.insert(all, storage)
            end
        end
    end
    if #all > 0 then
        table.insert(result, {owner = "farm", kind = "farm", storages = all, extra = {}, distance = math.huge,
            name = StorageMonitor.getText("storageMonitor_farmAll", "All silos of my farm"),
            anchor = {StorageMonitor.FARM_PICK, StorageMonitor.FARM_PICK}})
    end
    -- and the farm's money and loan, also only when picked
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        table.insert(result, {owner = "finance", kind = "finance", storages = {}, extra = {}, distance = math.huge,
            name = StorageMonitor.getText("storageMonitor_finance", "My farm's money"),
            anchor = {StorageMonitor.FINANCE_PICK, StorageMonitor.FINANCE_PICK}})
    end
    return result
end

--- The candidate to show: the picked one (the building nearest the remembered spot, within PICK_TOLERANCE),
-- else the nearest. A picked building that is gone falls back to the nearest.
function StorageMonitor.choose(candidates, pick)
    if pick ~= nil then
        local best, bestD = nil, StorageMonitor.PICK_TOLERANCE
        for _, c in ipairs(candidates) do
            local d = math.sqrt((c.anchor[1] - pick[1]) ^ 2 + (c.anchor[2] - pick[2]) ^ 2)
            if d <= bestD then
                best, bestD = c, d
            end
        end
        if best ~= nil then
            return best
        end
    end
    for _, c in ipairs(candidates) do      -- the nearest real building, never the farm overview or money
        if c.kind ~= "farm" and c.kind ~= "finance" then
            return c
        end
    end
    return nil
end

function StorageMonitor:rescanStorageMonitor()
    local spec = self.spec_storageMonitor
    local candidates = StorageMonitor.collectStorageCandidates(self)
    spec.candidates = candidates
    spec.candidateCount = #candidates
    local previous = spec.target
    spec.target = nil
    local c = StorageMonitor.choose(candidates, spec.pick)
    if c ~= nil then
        local storages = c.storages
        local title = c.name
        if spec.connected and #c.storages > 0 then
            storages = StorageMonitor.connectedStorages(c.storages, getPlayerFarmId())
            local more = #storages - #c.storages
            if more > 0 then
                title = string.format(StorageMonitor.getText("storageMonitor_plusConnected", "%s + %d connected"), c.name, more)
            end
        end
        local sources = {}
        for _, storage in ipairs(storages) do
            table.insert(sources, {storage = storage})
        end
        for _, extra in ipairs(c.extra) do
            table.insert(sources, extra)
        end
        spec.target = {name = c.name, title = title, sources = sources, roles = c.roles, owner = c.owner,
                       anchor = c.anchor, connectedCount = #storages - #c.storages, kind = c.kind,
                       placeable = c.placeable, pp = c.pp, bunkers = c.bunkers, objectStorage = c.objectStorage,
                       greenhouse = c.greenhouse, hives = c.hives, spawners = c.spawners}
    end
    if previous == nil or spec.target == nil or previous.owner ~= spec.target.owner then
        spec.page = 1
        spec.pageTime = 0
        spec.alertKnown = nil       -- what a newly shown storage already has is not announced
    end
    spec.scanTimer = 0
    spec.dataTimer = math.huge      -- read the levels right away
end

local function fillTypeInfo(fillTypeIndex)
    if g_fillTypeManager == nil then
        return nil
    end
    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    if fillType == nil then
        return nil
    end
    return {name = fillType.name, title = fillType.title or fillType.name, icon = fillType.hudOverlayFilename}
end

StorageMonitor.LINE_TEXTS = {running = "Running", missing = "Missing inputs", full = "Output full", off = "Off"}
StorageMonitor.BUNKER_TEXTS = {filling = "Filling", fermenting = "Fermenting", ready = "Ready"}

local function ratioOf(value, capacity)
    if capacity == nil or capacity <= 0 then
        return 0
    end
    return math.max(0, math.min(1, (value or 0) / capacity))
end

local function call(object, name, ...)
    if object ~= nil and type(object[name]) == "function" then
        local ok, a, b = pcall(object[name], object, ...)
        if ok then
            return a, b
        end
    end
    return nil
end

--- What the top panel shows for the kinds that are not plain storages: production lines, animals and their
-- condition, bunker silos, bale / pallet sheds. nil for silos (capacity panel).
function StorageMonitor.buildPanel(target)
    local T = StorageMonitor.getText
    if target.kind == "production" and target.pp ~= nil then
        local pp = target.pp
        local active = {}
        for _, production in ipairs(pp.activeProductions or {}) do
            active[production] = true
        end
        local panel = {kind = "production", lines = {}, running = 0}
        local status = ProductionPoint ~= nil and ProductionPoint.PROD_STATUS or {}
        for _, production in ipairs(pp.productions or {}) do
            local name = production.name
            if (name == nil or name == "") and production.primaryProductFillType ~= nil and g_fillTypeManager ~= nil then
                name = g_fillTypeManager:getFillTypeTitleByIndex(production.primaryProductFillType)
            end
            local st = production.status
            local line = {name = tostring(name or production.id or "?"), color = COLORS.dim}
            if not active[production] or st == status.INACTIVE then
                line.state = "off"
            elseif st == status.RUNNING then
                line.state = "running"
                panel.running = panel.running + 1
            elseif st == status.MISSING_INPUTS then
                line.state = "missing"
            elseif st == status.NO_OUTPUT_SPACE then
                line.state = "full"
            else
                line.state = "off"
            end
            local key = ProductionPoint ~= nil and ProductionPoint.PROD_STATUS_TO_L10N ~= nil
                and ProductionPoint.PROD_STATUS_TO_L10N[st] or nil
            line.text = (key ~= nil and g_i18n ~= nil and g_i18n:hasText(key)) and g_i18n:getText(key)
                or T("storageMonitor_line_" .. line.state, StorageMonitor.LINE_TEXTS[line.state])
            table.insert(panel.lines, line)
        end
        if target.greenhouse ~= nil then       -- a greenhouse: its plants need water
            panel.greenhouse = true
            panel.noWater = target.greenhouse.hasWater == false
        end
        return panel
    elseif target.kind == "husbandry" and target.placeable ~= nil then
        local p = target.placeable
        local panel = {kind = "husbandry", animals = call(p, "getNumOfAnimals") or 0,
                       maxAnimals = call(p, "getMaxNumOfAnimals") or 0, conditions = {}}
        local food, foodCap = call(p, "getTotalFood"), call(p, "getFoodCapacity")
        if foodCap ~= nil and foodCap > 0 then
            panel.food = tonumber(food) or 0
            table.insert(panel.conditions, {title = T("storageMonitor_food", "Food"), ratio = ratioOf(food, foodCap), isFood = true})
        end
        -- what the animals eat per in-game hour (the game's own number); else the rate seen on the screen
        local foodSpec = p.spec_husbandryFood
        if foodSpec ~= nil and type(foodSpec.litersPerHour) == "number" and foodSpec.litersPerHour > 0 then
            local env = g_currentMission ~= nil and g_currentMission.environment or nil
            panel.foodPerHour = foodSpec.litersPerHour * ((env ~= nil and tonumber(env.timeAdjustment)) or 1)
        end
        for _, info in ipairs(call(p, "getConditionInfos") or {}) do
            if not info.disabled then
                table.insert(panel.conditions, {title = tostring(info.title or ""), ratio = math.max(0, math.min(1, info.ratio or 0)),
                    inverted = info.invertedBar == true, valueText = info.valueText,
                    supply = info.invertedBar ~= true and info.valueText == nil})
            end
        end
        return panel
    elseif target.kind == "beehive" then
        local panel = {kind = "beehive", hives = #(target.hives or {}), honeyPerDay = 0, active = true, flying = false,
                       spawner = #(target.spawners or {}) > 0, palletFull = false}
        local system = g_currentMission ~= nil and g_currentMission.beehiveSystem or nil
        if system ~= nil then
            panel.active = system.isProductionActive ~= false
            panel.flying = system.isFxActive == true
        end
        for _, hive in ipairs(target.hives or {}) do
            local s = hive.spec_beehive
            if s ~= nil and type(s.honeyPerHour) == "number" then
                panel.honeyPerDay = panel.honeyPerDay + s.honeyPerHour * 24
            end
        end
        for _, spawner in ipairs(target.spawners or {}) do
            local s = spawner.spec_beehivePalletSpawner
            if s ~= nil and s.palletLimitReached then
                panel.palletFull = true
            end
        end
        -- what a day's honey is worth at the best price
        local honey = g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeIndexByName ~= nil
            and g_fillTypeManager:getFillTypeIndexByName("HONEY") or nil
        local best = honey ~= nil and StorageMonitor.bestPrice(honey) or nil
        if best ~= nil then
            panel.honeyValue = panel.honeyPerDay * best.price
        end
        return panel
    elseif target.kind == "finance" then
        local farm = g_farmManager ~= nil and g_farmManager:getFarmById(getPlayerFarmId()) or nil
        if farm == nil then
            return nil
        end
        local panel = {kind = "finance", money = tonumber(farm.money) or 0, loan = tonumber(farm.loan) or 0,
                       loanMax = tonumber(farm.loanMax), income = 0, expenses = 0, lines = {}}
        if farm.getBalance ~= nil then
            panel.money = tonumber(call(farm, "getBalance")) or panel.money
        end
        -- today's finances by category, as the game's finances page lists them
        local finances = farm.stats ~= nil and farm.stats.finances or nil
        if type(finances) == "table" then
            local names = (FinanceStats ~= nil and type(FinanceStats.statNames) == "table") and FinanceStats.statNames or nil
            local function add(name, value)
                value = tonumber(value)
                if value ~= nil and math.abs(value) >= 0.5 then
                    if value > 0 then
                        panel.income = panel.income + value
                    else
                        panel.expenses = panel.expenses + value
                    end
                    table.insert(panel.lines, {name = name, value = value,
                        title = T("finance_" .. name, (string.gsub(string.gsub(name, "(%l)(%u)", "%1 %2"), "^%l", string.upper)))})
                end
            end
            if names ~= nil then
                for _, name in ipairs(names) do
                    add(name, finances[name])
                end
            else
                for name, value in pairs(finances) do
                    if type(name) == "string" and type(value) == "number" then
                        add(name, value)
                    end
                end
            end
            table.sort(panel.lines, function(a, b)
                if math.abs(math.abs(a.value) - math.abs(b.value)) > 0.5 then
                    return math.abs(a.value) > math.abs(b.value)
                end
                return a.name < b.name
            end)
        end
        return panel
    elseif target.kind == "bunker" and target.bunkers ~= nil then
        local panel = {kind = "bunker", bunkers = {}, ready = 0}
        local B = BunkerSilo or {}
        for i, b in ipairs(target.bunkers) do
            local entry = {index = i, fillLevel = tonumber(b.fillLevel) or 0}
            if b.state == B.STATE_FERMENTED or b.state == B.STATE_DRAIN then
                entry.state, entry.percent = "ready", 100
                panel.ready = panel.ready + 1
            elseif b.state == B.STATE_CLOSED then
                entry.state, entry.percent = "fermenting", math.ceil((tonumber(b.fermentingPercent) or 0) * 100)
            else
                entry.state, entry.percent = "filling", tonumber(b.compactedPercent) or 0
            end
            entry.text = T("storageMonitor_bunker_" .. entry.state, StorageMonitor.BUNKER_TEXTS[entry.state])
            table.insert(panel.bunkers, entry)
        end
        return panel
    elseif target.kind == "objects" and target.objectStorage ~= nil then
        local o = target.objectStorage
        return {kind = "objects", count = tonumber(o.numStoredObjects) or 0, capacity = tonumber(o.capacity) or 0}
    end
    return nil
end

-- ---------------------------------------------------------------------------------------------------
-- prices: the best price for a product at the map's selling points, read for all monitors at most every
-- PRICE_INTERVAL; the trend is the game's seasonal price curve (this month to next)
-- ---------------------------------------------------------------------------------------------------

StorageMonitor.clock = 0                -- ms, advanced by the listener
StorageMonitor.priceCache = nil

-- the selling points: unloading stations that sell (as the game counts them for a silo's sell value), not the
-- farm's own productions or animal pens
function StorageMonitor.getSellingStations()
    local list = {}
    local storageSystem = g_currentMission ~= nil and g_currentMission.storageSystem or nil
    if storageSystem == nil or storageSystem.getUnloadingStations == nil then
        return list
    end
    for _, station in pairs(storageSystem:getUnloadingStations() or {}) do
        local p = type(station) == "table" and station.owningPlaceable or nil
        if p ~= nil and station.isSellingPoint and type(station.acceptedFillTypes) == "table"
            and station.getEffectiveFillTypePrice ~= nil and p.spec_productionPoint == nil and p.spec_husbandry == nil then
            table.insert(list, station)
        end
    end
    return list
end

local function stationName(station)
    local name = call(station, "getName")
    if name == nil or name == "" then
        name = placeableName(station.owningPlaceable, "?")
    end
    return tostring(name)
end

--- Best price per litre of a fill type and where: {price, station}, or nil when nobody buys it.
function StorageMonitor.bestPrice(fillTypeIndex)
    local cache = StorageMonitor.priceCache
    if cache == nil or StorageMonitor.clock - cache.time >= StorageMonitor.PRICE_INTERVAL then
        cache = {time = StorageMonitor.clock, stations = StorageMonitor.getSellingStations(), best = {}}
        StorageMonitor.priceCache = cache
    end
    local best = cache.best[fillTypeIndex]
    if best == nil then
        best = false
        for _, station in ipairs(cache.stations) do
            if station.acceptedFillTypes[fillTypeIndex] then
                local price = tonumber(call(station, "getEffectiveFillTypePrice", fillTypeIndex)) or 0
                if price > 0 and (not best or price > best.price) then
                    best = {price = price, station = stationName(station)}
                end
            end
        end
        cache.best[fillTypeIndex] = best
    end
    return best or nil
end

--- The seasonal trend of a fill type's price, in percent from this month to the next (nil without a curve).
function StorageMonitor.priceTrend(fillTypeIndex)
    local fillType = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex) or nil
    local factors = fillType ~= nil and fillType.economy ~= nil and fillType.economy.factors or nil
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local period = env ~= nil and tonumber(env.currentPeriod) or nil
    if type(factors) ~= "table" or period == nil then
        return nil
    end
    local periods = (Environment ~= nil and Environment.PERIODS_IN_YEAR) or 12
    local now = tonumber(factors[period])
    local nextFactor = tonumber(factors[period % periods + 1])
    if now == nil or nextFactor == nil or now <= 0 then
        return nil
    end
    return (nextFactor / now - 1) * 100
end

--- Puts prices into the snapshot's items: price (per litre), station, value (level x price), trend; and the
-- totals: snapshot.value, snapshot.rising, snapshot.falling, snapshot.topItem, snapshot.topStation.
function StorageMonitor.addPrices(snapshot)
    local value, rising, falling = 0, 0, 0
    local byStation = {}
    local top = nil
    for _, item in ipairs(snapshot.items) do
        local best = StorageMonitor.bestPrice(item.fillType)
        item.price, item.station, item.value = nil, nil, 0
        if best ~= nil then
            item.price, item.station = best.price, best.station
            item.value = item.level * best.price
            value = value + item.value
            byStation[best.station] = (byStation[best.station] or 0) + item.value
            if top == nil or item.value > top.value then
                top = item
            end
        end
        item.trend = StorageMonitor.priceTrend(item.fillType)
        if item.trend ~= nil and item.trend >= 0.5 then
            rising = rising + 1
        elseif item.trend ~= nil and item.trend <= -0.5 then
            falling = falling + 1
        end
    end
    local topStation, topValue = nil, 0
    for name, v in pairs(byStation) do
        if v > topValue or (v == topValue and topStation ~= nil and name < topStation) then
            topStation, topValue = name, v
        end
    end
    snapshot.value, snapshot.rising, snapshot.falling = value, rising, falling
    snapshot.topItem, snapshot.topStation, snapshot.topStationValue = top, topStation, topValue
    -- most valuable first; products nobody buys last
    table.sort(snapshot.items, function(a, b)
        if math.abs((a.value or 0) - (b.value or 0)) > 0.5 then
            return (a.value or 0) > (b.value or 0)
        end
        return tostring(a.title) < tostring(b.title)
    end)
end

-- ---------------------------------------------------------------------------------------------------
-- alerts: what needs attention at the storage shown
-- ---------------------------------------------------------------------------------------------------

-- what an animal pen makes: a full tank of these loses production (a full water or straw store does not)
StorageMonitor.ANIMAL_OUTPUTS = {MILK = true, GOATMILK = true, BUFFALOMILK = true, EGG = true, WOOL = true,
    LIQUIDMANURE = true, MANURE = true, SLURRY = true}

--- The alerts of a snapshot: {key, text}, most important first.
function StorageMonitor.computeAlerts(target, snapshot)
    local T = StorageMonitor.getText
    local alerts = {}
    local function add(key, text)
        table.insert(alerts, {key = key, text = text})
    end
    local panel = snapshot.panel
    local kind = target.kind
    if panel == nil and snapshot.capacity > 0 and kind ~= "finance" and kind ~= "beehive" then
        local pct = StorageMonitor.percent(snapshot.used, snapshot.capacity)
        if pct >= 100 then
            add("full", T("storageMonitor_alertFull", "Full"))
        elseif pct >= StorageMonitor.ALERT_FULL then
            add("full", string.format(T("storageMonitor_alertNearlyFull", "Nearly full: %d%%"), pct))
        end
    end
    if kind == "production" or kind == "husbandry" then
        for _, item in ipairs(snapshot.items) do
            if item.missing then
                add("empty_" .. tostring(item.fillType), string.format(T("storageMonitor_alertEmpty", "%s is empty"), tostring(item.title)))
            elseif item.capacity ~= nil and item.capacity > 0 and item.level >= item.capacity * 0.98
                and ((kind == "production" and item.role ~= "in") or StorageMonitor.ANIMAL_OUTPUTS[item.name]) then
                add("itemFull_" .. tostring(item.fillType), string.format(T("storageMonitor_alertItemFull", "%s is full"), tostring(item.title)))
            end
        end
    end
    if panel ~= nil and panel.kind == "production" then
        if panel.noWater then
            add("noWater", T("storageMonitor_alertNoWater", "No water"))
        end
        local missing = false
        for _, item in ipairs(snapshot.items) do
            missing = missing or item.missing
        end
        if not missing then
            for _, line in ipairs(panel.lines) do
                if line.state == "missing" then
                    add("missingInputs", T("storageMonitor_line_missing", "Missing inputs"))
                    break
                end
            end
        end
    elseif panel ~= nil and panel.kind == "husbandry" then
        for _, cond in ipairs(panel.conditions) do
            if (cond.isFood or cond.supply) and cond.ratio < StorageMonitor.ALERT_LOW then
                add("low_" .. cond.title, string.format(T("storageMonitor_alertLow", "Low %s: %d%%"), cond.title, math.floor(cond.ratio * 100 + 0.5)))
            elseif cond.inverted and cond.ratio >= 0.95 then
                add("condFull_" .. cond.title, string.format(T("storageMonitor_alertItemFull", "%s is full"), cond.title))
            end
        end
    elseif panel ~= nil and panel.kind == "objects" then
        local pct = StorageMonitor.percent(panel.count, panel.capacity)
        if panel.capacity > 0 and pct >= StorageMonitor.ALERT_FULL then
            add("full", string.format(T("storageMonitor_alertNearlyFull", "Nearly full: %d%%"), pct))
        end
    elseif panel ~= nil and panel.kind == "beehive" then
        if not panel.spawner then
            add("noSpawner", T("storageMonitor_alertNoSpawner", "No honey pallet spot"))
        elseif panel.palletFull then
            add("palletFull", T("storageMonitor_alertPalletFull", "Honey pallet spot is full"))
        end
    elseif panel ~= nil and panel.kind == "finance" then
        if panel.money < 0 then
            add("overdrawn", T("storageMonitor_alertOverdrawn", "Account overdrawn"))
        end
    end
    return alerts
end

-- a game message for each alert that is new since the last read, on the monitor's own farm only, at most once
-- per storage and alert every ALERT_REPEAT (several monitors at one storage give one message)
function StorageMonitor.announceAlerts(monitor, target, alerts)
    local spec = monitor.spec_storageMonitor
    local known = spec.alertKnown
    local now = {}
    for _, a in ipairs(alerts) do
        now[a.key] = true
    end
    spec.alertKnown = now
    if known == nil or spec.alerts < 3 or g_currentMission == nil or g_currentMission.addIngameNotification == nil then
        return
    end
    local owner = call(monitor, "getOwnerFarmId")
    if owner ~= nil and owner ~= getPlayerFarmId() then
        return
    end
    StorageMonitor.announced = StorageMonitor.announced or {}
    for _, a in ipairs(alerts) do
        if not known[a.key] then
            local id = tostring(target.owner) .. "|" .. a.key
            local last = StorageMonitor.announced[id]
            if last == nil or StorageMonitor.clock - last >= StorageMonitor.ALERT_REPEAT then
                StorageMonitor.announced[id] = StorageMonitor.clock
                local kind = FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or 1
                g_currentMission:addIngameNotification(kind, string.format("%s: %s", tostring(target.title or target.name), a.text))
            end
        end
    end
end

function StorageMonitor:refreshStorageMonitorData()
    local spec = self.spec_storageMonitor
    spec.dataTimer = 0
    if spec.target == nil then
        spec.snapshot = nil
        return
    end
    local ok, snapshot = pcall(StorageMonitor.buildSnapshot, spec.target.sources, spec.target.roles, fillTypeInfo)
    if not ok then
        StorageMonitor.log("Warning: could not read %s: %s", tostring(spec.target.name), tostring(snapshot))
        spec.target = nil
        spec.snapshot = nil
        return
    end
    spec.snapshot = snapshot
    local okPanel, panel = pcall(StorageMonitor.buildPanel, spec.target)
    snapshot.panel = okPanel and panel or nil
    snapshot.countMode = spec.target.kind == "objects"
    snapshot.noPercent = spec.target.kind == "bunker"
    if not okPanel and not spec.loggedPanel then
        spec.loggedPanel = true
        StorageMonitor.log("Warning: could not read %s: %s", tostring(spec.target.name), tostring(panel))
    end

    -- money: the list is the day's finances; no rates, no prices
    if snapshot.panel ~= nil and snapshot.panel.kind == "finance" then
        snapshot.finance = true
        snapshot.count = #snapshot.panel.lines
    else
        -- rates and time left from the levels over the last in-game hours
        local food = snapshot.panel ~= nil and snapshot.panel.food or nil
        StorageMonitor.updateRates(spec.history, snapshot, StorageMonitor.gameHours(), spec.target.owner, food)
        if snapshot.panel ~= nil and snapshot.panel.kind == "husbandry" and snapshot.panel.food ~= nil then
            local perHour = snapshot.panel.foodPerHour
            if perHour == nil and snapshot.foodRate ~= nil and snapshot.foodRate < -1 then
                perHour = -snapshot.foodRate
            end
            if perHour ~= nil and perHour > 0 then
                snapshot.panel.foodHours = snapshot.panel.food / perHour
            end
        end
        -- prices: the price board, and the value of the stock
        if spec.mode == StorageMonitor.MODE_PRICES and snapshot.count > 0 then
            local okPrices, err = pcall(StorageMonitor.addPrices, snapshot)
            snapshot.prices = okPrices
            if not okPrices and not spec.loggedPrices then
                spec.loggedPrices = true
                StorageMonitor.log("Warning: could not read prices: %s", tostring(err))
            end
        end
    end

    -- alerts
    if spec.alerts > 1 then
        local okAlerts, alerts = pcall(StorageMonitor.computeAlerts, spec.target, snapshot)
        spec.alertList = okAlerts and alerts or {}
        pcall(StorageMonitor.announceAlerts, self, spec.target, spec.alertList)
    else
        spec.alertList = {}
        spec.alertKnown = nil
    end
    spec.layout = StorageMonitor.computeListLayout(snapshot.count)
    spec.rowCache = {}          -- shortened titles are measured again on the next frame
    if spec.page > spec.layout.pages then
        spec.page = 1
    end
end

-- next (+1) or previous (-1) page; stops the pages turning by themselves for a while
function StorageMonitor:scrollStorageMonitor(direction)
    local spec = self.spec_storageMonitor
    local pages = spec.layout.pages
    spec.page = ((spec.page - 1 + direction) % pages) + 1
    spec.pageTime = 0
    spec.manualTime = StorageMonitor.MANUAL_PAUSE
end

-- ---------------------------------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------------------------------

-- the way the camera looks (unit vector), or nil
function StorageMonitor.getCameraForward()
    local camera = getCamera ~= nil and getCamera() or nil
    if (camera == nil or camera == 0) and g_cameraManager ~= nil and g_cameraManager.getActiveCamera ~= nil then
        camera = g_cameraManager:getActiveCamera()
    end
    if camera == nil or camera == 0 or localDirectionToWorld == nil then
        return nil
    end
    local x, y, z = localDirectionToWorld(camera, 0, 0, -1)
    local l = math.sqrt(x * x + y * y + z * z)
    if l < 1e-6 then
        return nil
    end
    return x / l, y / l, z / l
end

local function getCameraPosition()
    local camera = nil
    if getCamera ~= nil then
        camera = getCamera()
    end
    if (camera == nil or camera == 0) and g_cameraManager ~= nil and g_cameraManager.getActiveCamera ~= nil then
        camera = g_cameraManager:getActiveCamera()
    end
    if camera ~= nil and camera ~= 0 then
        return getWorldTranslation(camera)
    end
    if g_localPlayer ~= nil and g_localPlayer.rootNode ~= nil then
        return getWorldTranslation(g_localPlayer.rootNode)
    end
    return nil
end

-- world frame of a screen face (the front one by default); placeables do not move once placed, so it is read
-- once
function StorageMonitor:getScreenFrame(face)
    local spec = self.spec_storageMonitor
    face = face or (spec.faces ~= nil and spec.faces[1]) or spec
    if face.frame == nil then
        local node = face.screenNode
        local function unit(x, y, z)
            local l = math.sqrt(x * x + y * y + z * z)
            if l < 1e-6 then
                return x, y, z
            end
            return x / l, y / l, z / l
        end
        local ox, oy, oz = getWorldTranslation(node)
        local xx, xy, xz = unit(localDirectionToWorld(node, 1, 0, 0))
        local yx, yy, yz = unit(localDirectionToWorld(node, 0, 1, 0))
        local zx, zy, zz = unit(localDirectionToWorld(node, 0, 0, 1))
        local rx, ry, rz = getWorldRotation(node)
        -- scale: screen height in the world (text); localScale: in the screen node's own space (bars, which
        -- are children of the screen node and so already resized with a silo mount)
        face.frame = {o = {ox, oy, oz}, ex = {xx, xy, xz}, ey = {yx, yy, yz}, ez = {zx, zy, zz}, rot = {rx, ry, rz},
                      scale = spec.height * (spec.sizeScale or 1), localScale = spec.height}
    end
    return face.frame
end

-- design units -> world
local function toWorld(f, u, v, dz)
    local lx = (u - StorageMonitor.DESIGN_W * 0.5) * f.scale
    local ly = (0.5 - v) * f.scale
    return f.o[1] + f.ex[1] * lx + f.ey[1] * ly + f.ez[1] * dz,
           f.o[2] + f.ex[2] * lx + f.ey[2] * ly + f.ez[2] * dz,
           f.o[3] + f.ex[3] * lx + f.ey[3] * ly + f.ez[3] * dz
end

-- Bars are real glowing rectangles: copies of the model's hidden "barTemplate" (glowShader, staticLight),
-- each placed, sized and coloured by the script. The game does not draw debug triangles in normal play.
-- A frame fills slots from 1; endBars hides the slots not used this frame.
local barSpec = nil     -- the monitor being drawn
local barFace = nil     -- the screen face being drawn (its templates, bars and icons)
local currentTheme = StorageMonitor.THEMES[1]     -- the theme being drawn

function StorageMonitor.beginBars(spec, face)
    barSpec = spec
    barFace = face or (spec.faces ~= nil and spec.faces[1]) or spec
    barFace.barUsed = 0
    barFace.iconUsed = 0
end

function StorageMonitor.endBars(spec, face)
    face = face or barFace or (spec.faces ~= nil and spec.faces[1]) or spec
    for _, pool in ipairs({{face.bars, face.barUsed}, {face.icons, face.iconUsed}}) do
        for k = (pool[2] or 0) + 1, #(pool[1] or {}) do
            local slot = pool[1][k]
            if slot.visible then
                setVisibility(slot.node, false)
                slot.visible = false
            end
        end
    end
    barSpec = nil
    barFace = nil
end

local function rect(f, u0, v0, u1, v1, c, brightness)
    local face = barFace
    if face == nil or face.barTemplate == nil or u1 - u0 <= 0.0005 or v1 - v0 <= 0.0005 then
        return
    end
    face.bars = face.bars or {}
    face.barUsed = (face.barUsed or 0) + 1
    local slot = face.bars[face.barUsed]
    if slot == nil then
        local node = clone(face.barTemplate, false, false, false)
        link(getParent(face.barTemplate), node)
        slot = {node = node, visible = false}
        face.bars[face.barUsed] = slot
    end
    StorageMonitor.placeSlot(f, slot, u0, v0, u1, v1, c, brightness)
end

-- places a copy of the template at u0..u1 x v0..v1 (design units) with the glow colour c
function StorageMonitor.placeSlot(f, slot, u0, v0, u1, v1, c, brightness)
    local h = f.localScale or f.scale
    local x, y = (u0 - StorageMonitor.DESIGN_W * 0.5) * h, (0.5 - v0) * h
    local w, ht = (u1 - u0) * h, (v1 - v0) * h
    if slot.x ~= x or slot.y ~= y or slot.w ~= w or slot.h ~= ht then
        setTranslation(slot.node, x, y, StorageMonitor.OFFSET_BAR)
        setScale(slot.node, w, ht, 1)
        slot.x, slot.y, slot.w, slot.h = x, y, w, ht
    end
    local k = (brightness or 1) * StorageMonitor.BAR_GLOW * StorageMonitor.brightnessFactor(barSpec)
    local r, g, b = c[1] * k, c[2] * k, c[3] * k
    if slot.r ~= r or slot.g ~= g or slot.b ~= b then
        setShaderParameter(slot.node, "emitColor", r, g, b, 1, false)
        slot.r, slot.g, slot.b = r, g, b
    end
    if not slot.visible then
        setVisibility(slot.node, true)
        slot.visible = true
    end
end

-- The product's own icon (its HUD image, as the game's menus show it) on a copy of the icon template,
-- glowing in colour c; the same way DashboardLive puts fill type icons on vehicle screens. Returns false
-- when there is no icon to show, the caller then draws a coloured square.
local function icon(f, u0, v0, side, path, c)
    local spec = barFace
    if spec == nil or spec.iconTemplate == nil or path == nil or path == "" or getMaterial == nil
        or setMaterialDiffuseMapFromFile == nil then
        return false
    end
    StorageMonitor.iconMaterials = StorageMonitor.iconMaterials or {}
    local material = StorageMonitor.iconMaterials[path]
    if material == nil then
        if StorageMonitor.iconBaseMaterial == nil then
            StorageMonitor.iconBaseMaterial = getMaterial(spec.iconTemplate, 0)
        end
        local ok, result = pcall(setMaterialDiffuseMapFromFile, StorageMonitor.iconBaseMaterial, path, true, true, false)
        material = (ok and result ~= nil and result ~= 0) and result or false
        if not material then
            StorageMonitor.log("Warning: icon %s not loaded", tostring(path))
        end
        StorageMonitor.iconMaterials[path] = material
    end
    if not material then
        return false
    end
    spec.icons = spec.icons or {}
    spec.iconUsed = (spec.iconUsed or 0) + 1
    local slot = spec.icons[spec.iconUsed]
    if slot == nil then
        local node = clone(spec.iconTemplate, false, false, false)
        link(getParent(spec.iconTemplate), node)
        slot = {node = node, visible = false}
        spec.icons[spec.iconUsed] = slot
    end
    if slot.material ~= material then
        setMaterial(slot.node, material, 0)
        slot.material = material
    end
    StorageMonitor.placeSlot(f, slot, u0, v0, u0 + side, v0 + side, c)
    return true
end

-- icon colour: the product's colour, or the text colour on a light screen
local function iconColor(item)
    if currentTheme ~= nil and currentTheme.monoPercent then
        return COLORS.text
    end
    return item.color
end

local textScale = 1      -- dims the text with the brightness setting (text is unlit: never brighter than 1)

local function text(f, u, v, size, str, c, align, bold)
    local x, y, z = toWorld(f, u, v, StorageMonitor.OFFSET_TEXT)
    setTextColor(c[1] * textScale, c[2] * textScale, c[3] * textScale, c[4] or 1)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    setTextBold(bold == true)
    renderText3D(x, y, z, f.rot[1], f.rot[2], f.rot[3], size * f.scale, str)
end

local function textWidth(f, size, str, bold)
    setTextBold(bold == true)
    return getText3DWidth(size * f.scale, str) / f.scale
end

-- shortens str with ".." until it fits maxWidth design units
local function fitText(f, str, size, maxWidth, bold)
    if maxWidth <= 0 then
        return ""
    end
    if textWidth(f, size, str, bold) <= maxWidth then
        return str
    end
    local len = utf8Strlen ~= nil and utf8Strlen(str) or #str
    while len > 1 do
        len = len - 1
        local short = (utf8Substr ~= nil and utf8Substr(str, 0, len) or string.sub(str, 1, len)) .. ".."
        if textWidth(f, size, short, bold) <= maxWidth then
            return short
        end
    end
    return ""
end

local function percentColor(item)
    if currentTheme.monoPercent then
        return COLORS.text
    end
    return item.color
end

local function roleTag(role)
    if role == "in" then
        return "IN", COLORS.input
    elseif role == "inout" then
        return "IN/OUT", COLORS.output
    end
    return "OUT", COLORS.output
end

local function itemFraction(item, snapshot)
    local fraction = 0
    if item.capacity ~= nil and item.capacity > 0 then
        fraction = item.level / item.capacity
    elseif snapshot.used > 0 then
        fraction = item.level / snapshot.used
    end
    return math.max(0, math.min(1, fraction))
end

local function itemPercent(item, snapshot)
    if item.capacity ~= nil and item.capacity > 0 then
        return item.percent
    end
    return StorageMonitor.percent(item.level, snapshot.used)
end

local function percentText(item, snapshot)
    if snapshot.countMode and item.count ~= nil then
        return string.format("%dx", item.count)
    end
    if snapshot.noPercent then         -- a bunker silo has no capacity
        return ""
    end
    return string.format("%d%%", itemPercent(item, snapshot))
end


-- one column, big rows: swatch, name, IN/OUT, fill bar, amount, percent
function StorageMonitor:drawWideList(f, snapshot, layout, first)
    local spec = self.spec_storageMonitor
    local L = LAYOUT
    local size = layout.size
    local headSize = math.min(0.028, size * 0.75)
    text(f, 0.070, L.listHeadV, headSize, StorageMonitor.getText("storageMonitor_colProduct", "PRODUCT"), COLORS.dim, RenderText.ALIGN_LEFT, true)
    text(f, L.rowBarU[1], L.listHeadV, headSize, StorageMonitor.getText("storageMonitor_colLevel", "FILL"), COLORS.dim, RenderText.ALIGN_LEFT, true)
    text(f, 1.385, L.listHeadV, headSize, StorageMonitor.getText("storageMonitor_colAmount", "AMOUNT"), COLORS.dim, RenderText.ALIGN_RIGHT, true)
    text(f, 1.535, L.listHeadV, headSize, "%", COLORS.dim, RenderText.ALIGN_RIGHT, true)
    -- a rate per product (litres per in-game hour) when any of them changes: the bar gets shorter for it
    local withRates = false
    for row = 1, layout.rows do
        local item = snapshot.items[first + row]
        if item ~= nil and item.rate ~= nil and math.abs(item.rate) >= 1 then
            withRates = true
        end
    end
    local barRight = withRates and 1.050 or L.rowBarU[2]

    for row = 1, layout.rows do
        local item = snapshot.items[first + row]
        if item == nil then
            break
        end
        local vc = L.listTopV + layout.rowH * (row - 0.5)
        local baseline = vc + size * 0.36
        local half = size * 0.36
        local side = size * 0.95
        if not icon(f, 0.066, vc - side * 0.5, side, item.icon, iconColor(item)) then
            rect(f, 0.070, vc - half, 0.070 + half * 2, vc + half, item.color)
        end

        local cached = spec.rowCache[item.fillType]
        if cached == nil then
            cached = {title = fitText(f, tostring(item.title), size, item.role ~= nil and 0.43 or 0.55, false)}
            spec.rowCache[item.fillType] = cached
        end
        text(f, 0.120, baseline, size, cached.title, COLORS.text, RenderText.ALIGN_LEFT, false)
        if item.role ~= nil then
            local tag, color = roleTag(item.role)
            text(f, 0.675, vc + size * 0.25, size * 0.65, tag, color, RenderText.ALIGN_RIGHT, true)
        end

        local u0, u1 = L.rowBarU[1], barRight
        local h = math.min(L.rowBarHalfH, layout.rowH * 0.18)
        local fraction = itemFraction(item, snapshot)
        local split = u0
        if fraction > 0 then
            split = math.min(u1, u0 + math.max(0.004, (u1 - u0) * fraction))
            rect(f, u0, vc - h, split, vc + h, item.color)
        end
        rect(f, split, vc - h, u1, vc + h, COLORS.track)     -- side by side, never on top: no flicker
        if item.rate ~= nil and math.abs(item.rate) >= 1 then
            local sign = item.rate > 0 and "+" or ""
            text(f, L.rowBarU[2], vc + size * 0.25, size * 0.7, sign .. StorageMonitor.shortNumber(item.rate) .. "/h",
                item.rate > 0 and COLORS.ok or COLORS.warn, RenderText.ALIGN_RIGHT, true)
        end
        text(f, 1.385, baseline, size, StorageMonitor.formatVolume(item.level), item.missing and COLORS.full or COLORS.text, RenderText.ALIGN_RIGHT, false)
        text(f, 1.535, baseline, size * 0.92, percentText(item, snapshot), percentColor(item), RenderText.ALIGN_RIGHT, true)
    end
end

-- 2 or 3 columns, compact rows: swatch, name, amount, percent, with a thin fill bar underneath
function StorageMonitor:drawColumnList(f, snapshot, layout, first)
    local spec = self.spec_storageMonitor
    local L = LAYOUT
    local size = layout.size
    local headSize = math.min(0.026, size * 0.85)
    local pctW = size * 2.3
    local top, bottom = L.listTopV, L.listBottomV

    for c = 1, layout.cols do
        local x0, x1 = StorageMonitor.columnBounds(layout, c)
        local amountRight = x1 - pctW - size * 0.4
        text(f, x0, L.listHeadV, headSize, StorageMonitor.getText("storageMonitor_colProduct", "PRODUCT"), COLORS.dim, RenderText.ALIGN_LEFT, true)
        text(f, amountRight, L.listHeadV, headSize, StorageMonitor.getText("storageMonitor_colAmount", "AMOUNT"), COLORS.dim, RenderText.ALIGN_RIGHT, true)
        text(f, x1, L.listHeadV, headSize, "%", COLORS.dim, RenderText.ALIGN_RIGHT, true)
        if c < layout.cols then
            local sx = x1 + L.colGap * 0.5
            rect(f, sx - 0.0015, top - 0.035, sx + 0.0015, bottom, COLORS.track)
        end

        for row = 1, layout.rows do
            local item = snapshot.items[first + (c - 1) * layout.rows + row]
            if item == nil then
                break
            end
            local vc = top + layout.rowH * (row - 0.5)
            local baseline = vc + size * 0.22
            local sw = size * 0.62
            if icon(f, x0 - size * 0.12, baseline - size * 0.82, size * 0.92, item.icon, iconColor(item)) then
                sw = size * 0.72
            else
                rect(f, x0, baseline - sw, x0 + sw, baseline, item.color)
            end
            if item.role ~= nil then
                local _, color = roleTag(item.role)
                rect(f, x0 - 0.011, vc - layout.rowH * 0.38, x0 - 0.005, vc + layout.rowH * 0.38, color)
            end

            local nameX = x0 + sw + size * 0.45
            local amount = StorageMonitor.formatVolume(item.level)
            local cached = spec.rowCache[item.fillType]
            if cached == nil or cached.amount ~= amount then
                local maxW = amountRight - textWidth(f, size, amount, false) - size * 0.6 - nameX
                cached = {title = fitText(f, tostring(item.title), size, maxW, false), amount = amount}
                spec.rowCache[item.fillType] = cached
            end
            text(f, nameX, baseline, size, cached.title, COLORS.text, RenderText.ALIGN_LEFT, false)
            text(f, amountRight, baseline, size, amount, item.missing and COLORS.full or COLORS.text, RenderText.ALIGN_RIGHT, false)
            text(f, x1, baseline, size * 0.92, percentText(item, snapshot), percentColor(item), RenderText.ALIGN_RIGHT, true)

            local b0 = vc + size * 0.55
            local b1 = b0 + math.max(0.003, layout.rowH * 0.09)
            local fraction = itemFraction(item, snapshot)
            local split = nameX
            if fraction > 0 then
                split = math.min(x1, nameX + math.max(0.003, (x1 - nameX) * fraction))
                rect(f, nameX, b0, split, b1, item.color)
            end
            rect(f, split, b0, x1, b1, COLORS.track)
        end
    end
end

-- a bar for a 0..1 ratio: the filled part and the rest side by side (never on top: flicker)
local function ratioBarRow(f, u0, v0, u1, v1, ratio, color)
    local split = u0 + (u1 - u0) * math.max(0, math.min(1, ratio))
    if split - u0 > 0.002 then
        rect(f, u0, v0, split, v1, color)
    end
    rect(f, split, v0, u1, v1, COLORS.track)
end

function StorageMonitor:drawStorageMonitor(face)
    local spec = self.spec_storageMonitor
    currentTheme = StorageMonitor.applyTheme(spec.theme or 1)
    textScale = math.max(0.45, math.min(1, 0.45 + 0.55 * StorageMonitor.brightnessFactor(spec)))
    local f = StorageMonitor.getScreenFrame(self, face)
    local L = LAYOUT
    local snapshot = spec.snapshot

    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)

    -- header: name of the storage and the in-game time
    local title
    if spec.title ~= nil and spec.title ~= "" then
        title = spec.title
    elseif spec.target ~= nil then
        title = spec.target.title
    else
        title = StorageMonitor.getText("storageMonitor_searching", "Searching for a storage...")
    end
    if spec.headerTitle == nil or spec.headerSource ~= title then
        spec.headerTitle = fitText(f, string.upper(title), 0.050, 1.20, true)
        spec.headerSource = title
    end
    text(f, 0.050, 0.070, 0.050, spec.headerTitle, COLORS.headText, RenderText.ALIGN_LEFT, true)

    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil and env.currentHour ~= nil then
        local clock = string.format("%02d:%02d", env.currentHour, env.currentMinute or 0)
        text(f, 1.550, 0.070, 0.045, clock, COLORS.headAccent, RenderText.ALIGN_RIGHT, true)
    end

    if snapshot == nil then
        local msg = spec.target == nil and StorageMonitor.getText("storageMonitor_noStorage", "No storage nearby")
            or StorageMonitor.getText("storageMonitor_reading", "Reading...")
        text(f, 0.800, 0.560, 0.060, msg, COLORS.dim, RenderText.ALIGN_CENTER, true)
        StorageMonitor.resetTextState(self)
        return
    end

    -- top panel: the value of the stock (price board); production lines, animals, bunkers, sheds, beehives,
    -- money; or the capacity of a silo
    if snapshot.prices then
        StorageMonitor.drawPricePanel(self, f, snapshot)
    elseif snapshot.panel ~= nil then
        StorageMonitor.drawKindPanel(self, f, snapshot)
    else
        StorageMonitor.drawCapacityPanel(self, f, snapshot)
    end

    -- product list: everything at once if it fits, else pages
    StorageMonitor.drawList(self, f, snapshot)
    StorageMonitor.drawAlerts(self, f)
    StorageMonitor.resetTextState(self)
end

-- alerts: a blinking red stripe under the header and the alert in the footer (several take turns)
function StorageMonitor:drawAlerts(f)
    local spec = self.spec_storageMonitor
    local alerts = spec.alertList
    if spec.alerts < 2 or alerts == nil or #alerts == 0 then
        return
    end
    if StorageMonitor.clock % 1000 < 650 then
        rect(f, 0.000, 0.108, 1.600, 0.123, COLORS.full)
    end
    local index = math.floor(StorageMonitor.clock / StorageMonitor.ALERT_CYCLE) % #alerts + 1
    local str = "! " .. alerts[index].text
    if #alerts > 1 then
        str = string.format("%s  (%d/%d)", str, index, #alerts)
    end
    local maxW = spec.layout.pages > 1 and 1.05 or 1.22
    text(f, 0.300, 0.973, 0.030, fitText(f, str, 0.030, maxW, true), COLORS.full, RenderText.ALIGN_LEFT, true)
end

-- a label on the left of a panel row and its value on the right
local function panelRow(f, u0, u1, base, label, value, color)
    local labelW = textWidth(f, 0.028, label, true)
    text(f, u0, base, 0.028, label, COLORS.dim, RenderText.ALIGN_LEFT, true)
    text(f, u1, base, 0.032, fitText(f, value, 0.032, u1 - u0 - labelW - 0.03, true), color or COLORS.text, RenderText.ALIGN_RIGHT, true)
end

-- a big number on the left of the top panel, as large as fits
local function bigNumber(f, str, color, maxSize)
    local size = maxSize or 0.125
    local w = textWidth(f, size, str, true)
    if w > 0.30 then
        size = size * 0.30 / w
    end
    text(f, 0.070, 0.318 - (0.125 - size) * 0.35, size, str, color, RenderText.ALIGN_LEFT, true)
end

local function trendText(trend)
    if trend == nil then
        return "", COLORS.dim
    elseif trend >= 0.5 then
        return string.format("+%d%%", math.floor(trend + 0.5)), COLORS.ok
    elseif trend <= -0.5 then
        return string.format("-%d%%", math.floor(-trend + 0.5)), COLORS.full
    end
    return "0%", COLORS.dim
end

-- price board: what the stock is worth at the best prices, the most valuable product and the best market
function StorageMonitor:drawPricePanel(f, snapshot)
    local T = StorageMonitor.getText
    text(f, 0.070, 0.185, 0.032, T("storageMonitor_stockValue", "STOCK VALUE"), COLORS.dim, RenderText.ALIGN_LEFT, true)
    bigNumber(f, StorageMonitor.formatMoney(snapshot.value or 0), COLORS.ok, 0.080)
    local x0, x1 = 0.420, 1.530
    local top = snapshot.topItem
    panelRow(f, x0, x1, 0.200, T("storageMonitor_mostValuable", "MOST VALUABLE"),
        top ~= nil and string.format("%s  %s", tostring(top.title), StorageMonitor.formatMoney(top.value)) or "--", COLORS.text)
    panelRow(f, x0, x1, 0.272, T("storageMonitor_bestMarket", "BEST MARKET"),
        snapshot.topStation ~= nil and tostring(snapshot.topStation) or "--", COLORS.accent)
    local trend = string.format(T("storageMonitor_trendCount", "%d rising  %d falling"), snapshot.rising or 0, snapshot.falling or 0)
    panelRow(f, x0, x1, 0.344, T("storageMonitor_nextMonth", "NEXT MONTH"), trend,
        (snapshot.rising or 0) >= (snapshot.falling or 0) and COLORS.ok or COLORS.warn)
end

-- price board rows: product, best price and where, the trend to next month, what it is worth
function StorageMonitor:drawPriceList(f, snapshot, layout, first)
    local spec = self.spec_storageMonitor
    local T = StorageMonitor.getText
    local L = LAYOUT
    local size = layout.size
    if layout.cols == 1 then
        local headSize = math.min(0.026, size * 0.75)
        text(f, 0.070, L.listHeadV, headSize, T("storageMonitor_colProduct", "PRODUCT"), COLORS.dim, RenderText.ALIGN_LEFT, true)
        text(f, 0.520, L.listHeadV, headSize, T("storageMonitor_colBestAt", "BEST PRICE AT"), COLORS.dim, RenderText.ALIGN_LEFT, true)
        text(f, 1.150, L.listHeadV, headSize, T("storageMonitor_colPrice", "PER 1000 L"), COLORS.dim, RenderText.ALIGN_RIGHT, true)
        text(f, 1.300, L.listHeadV, headSize, T("storageMonitor_colTrend", "TREND"), COLORS.dim, RenderText.ALIGN_RIGHT, true)
        text(f, 1.535, L.listHeadV, headSize, T("storageMonitor_colValue", "VALUE"), COLORS.dim, RenderText.ALIGN_RIGHT, true)
        for row = 1, layout.rows do
            local item = snapshot.items[first + row]
            if item == nil then
                break
            end
            local vc = L.listTopV + layout.rowH * (row - 0.5)
            local baseline = vc + size * 0.36
            local side = size * 0.95
            if not icon(f, 0.066, vc - side * 0.5, side, item.icon, iconColor(item)) then
                rect(f, 0.070, vc - size * 0.36, 0.070 + size * 0.72, vc + size * 0.36, item.color)
            end
            local rowKey = "price" .. tostring(item.fillType)
            local cached = spec.rowCache[rowKey]
            local station = item.station or T("storageMonitor_notSold", "nobody buys it")
            if cached == nil or cached.station ~= station then
                cached = {title = fitText(f, tostring(item.title), size, 0.38, false), station = station,
                          stationText = fitText(f, station, size * 0.85, 0.40, false)}
                spec.rowCache[rowKey] = cached
            end
            text(f, 0.120, baseline, size, cached.title, COLORS.text, RenderText.ALIGN_LEFT, false)
            text(f, 0.520, baseline, size * 0.85, cached.stationText, item.station ~= nil and COLORS.accent or COLORS.dim, RenderText.ALIGN_LEFT, false)
            text(f, 1.150, baseline, size, item.price ~= nil and StorageMonitor.formatMoney(item.price * 1000) or "--", COLORS.text, RenderText.ALIGN_RIGHT, false)
            local tr, tc = trendText(item.trend)
            text(f, 1.300, baseline, size * 0.9, tr, tc, RenderText.ALIGN_RIGHT, true)
            text(f, 1.535, baseline, size * 0.92, item.price ~= nil and StorageMonitor.formatMoney(item.value) or "--",
                item.price ~= nil and percentColor(item) or COLORS.dim, RenderText.ALIGN_RIGHT, true)
        end
        return
    end
    -- 2 or 3 columns: product, price per 1000 l, trend
    local headSize = math.min(0.026, size * 0.85)
    local trendW = size * 2.6
    for c = 1, layout.cols do
        local x0, x1 = StorageMonitor.columnBounds(layout, c)
        local priceRight = x1 - trendW
        text(f, x0, L.listHeadV, headSize, T("storageMonitor_colProduct", "PRODUCT"), COLORS.dim, RenderText.ALIGN_LEFT, true)
        text(f, priceRight, L.listHeadV, headSize, T("storageMonitor_colPrice", "PER 1000 L"), COLORS.dim, RenderText.ALIGN_RIGHT, true)
        if c < layout.cols then
            local sx = x1 + L.colGap * 0.5
            rect(f, sx - 0.0015, L.listTopV - 0.035, sx + 0.0015, L.listBottomV, COLORS.track)
        end
        for row = 1, layout.rows do
            local item = snapshot.items[first + (c - 1) * layout.rows + row]
            if item == nil then
                break
            end
            local vc = L.listTopV + layout.rowH * (row - 0.5)
            local baseline = vc + size * 0.22
            local sw = size * 0.62
            if icon(f, x0 - size * 0.12, baseline - size * 0.82, size * 0.92, item.icon, iconColor(item)) then
                sw = size * 0.72
            else
                rect(f, x0, baseline - sw, x0 + sw, baseline, item.color)
            end
            local nameX = x0 + sw + size * 0.45
            local price = item.price ~= nil and StorageMonitor.formatMoney(item.price * 1000) or "--"
            local rowKey = "price" .. tostring(item.fillType)
            local cached = spec.rowCache[rowKey]
            if cached == nil or cached.price ~= price then
                cached = {title = fitText(f, tostring(item.title), size, priceRight - textWidth(f, size, price, false) - size * 0.6 - nameX, false),
                          price = price}
                spec.rowCache[rowKey] = cached
            end
            text(f, nameX, baseline, size, cached.title, COLORS.text, RenderText.ALIGN_LEFT, false)
            text(f, priceRight, baseline, size, price, item.price ~= nil and COLORS.text or COLORS.dim, RenderText.ALIGN_RIGHT, false)
            local tr, tc = trendText(item.trend)
            text(f, x1, baseline, size * 0.92, tr, tc, RenderText.ALIGN_RIGHT, true)
        end
    end
end

-- money: today's income and costs by category
function StorageMonitor:drawFinanceList(f, snapshot, layout, first)
    local spec = self.spec_storageMonitor
    local T = StorageMonitor.getText
    local L = LAYOUT
    local size = layout.size
    local lines = snapshot.panel.lines
    local biggest = 1
    for _, line in ipairs(lines) do
        biggest = math.max(biggest, math.abs(line.value))
    end
    local headSize = math.min(0.026, size * 0.85)
    for c = 1, layout.cols do
        local x0, x1 = StorageMonitor.columnBounds(layout, c)
        text(f, x0, L.listHeadV, headSize, T("storageMonitor_colToday", "TODAY"), COLORS.dim, RenderText.ALIGN_LEFT, true)
        text(f, x1, L.listHeadV, headSize, T("storageMonitor_colAmountMoney", "AMOUNT"), COLORS.dim, RenderText.ALIGN_RIGHT, true)
        if c < layout.cols then
            local sx = x1 + L.colGap * 0.5
            rect(f, sx - 0.0015, L.listTopV - 0.035, sx + 0.0015, L.listBottomV, COLORS.track)
        end
        for row = 1, layout.rows do
            local line = lines[first + (c - 1) * layout.rows + row]
            if line == nil then
                break
            end
            local vc = L.listTopV + layout.rowH * (row - 0.5)
            local baseline = vc + size * (layout.cols == 1 and 0.36 or 0.22)
            local color = line.value >= 0 and COLORS.ok or COLORS.full
            local amount = (line.value >= 0 and "+" or "") .. StorageMonitor.formatMoney(line.value)
            local rowKey = "fin" .. line.name
            local cached = spec.rowCache[rowKey]
            local barU0 = layout.cols == 1 and 0.700 or x0
            if cached == nil or cached.amount ~= amount then
                local maxW = (layout.cols == 1 and barU0 - 0.03 or x1 - textWidth(f, size, amount, true) - size * 0.6) - x0
                cached = {title = fitText(f, tostring(line.title), size, maxW, false), amount = amount}
                spec.rowCache[rowKey] = cached
            end
            text(f, x0, baseline, size, cached.title, COLORS.text, RenderText.ALIGN_LEFT, false)
            text(f, x1, baseline, size, amount, color, RenderText.ALIGN_RIGHT, true)
            -- a bar for the size of the amount: in the row (one column) or under it
            local fraction = math.abs(line.value) / biggest
            if layout.cols == 1 then
                local h = math.min(L.rowBarHalfH, layout.rowH * 0.18)
                ratioBarRow(f, barU0, vc - h, 1.170, vc + h, fraction, color)
            else
                local b0 = vc + size * 0.55
                ratioBarRow(f, x0, b0, x1, b0 + math.max(0.003, layout.rowH * 0.09), fraction, color)
            end
        end
    end
end

function StorageMonitor:drawCapacityPanel(f, snapshot)
    local L = LAYOUT
    local usedPct = StorageMonitor.percent(snapshot.used, snapshot.capacity)
    local levelColor = StorageMonitor.levelColor(usedPct)
    text(f, 0.070, 0.185, 0.032, StorageMonitor.getText("storageMonitor_capacity", "CAPACITY"), COLORS.dim, RenderText.ALIGN_LEFT, true)
    if snapshot.capacity > 0 then
        text(f, 0.070, 0.318, 0.125, string.format("%d%%", usedPct), levelColor, RenderText.ALIGN_LEFT, true)
    else
        text(f, 0.070, 0.318, 0.125, "--", COLORS.dim, RenderText.ALIGN_LEFT, true)
    end

    local sb = L.stackBar
    text(f, sb[1], sb[2] - 0.022, 0.040,
        StorageMonitor.getText("storageMonitor_used", "USED") .. "  " .. StorageMonitor.formatVolume(snapshot.used),
        COLORS.text, RenderText.ALIGN_LEFT, true)
    if snapshot.capacity > 0 then
        text(f, sb[3], sb[2] - 0.022, 0.040,
            StorageMonitor.getText("storageMonitor_total", "TOTAL") .. "  " .. StorageMonitor.formatVolume(snapshot.capacity),
            COLORS.dim, RenderText.ALIGN_RIGHT, false)
    end

    -- stacked bar: every product in its colour, then the free space; the pieces sit side by side (never on
    -- top of each other, which flickers)
    local u = sb[1]
    if snapshot.used > 0 then
        local reference = math.max(snapshot.capacity, snapshot.used)
        local width = sb[3] - sb[1]
        for _, item in ipairs(snapshot.items) do
            local w = width * item.level / reference
            if w > 0.002 then
                local u1 = math.min(sb[3], u + w)
                rect(f, u, sb[2], u1, sb[4], item.color)
                u = u1
            end
            if u >= sb[3] then
                break
            end
        end
        rect(f, sb[1], sb[4] + 0.004, sb[1] + width * math.min(1, snapshot.used / reference), sb[4] + 0.009, levelColor)
    end
    rect(f, u, sb[2], sb[3], sb[4], COLORS.stackFree)

    if snapshot.capacity > 0 then
        local free = math.max(0, snapshot.capacity - snapshot.used)
        text(f, sb[1], 0.338, 0.034,
            StorageMonitor.getText("storageMonitor_free", "FREE") .. "  " .. StorageMonitor.formatVolume(free),
            COLORS.ok, RenderText.ALIGN_LEFT, false)
    end
    -- how fast it fills or empties and when it is full / empty; else the number of products
    local left, toward = StorageMonitor.hoursLeft(snapshot.used, snapshot.capacity, snapshot.rate)
    if snapshot.rate ~= nil and math.abs(snapshot.rate) >= 1 then
        local str = StorageMonitor.formatRate(snapshot.rate)
        local color = snapshot.rate > 0 and COLORS.accent or COLORS.warn
        if left ~= nil then
            local key = toward == "full" and "storageMonitor_fullIn" or "storageMonitor_emptyIn"
            str = str .. "   " .. string.format(StorageMonitor.getText(key, toward == "full" and "FULL IN %s" or "EMPTY IN %s"),
                StorageMonitor.formatDuration(left))
            if left < 6 then
                color = COLORS.full
            end
        end
        text(f, sb[3], 0.338, 0.034, str, color, RenderText.ALIGN_RIGHT, true)
    else
        text(f, sb[3], 0.338, 0.034,
            string.format(StorageMonitor.getText("storageMonitor_products", "%d PRODUCTS"), snapshot.count),
            COLORS.dim, RenderText.ALIGN_RIGHT, false)
    end
end

local ratioBar = ratioBarRow

-- colour of a condition: full is good, unless inverted (manure: full is bad)
local function conditionColor(ratio, inverted)
    if inverted then           -- a tank that should not run full (manure, slurry)
        return StorageMonitor.levelColor(ratio * 100)
    end
    if ratio < 0.2 then
        return COLORS.full
    elseif ratio < 0.5 then
        return COLORS.warn
    end
    return COLORS.ok
end

local STATE_COLORS = {running = "ok", missing = "warn", full = "full", off = "dim", ready = "ok", fermenting = "warn",
    filling = "accent"}

function StorageMonitor:drawKindPanel(f, snapshot)
    local T = StorageMonitor.getText
    local panel = snapshot.panel
    local x0, x1 = 0.420, 1.530
    local colW = (x1 - x0 - 0.05) / 2
    local rowV = {0.190, 0.262, 0.334}       -- baselines of the panel rows

    local function cell(i)                    -- left edge, right edge, baseline of panel cell i (2 columns)
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2) + 1
        local u0 = x0 + col * (colW + 0.05)
        return u0, u0 + colW, rowV[row]
    end
    local maxCells = StorageMonitor.PANEL_ROWS * 2
    local cache = self.spec_storageMonitor.rowCache
    -- fitted texts are measured once per read of the storage, not every frame
    local function fitted(key, str, size, width, bold)
        local c = cache[key]
        if c == nil or c.source ~= str or math.abs(c.width - width) > 1e-6 then
            c = {source = str, width = width, text = fitText(f, str, size, width, bold)}
            cache[key] = c
        end
        return c.text
    end
    -- a small line under the big number on the left
    local function note(str, color)
        text(f, 0.070, 0.356, 0.022, fitted("note", str, 0.022, 0.30, true), color or COLORS.dim, RenderText.ALIGN_LEFT, true)
    end

    if panel.kind == "production" then
        local n = #panel.lines
        text(f, 0.070, 0.185, 0.032, T("storageMonitor_linesRunning", "RUNNING"), COLORS.dim, RenderText.ALIGN_LEFT, true)
        local color = (n > 0 and panel.running == n) and COLORS.ok or (panel.running > 0 and COLORS.warn or COLORS.full)
        text(f, 0.070, 0.300, 0.090, string.format("%d/%d", panel.running, n), color, RenderText.ALIGN_LEFT, true)
        for i, line in ipairs(panel.lines) do
            if i > maxCells then
                break
            end
            local u0, u1, base = cell(i)
            local c = COLORS[STATE_COLORS[line.state] or "dim"]
            if i == maxCells and n > maxCells then
                text(f, u0, base, 0.030, string.format(T("storageMonitor_more", "+%d more"), n - maxCells + 1), COLORS.dim, RenderText.ALIGN_LEFT, true)
            else
                rect(f, u0, base - 0.024, u0 + 0.016, base - 0.008, c)
                local statusW = textWidth(f, 0.026, line.text, true)
                local name = fitted("line" .. i, line.name, 0.032, u1 - u0 - 0.03 - statusW - 0.02, false)
                text(f, u0 + 0.028, base, 0.032, name, COLORS.text, RenderText.ALIGN_LEFT, false)
                text(f, u1, base, 0.026, line.text, c, RenderText.ALIGN_RIGHT, true)
            end
        end
        -- the input that runs out first, or "no water" in a greenhouse
        local first, firstHours = nil, math.huge
        for _, item in ipairs(snapshot.items) do
            if item.role == "in" or item.role == "inout" then
                local hours, toward = StorageMonitor.hoursLeft(item.level, item.capacity, item.rate)
                if hours ~= nil and toward == "empty" and hours < firstHours then
                    first, firstHours = item, hours
                end
            end
        end
        if panel.noWater then
            note(T("storageMonitor_alertNoWater", "No water"), COLORS.full)
        elseif first ~= nil then
            note(string.format(T("storageMonitor_runsOut", "%s: empty in %s"), tostring(first.title), StorageMonitor.formatDuration(firstHours)),
                firstHours < 6 and COLORS.full or COLORS.warn)
        end
    elseif panel.kind == "husbandry" then
        text(f, 0.070, 0.185, 0.032, T("storageMonitor_animals", "ANIMALS"), COLORS.dim, RenderText.ALIGN_LEFT, true)
        local full = panel.maxAnimals > 0 and panel.animals >= panel.maxAnimals
        text(f, 0.070, 0.300, panel.maxAnimals >= 100 and 0.064 or 0.085,
            string.format("%d/%d", panel.animals, panel.maxAnimals), full and COLORS.warn or COLORS.ok, RenderText.ALIGN_LEFT, true)
        for i, cond in ipairs(panel.conditions) do
            if i > maxCells then
                break
            end
            local u0, u1, base = cell(i)
            local value = cond.valueText or string.format("%d%%", math.floor(cond.ratio * 100 + 0.5))
            local title = fitted("cond" .. i, cond.title, 0.028, u1 - u0 - 0.08, false)
            text(f, u0, base - 0.018, 0.028, title, COLORS.text, RenderText.ALIGN_LEFT, false)
            text(f, u1, base - 0.018, 0.028, value, COLORS.dim, RenderText.ALIGN_RIGHT, true)
            ratioBar(f, u0, base - 0.008, u1, base + 0.006, cond.ratio, conditionColor(cond.ratio, cond.inverted))
        end
        -- how long the food lasts
        if panel.foodHours ~= nil then
            note(string.format(T("storageMonitor_foodFor", "Food for %s"), StorageMonitor.formatDuration(panel.foodHours)),
                panel.foodHours < 12 and COLORS.full or (panel.foodHours < 48 and COLORS.warn or COLORS.ok))
        end
    elseif panel.kind == "beehive" then
        text(f, 0.070, 0.185, 0.032, T("storageMonitor_beehivesCaps", "BEEHIVES"), COLORS.dim, RenderText.ALIGN_LEFT, true)
        bigNumber(f, tostring(panel.hives), COLORS.ok, 0.110)
        local status = panel.active and T("storageMonitor_beesProducing", "Producing") or T("storageMonitor_beesWinter", "Winter break")
        local spot = not panel.spawner and T("storageMonitor_spotNone", "None") or
            (panel.palletFull and T("storageMonitor_spotFull", "Full") or T("storageMonitor_spotOk", "OK"))
        local cells = {
            {T("storageMonitor_honeyPerDay", "Honey per day"), StorageMonitor.formatVolume(panel.honeyPerDay), COLORS.text},
            {T("storageMonitor_beesStatus", "Status"), status, panel.active and COLORS.ok or COLORS.warn},
            {T("storageMonitor_beesFlying", "Bees"), panel.flying and T("storageMonitor_beesOut", "Flying") or T("storageMonitor_beesIn", "Resting"), COLORS.dim},
            {T("storageMonitor_palletSpot", "Pallet spot"), spot, (panel.spawner and not panel.palletFull) and COLORS.ok or COLORS.full},
        }
        if panel.honeyValue ~= nil then
            table.insert(cells, {T("storageMonitor_honeyValue", "Worth per day"), StorageMonitor.formatMoney(panel.honeyValue), COLORS.ok})
        end
        for i, c in ipairs(cells) do
            local u0, u1, base = cell(i)
            text(f, u0, base, 0.028, fitted("bee" .. i, c[1], 0.028, colW * 0.55, false), COLORS.text, RenderText.ALIGN_LEFT, false)
            text(f, u1, base, 0.028, c[2], c[3], RenderText.ALIGN_RIGHT, true)
        end
    elseif panel.kind == "finance" then
        text(f, 0.070, 0.185, 0.032, T("storageMonitor_balance", "BALANCE"), COLORS.dim, RenderText.ALIGN_LEFT, true)
        bigNumber(f, StorageMonitor.formatMoney(panel.money), panel.money >= 0 and COLORS.ok or COLORS.full, 0.080)
        local net = panel.income + panel.expenses
        local cells = {
            {T("storageMonitor_loan", "Loan"), StorageMonitor.formatMoney(panel.loan), panel.loan > 0 and COLORS.warn or COLORS.ok},
            {T("storageMonitor_credit", "Credit left"), panel.loanMax ~= nil and StorageMonitor.formatMoney(math.max(0, panel.loanMax - panel.loan)) or "--", COLORS.text},
            {T("storageMonitor_incomeToday", "Income today"), "+" .. StorageMonitor.formatMoney(panel.income), COLORS.ok},
            {T("storageMonitor_costsToday", "Costs today"), StorageMonitor.formatMoney(panel.expenses), COLORS.full},
            {T("storageMonitor_netToday", "Today"), (net >= 0 and "+" or "") .. StorageMonitor.formatMoney(net), net >= 0 and COLORS.ok or COLORS.full},
        }
        for i, c in ipairs(cells) do
            local u0, u1, base = cell(i)
            local valueW = textWidth(f, 0.028, c[2], true)
            text(f, u0, base, 0.028, fitted("fin" .. i, c[1], 0.028, u1 - u0 - valueW - 0.02, false), COLORS.text, RenderText.ALIGN_LEFT, false)
            text(f, u1, base, 0.028, c[2], c[3], RenderText.ALIGN_RIGHT, true)
        end
    elseif panel.kind == "bunker" then
        local single = #panel.bunkers == 1 and panel.bunkers[1] or nil
        if single ~= nil then
            text(f, 0.070, 0.185, 0.032, string.upper(single.text), COLORS.dim, RenderText.ALIGN_LEFT, true)
            text(f, 0.070, 0.318, 0.125, string.format("%d%%", single.percent), COLORS[STATE_COLORS[single.state]], RenderText.ALIGN_LEFT, true)
            text(f, x0, 0.213, 0.040, T("storageMonitor_bunkerLevel", "IN THE SILO") .. "  " .. StorageMonitor.formatVolume(single.fillLevel),
                COLORS.text, RenderText.ALIGN_LEFT, true)
            ratioBar(f, x0, 0.235, x1, 0.285, single.percent / 100, COLORS[STATE_COLORS[single.state]])
            text(f, x0, 0.338, 0.034, single.text, COLORS[STATE_COLORS[single.state]], RenderText.ALIGN_LEFT, false)
        else
            text(f, 0.070, 0.185, 0.032, T("storageMonitor_bunker_ready", "READY"), COLORS.dim, RenderText.ALIGN_LEFT, true)
            text(f, 0.070, 0.310, 0.100, string.format("%d/%d", panel.ready, #panel.bunkers),
                panel.ready > 0 and COLORS.ok or COLORS.warn, RenderText.ALIGN_LEFT, true)
            for i, b in ipairs(panel.bunkers) do
                if i > maxCells then
                    break
                end
                local u0, u1, base = cell(i)
                local c = COLORS[STATE_COLORS[b.state]]
                text(f, u0, base - 0.018, 0.028, string.format("%d  %s", b.index, b.text), COLORS.text, RenderText.ALIGN_LEFT, false)
                text(f, u1, base - 0.018, 0.028, string.format("%d%%", b.percent), c, RenderText.ALIGN_RIGHT, true)
                ratioBar(f, u0, base - 0.008, u1, base + 0.006, b.percent / 100, c)
            end
        end
    elseif panel.kind == "objects" then
        local pct = StorageMonitor.percent(panel.count, panel.capacity)
        local c = StorageMonitor.levelColor(pct)
        text(f, 0.070, 0.185, 0.032, T("storageMonitor_capacity", "CAPACITY"), COLORS.dim, RenderText.ALIGN_LEFT, true)
        text(f, 0.070, 0.318, 0.125, string.format("%d%%", pct), c, RenderText.ALIGN_LEFT, true)
        text(f, x0, 0.213, 0.040, string.format(T("storageMonitor_objects", "STORED  %d / %d"), panel.count, panel.capacity),
            COLORS.text, RenderText.ALIGN_LEFT, true)
        ratioBar(f, x0, 0.235, x1, 0.285, panel.capacity > 0 and panel.count / panel.capacity or 0, c)
        text(f, x0, 0.338, 0.034, StorageMonitor.getText("storageMonitor_used", "USED") .. "  " .. StorageMonitor.formatVolume(snapshot.used),
            COLORS.dim, RenderText.ALIGN_LEFT, false)
        text(f, x1, 0.338, 0.034, string.format(StorageMonitor.getText("storageMonitor_products", "%d PRODUCTS"), snapshot.count),
            COLORS.dim, RenderText.ALIGN_RIGHT, false)
    end
end

function StorageMonitor:drawList(f, snapshot)
    local spec = self.spec_storageMonitor
    local L = LAYOUT
    local layout = spec.layout
    local first = (spec.page - 1) * layout.perPage
    if snapshot.count == 0 then
        local kind = snapshot.panel ~= nil and snapshot.panel.kind or nil
        local msg = StorageMonitor.getText("storageMonitor_empty", "Empty")
        if kind == "beehive" then
            msg = StorageMonitor.getText("storageMonitor_honeyHint", "Honey goes onto pallets at the pallet spot")
        elseif kind == "finance" then
            msg = StorageMonitor.getText("storageMonitor_noMoneyToday", "No income or costs today yet")
        end
        text(f, 0.800, 0.680, 0.040, fitText(f, msg, 0.040, 1.40, true), COLORS.dim, RenderText.ALIGN_CENTER, true)
    elseif snapshot.finance then
        StorageMonitor.drawFinanceList(self, f, snapshot, layout, first)
    elseif snapshot.prices then
        StorageMonitor.drawPriceList(self, f, snapshot, layout, first)
    elseif layout.cols == 1 then
        StorageMonitor.drawWideList(self, f, snapshot, layout, first)
    else
        StorageMonitor.drawColumnList(self, f, snapshot, layout, first)
    end

    -- page indicator and timer (no timer bar while an alert is in the footer)
    local alerting = spec.alerts > 1 and spec.alertList ~= nil and #spec.alertList > 0
    if layout.pages > 1 and alerting then
        text(f, 1.550, 0.973, 0.028,
            string.format(StorageMonitor.getText("storageMonitor_page", "PAGE %d/%d"), spec.page, layout.pages),
            COLORS.dim, RenderText.ALIGN_RIGHT, true)
    elseif layout.pages > 1 then
        text(f, 1.550, 0.973, 0.028,
            string.format(StorageMonitor.getText("storageMonitor_page", "PAGE %d/%d"), spec.page, layout.pages),
            COLORS.dim, RenderText.ALIGN_RIGHT, true)
        local pb = L.pageBar
        local progress
        if spec.manualTime > 0 then
            progress = 1 - spec.manualTime / StorageMonitor.MANUAL_PAUSE
        else
            progress = math.min(1, spec.pageTime / StorageMonitor.PAGE_TIME)
        end
        local split = pb[1] + (pb[3] - pb[1]) * progress
        rect(f, pb[1], pb[2], split, pb[4], spec.manualTime > 0 and COLORS.warn or COLORS.accent)
        rect(f, split, pb[2], pb[3], pb[4], COLORS.track)
    end

    StorageMonitor.resetTextState(self)
end

function StorageMonitor:resetTextState()
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
end

-- per frame, from the mod event listener below
function StorageMonitor:updateStorageMonitor(dt)
    local spec = self.spec_storageMonitor
    if spec == nil or spec.screenNode == nil then
        return
    end

    local cx, cy, cz = getCameraPosition()
    spec.isNear = false
    if cx == nil then
        return
    end
    local f = StorageMonitor.getScreenFrame(self)
    local dx, dy, dz = cx - f.o[1], cy - f.o[2], cz - f.o[3]
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    spec.distance = distance
    local drawDistance = spec.drawDistance * math.max(1, spec.sizeScale or 1)
    for _, face in ipairs(spec.faces) do
        face.visible = false
    end

    -- nobody near: read the storage now and then (rates, alerts), draw nothing
    if distance > drawDistance then
        spec.scanTimer = spec.scanTimer + dt
        if spec.scanTimer >= StorageMonitor.FAR_SCAN_INTERVAL then      -- also the very first update
            self:rescanStorageMonitor()
        end
        spec.dataTimer = spec.dataTimer + dt
        if spec.dataTimer >= StorageMonitor.FAR_DATA_INTERVAL then
            StorageMonitor.refreshStorageMonitorData(self)
        end
        return
    end

    -- the faces the camera is in front of, and not behind the camera
    local fx, fy, fz = StorageMonitor.getCameraForward()
    local radius = spec.width * (spec.sizeScale or 1) * 0.6 + 1
    for _, face in ipairs(spec.faces) do
        local ff = StorageMonitor.getScreenFrame(self, face)
        local ox, oy, oz = cx - ff.o[1], cy - ff.o[2], cz - ff.o[3]
        local inFront = (ox * ff.ez[1] + oy * ff.ez[2] + oz * ff.ez[3]) > 0.02
        local ahead = fx == nil or (-ox * fx - oy * fy - oz * fz) > -radius
        face.visible = inFront and ahead
        spec.isNear = spec.isNear or face.visible
    end

    spec.scanTimer = spec.scanTimer + dt
    if spec.scanTimer >= StorageMonitor.SCAN_INTERVAL then
        self:rescanStorageMonitor()
    end
    spec.dataTimer = spec.dataTimer + dt
    local interval = StorageMonitor.DATA_INTERVAL
    if not spec.isNear then
        interval = StorageMonitor.FAR_DATA_INTERVAL
    elseif distance > drawDistance * 0.5 then
        interval = StorageMonitor.MID_DATA_INTERVAL
    end
    if spec.dataTimer >= interval then
        StorageMonitor.refreshStorageMonitorData(self)
    end

    if spec.manualTime > 0 then
        spec.manualTime = math.max(0, spec.manualTime - dt)
        return
    end
    spec.pageTime = spec.pageTime + dt
    if spec.pageTime >= StorageMonitor.PAGE_TIME then
        spec.pageTime = 0
        spec.page = (spec.page % spec.layout.pages) + 1
    end
end

-- ---------------------------------------------------------------------------------------------------
-- keys while standing in front of a monitor: page up / down, connected silos on / off
-- ---------------------------------------------------------------------------------------------------

StorageMonitor.actionEvents = {}

function StorageMonitor.registerActionEvents()
    StorageMonitor.actionEvents = {}
    StorageMonitor.actionState = nil
    local function register(actionName, callback)
        local action = InputAction ~= nil and InputAction[actionName] or nil
        if action == nil then
            return
        end
        local _, eventId = g_inputBinding:registerActionEvent(action, StorageMonitor, callback, false, true, false, true, nil, true)
        if eventId ~= nil then
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_HIGH)
            g_inputBinding:setActionEventActive(eventId, false)
            StorageMonitor.actionEvents[actionName] = eventId
        end
    end
    register("STORAGE_MONITOR_PAGE_UP", StorageMonitor.onActionPageUp)
    register("STORAGE_MONITOR_PAGE_DOWN", StorageMonitor.onActionPageDown)
end

function StorageMonitor.onActionPageUp()
    if StorageMonitor.activeMonitor ~= nil then
        StorageMonitor.scrollStorageMonitor(StorageMonitor.activeMonitor, -1)
    end
end

function StorageMonitor.onActionPageDown()
    if StorageMonitor.activeMonitor ~= nil then
        StorageMonitor.scrollStorageMonitor(StorageMonitor.activeMonitor, 1)
    end
end

-- shows the page keys only while the player stands at a monitor that has more than one page
function StorageMonitor.updateActionEvents()
    if g_inputBinding == nil then
        return
    end
    local monitor = StorageMonitor.activeMonitor
    local spec = monitor ~= nil and monitor.spec_storageMonitor or nil
    local paging = spec ~= nil and spec.layout.pages > 1
    if paging == StorageMonitor.actionState then
        return
    end
    StorageMonitor.actionState = paging
    for _, eventId in pairs(StorageMonitor.actionEvents) do
        g_inputBinding:setActionEventActive(eventId, paging)
    end
end

-- ---------------------------------------------------------------------------------------------------
-- settings menu (the activate key in front of the screen): pick the storage, connected silos, height
-- ---------------------------------------------------------------------------------------------------

local function formatDistance(metres)
    return string.format("%d m", math.floor(metres + 0.5))
end

-- the game's option dialog; a second dialog opens one frame later, after the first has closed
function StorageMonitor.showOptions(title, text, options, callback)
    if OptionDialog == nil or OptionDialog.show == nil then
        StorageMonitor.log("Warning: OptionDialog not available")
        return
    end
    StorageMonitor.pendingDialog = {title = title, text = text, options = options, callback = callback}
end

-- the game's text input dialog for a short text; callback(text) only on OK
function StorageMonitor.showTextInput(prompt, default, maxChars, callback)
    if TextInputDialog == nil or TextInputDialog.show == nil then
        StorageMonitor.log("Warning: TextInputDialog not available")
        return
    end
    StorageMonitor.pendingDialog = {kind = "text", text = prompt, default = default, maxChars = maxChars, callback = callback}
end

-- TextInputDialog.show(callback, target, defaultText, dialogPrompt, imePrompt, maxCharacters, confirmText); the
-- callback gets (target, text, clickOk), as Courseplay uses it
function StorageMonitor.openTextDialog(d)
    local okText = g_i18n ~= nil and g_i18n.getText ~= nil and g_i18n:getText("button_ok") or "OK"
    TextInputDialog.show(function(_, text, clickOk)
        if clickOk then
            d.callback(text)
        end
    end, StorageMonitor, d.default or "", d.text, d.text, d.maxChars, okText)
end

function StorageMonitor.openPendingDialog()
    local d = StorageMonitor.pendingDialog
    if d == nil or (g_gui ~= nil and g_gui.getIsDialogVisible ~= nil and g_gui:getIsDialogVisible()) then
        return
    end
    StorageMonitor.pendingDialog = nil
    if d.kind == "text" then
        StorageMonitor.openTextDialog(d)
    else
        OptionDialog.show(d.callback, d.title, d.text, d.options)
    end
end

-- changes one setting of a monitor (the others stay), syncs it and shows the result at once
local function change(monitor, key, value)
    local settings = monitor:getStorageMonitorSettings()
    settings[key] = value
    monitor:setStorageMonitorSettings(settings)
    monitor:rescanStorageMonitor()
    StorageMonitor.refreshStorageMonitorData(monitor)
end

local function mark(isCurrent)
    return isCurrent and "  <" or ""
end

function StorageMonitor.openSettings(monitor)
    local spec = monitor.spec_storageMonitor
    monitor:rescanStorageMonitor()
    local current = spec.target ~= nil and spec.target.name or StorageMonitor.getText("storageMonitor_noStorage", "No storage nearby")
    local T = StorageMonitor.getText

    local entries = {}
    table.insert(entries, {text = string.format(T("storageMonitor_menuPick", "Pick the storage (now: %s)"), current),
        run = function() StorageMonitor.openPick(monitor) end})
    table.insert(entries, {text = spec.connected and T("storageMonitor_menuConnectedOff", "Show only this silo")
        or T("storageMonitor_menuConnectedOn", "Also show the silos connected to it"),
        run = function() change(monitor, "connected", not spec.connected) end})
    if spec.mountNode ~= nil then
        table.insert(entries, {text = string.format(T("storageMonitor_menuSize", "Screen size (now: %.1f m wide)"), spec.mountWidth),
            run = function() StorageMonitor.openSize(monitor) end})
    end
    local level = StorageMonitor.BRIGHTNESS[spec.brightness]
    table.insert(entries, {text = string.format(T("storageMonitor_menuBrightness", "Brightness (now: %s)"), T(level.key, level.fallback)),
        run = function() StorageMonitor.openBrightness(monitor) end})
    local theme = StorageMonitor.THEMES[spec.theme]
    table.insert(entries, {text = string.format(T("storageMonitor_menuTheme", "Colours (now: %s)"), T(theme.key, theme.fallback)),
        run = function() StorageMonitor.openTheme(monitor) end})
    table.insert(entries, {text = spec.title ~= "" and string.format(T("storageMonitor_menuTitleNow", "Title (now: %s)"), spec.title)
        or T("storageMonitor_menuTitleSet", "Title: type your own"),
        run = function() StorageMonitor.openTitle(monitor) end})
    local mode = StorageMonitor.MODES[spec.mode] or StorageMonitor.MODES[1]
    table.insert(entries, {text = string.format(T("storageMonitor_menuMode", "Screen shows (now: %s)"), T(mode.key, mode.fallback)),
        run = function() StorageMonitor.openMode(monitor) end})
    local alerts = StorageMonitor.ALERT_LEVELS[spec.alerts] or StorageMonitor.ALERT_LEVELS[1]
    table.insert(entries, {text = string.format(T("storageMonitor_menuAlerts", "Alerts (now: %s)"), T(alerts.key, alerts.fallback)),
        run = function() StorageMonitor.openAlerts(monitor) end})

    local options = {}
    for _, e in ipairs(entries) do
        table.insert(options, e.text)
    end
    StorageMonitor.showOptions(T("storageMonitor_menuTitle", "Digital DTM"),
        string.format(T("storageMonitor_menuText", "Showing: %s"), current), options,
        function(index)
            local e = entries[index]
            if e ~= nil then
                e.run()
            end
        end)
end

function StorageMonitor.openPick(monitor)
    local spec = monitor.spec_storageMonitor
    local candidates = spec.candidates
    local options = {StorageMonitor.getText("storageMonitor_pickNearest", "Always the nearest") .. mark(spec.pick == nil)}
    for i = 1, math.min(#candidates, StorageMonitor.MAX_PICK) do
        local c = candidates[i]
        local isCurrent = spec.pick ~= nil and spec.target ~= nil and spec.target.owner == c.owner
        local label = c.kind == "farm" and tostring(c.name) or string.format("%s  (%s)", tostring(c.name), formatDistance(c.distance))
        table.insert(options, label .. mark(isCurrent))
    end
    StorageMonitor.showOptions(StorageMonitor.getText("storageMonitor_pickTitle", "Pick the storage"),
        StorageMonitor.getText("storageMonitor_pickText", "Storages near this monitor, nearest first:"), options,
        function(index)
            if index == 1 then
                change(monitor, "pick", nil)
            elseif index ~= nil and index > 1 and candidates[index - 1] ~= nil then
                local c = candidates[index - 1]
                change(monitor, "pick", {c.anchor[1], c.anchor[2]})
            end
        end)
end

function StorageMonitor.openSize(monitor)
    local spec = monitor.spec_storageMonitor
    local widths, options = StorageMonitor.SIZE_WIDTHS, {}
    for _, w in ipairs(widths) do
        table.insert(options, string.format(StorageMonitor.getText("storageMonitor_sizeOption", "%.1f m wide, %.1f m high"),
            w, w / StorageMonitor.DESIGN_W) .. mark(math.abs(w - spec.mountWidth) < 0.01))
    end
    local text = spec.mountMode == "silo" and StorageMonitor.getText("storageMonitor_sizeText", "Size of the screen. It grows upwards from its bottom edge.")
        or StorageMonitor.getText("storageMonitor_sizeTextGround", "Size of the monitor. It grows from the ground.")
    StorageMonitor.showOptions(StorageMonitor.getText("storageMonitor_sizeTitle", "Screen size"), text, options,
        function(index)
            if widths[index] ~= nil then
                change(monitor, "size", widths[index])
            end
        end)
end

function StorageMonitor.openBrightness(monitor)
    local spec = monitor.spec_storageMonitor
    local options = {}
    for i, level in ipairs(StorageMonitor.BRIGHTNESS) do
        table.insert(options, StorageMonitor.getText(level.key, level.fallback) .. mark(i == spec.brightness))
    end
    StorageMonitor.showOptions(StorageMonitor.getText("storageMonitor_brightnessTitle", "Brightness"),
        StorageMonitor.getText("storageMonitor_brightnessText", "How strongly the screen, its bars and its text glow:"), options,
        function(index)
            if StorageMonitor.BRIGHTNESS[index] ~= nil then
                change(monitor, "brightness", index)
            end
        end)
end

function StorageMonitor.openTheme(monitor)
    local spec = monitor.spec_storageMonitor
    local options = {}
    for i, theme in ipairs(StorageMonitor.THEMES) do
        table.insert(options, StorageMonitor.getText(theme.key, theme.fallback) .. mark(i == spec.theme))
    end
    StorageMonitor.showOptions(StorageMonitor.getText("storageMonitor_themeTitle", "Colours"),
        StorageMonitor.getText("storageMonitor_themeText", "Colours of the screen:"), options,
        function(index)
            if StorageMonitor.THEMES[index] ~= nil then
                change(monitor, "theme", index)
            end
        end)
end

function StorageMonitor.openMode(monitor)
    local spec = monitor.spec_storageMonitor
    local options = {}
    for i, mode in ipairs(StorageMonitor.MODES) do
        table.insert(options, StorageMonitor.getText(mode.key, mode.fallback) .. mark(i == spec.mode))
    end
    StorageMonitor.showOptions(StorageMonitor.getText("storageMonitor_modeTitle", "Screen shows"),
        StorageMonitor.getText("storageMonitor_modeText", "The storage, or today's best prices for what is in it (pick \"All silos of my farm\" for a price board of the whole farm):"),
        options,
        function(index)
            if StorageMonitor.MODES[index] ~= nil then
                change(monitor, "mode", index)
            end
        end)
end

function StorageMonitor.openAlerts(monitor)
    local spec = monitor.spec_storageMonitor
    local options = {}
    for i, level in ipairs(StorageMonitor.ALERT_LEVELS) do
        table.insert(options, StorageMonitor.getText(level.key, level.fallback) .. mark(i == spec.alerts))
    end
    StorageMonitor.showOptions(StorageMonitor.getText("storageMonitor_alertsTitle", "Alerts"),
        StorageMonitor.getText("storageMonitor_alertsText", "Warn when it is nearly full, an input is empty, or animals run low on food or water:"),
        options,
        function(index)
            if StorageMonitor.ALERT_LEVELS[index] ~= nil then
                change(monitor, "alerts", index)
            end
        end)
end

-- the custom title: typed in the game's text input dialog; empty = the storage's own name
function StorageMonitor.openTitle(monitor)
    local spec = monitor.spec_storageMonitor
    StorageMonitor.showTextInput(StorageMonitor.getText("storageMonitor_titlePrompt", "Title on the screen (empty: the storage's name)"),
        spec.title, StorageMonitor.TITLE_MAX,
        function(text)
            text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            change(monitor, "title", text)
        end)
end

-- ---------------------------------------------------------------------------------------------------
-- mod event listener: drives all monitors on this client
-- ---------------------------------------------------------------------------------------------------

StorageMonitor.Listener = {}

function StorageMonitor.Listener:update(dt)
    if g_currentMission == nil or not g_currentMission:getIsClient() then
        return
    end
    StorageMonitor.clock = StorageMonitor.clock + (dt or 0)
    -- an error here must never stop the game's own update (that freezes the player), so every step is
    -- protected and a monitor that fails is switched off with one log line
    for _, monitor in ipairs(StorageMonitor.instances) do
        local spec = monitor.spec_storageMonitor
        if spec ~= nil and not spec.failed then
            local ok, err = pcall(StorageMonitor.updateStorageMonitor, monitor, dt)
            if not ok then
                spec.failed = true
                spec.isNear = false
                StorageMonitor.log("Error, monitor switched off: %s", tostring(err))
            end
        end
    end
    local ok, err = pcall(StorageMonitor.updateActionEvents)
    if ok then
        ok, err = pcall(StorageMonitor.openPendingDialog)
    end
    if not ok and not StorageMonitor.loggedListenerError then
        StorageMonitor.loggedListenerError = true
        StorageMonitor.log("Error: %s", tostring(err))
    end
end

function StorageMonitor.Listener:draw()
    if g_currentMission == nil or not g_currentMission:getIsClient() then
        return
    end
    -- the nearest MAX_DRAWN monitors in sight are drawn; the others only hide their bars
    local near = {}
    for _, monitor in ipairs(StorageMonitor.instances) do
        local spec = monitor.spec_storageMonitor
        if spec ~= nil and spec.isNear and not spec.failed then
            table.insert(near, monitor)
        end
    end
    local drawn = {}
    if #near > StorageMonitor.MAX_DRAWN then
        table.sort(near, function(a, b)
            return (a.spec_storageMonitor.distance or 0) < (b.spec_storageMonitor.distance or 0)
        end)
    end
    for i = 1, math.min(#near, StorageMonitor.MAX_DRAWN) do
        drawn[near[i]] = true
    end

    local depthSet = false
    for _, monitor in ipairs(StorageMonitor.instances) do
        local spec = monitor.spec_storageMonitor
        if spec ~= nil then
            for _, face in ipairs(spec.faces or {}) do
                StorageMonitor.beginBars(spec, face)
                if drawn[monitor] and face.visible and not spec.failed then
                    if not depthSet and setTextDepthTestEnabled ~= nil then
                        setTextDepthTestEnabled(true)
                        depthSet = true
                    end
                    local ok, err = pcall(StorageMonitor.drawStorageMonitor, monitor, face)
                    if not ok then
                        spec.isNear = false
                        spec.failed = true
                        face.barUsed = 0
                        face.iconUsed = 0
                        StorageMonitor.log("Error drawing, monitor switched off: %s", tostring(err))
                        pcall(StorageMonitor.resetTextState, monitor)
                    end
                end
                -- bars of a face nobody looks at are hidden, like its text
                pcall(StorageMonitor.endBars, spec, face)
            end
        end
    end
    if depthSet then
        setTextDepthTestEnabled(false)
    end
end

addModEventListener(StorageMonitor.Listener)

-- ---------------------------------------------------------------------------------------------------
-- settings action (the activate key in front of the screen)
-- ---------------------------------------------------------------------------------------------------

StorageMonitorActivatable = {}
local StorageMonitorActivatable_mt = Class(StorageMonitorActivatable)

function StorageMonitorActivatable.new(placeable)
    local self = setmetatable({}, StorageMonitorActivatable_mt)
    self.placeable = placeable
    self.activateText = StorageMonitor.getText("storageMonitor_settings", "Monitor settings")
    return self
end

function StorageMonitorActivatable:getIsActivatable()
    return self.placeable.spec_storageMonitor ~= nil
end

function StorageMonitorActivatable:run()
    StorageMonitor.openSettings(self.placeable)
end

function StorageMonitorActivatable:getDistance(x, y, z)
    local spec = self.placeable.spec_storageMonitor
    if spec ~= nil and spec.playerTrigger ~= nil then
        local tx, ty, tz = getWorldTranslation(spec.playerTrigger)
        return MathUtil.vector3Length(x - tx, y - ty, z - tz)
    end
    return math.huge
end
