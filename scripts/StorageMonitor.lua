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
-- m; heights of a raised mount's bottom edge above the ground (silo mount, wall mount, hanging) to choose from
StorageMonitor.HEIGHTS = {0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5, 6.0, 7.0, 8.0, 10.0, 12.0}
-- what my productions need: an input counts as low below PROD_LOW of its room or when it lasts less than
-- PROD_LOW_HOURS in-game hours
StorageMonitor.PROD_LOW = 0.25
StorageMonitor.PROD_LOW_HOURS = 3
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
    {key = "storageMonitor_mode3", fallback = "History (24 h)"},
}
StorageMonitor.MODE_PRICES = 2
StorageMonitor.MODE_HISTORY = 3
-- "nearly full" levels to choose from (alerts, and the red / amber colours: amber from 15 below)
StorageMonitor.FULL_LEVELS = {70, 75, 80, 85, 90, 95, 100}
StorageMonitor.fullAt = 90                  -- the level of the monitor being drawn
-- price alert: steps above today's best price to choose from
StorageMonitor.PRICE_STEPS = {1.05, 1.10, 1.15, 1.20, 1.30, 1.50}
-- slideshow: time per screen (index 1 = off); at most MAX_SLIDES screens
StorageMonitor.SLIDE_TIMES = {0, 10000, 20000, 30000, 60000}
StorageMonitor.DEFAULT_SLIDE_TIME = 3
StorageMonitor.MAX_SLIDES = 8
-- history graph: a sample every GRAPH_STEP in-game hours, kept for GRAPH_SPAN hours
StorageMonitor.GRAPH_STEP = 0.5
StorageMonitor.GRAPH_SPAN = 24
StorageMonitor.BOARD_INTERVAL = 10000       -- ms between reads of the farm's fields / vehicles (shared)
-- Screens of the whole farm: at the end of the pick list, picked by a position no building has. The kinds
-- with rows (a board) list fields, vehicles, contracts, pens or productions instead of products.
StorageMonitor.FARM_SCREENS = {
    {kind = "farm",           pick = -9999999, key = "storageMonitor_farmAll",       fallback = "All silos of my farm"},
    {kind = "finance",        pick = -8888888, key = "storageMonitor_finance",       fallback = "My farm's money"},
    {kind = "fields",         pick = -7777777, key = "storageMonitor_fields",        fallback = "My fields",            board = true},
    {kind = "weather",        pick = -6666666, key = "storageMonitor_weather",       fallback = "Weather",              board = true},
    {kind = "fleet",          pick = -5555555, key = "storageMonitor_fleet",         fallback = "My vehicles",          board = true},
    {kind = "contracts",      pick = -4444444, key = "storageMonitor_contracts",     fallback = "My contracts",         board = true},
    {kind = "allPens",        pick = -3333333, key = "storageMonitor_allPens",       fallback = "All my animal pens",   board = true},
    {kind = "allProductions", pick = -2222222, key = "storageMonitor_allProductions", fallback = "All my productions",  board = true},
    {kind = "prodNeeds",      pick = -1717171, key = "storageMonitor_prodNeeds",     fallback = "What my productions need", board = true},
    {kind = "sellPlan",       pick = -1111111, key = "storageMonitor_sellPlan",      fallback = "When to sell",         board = true},
    {kind = "profit",         pick = -1313131, key = "storageMonitor_profit",        fallback = "Production profit",    board = true},
    {kind = "openContracts",  pick = -1414141, key = "storageMonitor_openContracts", fallback = "Contracts to take",    board = true},
    {kind = "farms",          pick = -1515151, key = "storageMonitor_farms",         fallback = "All farms",            board = true},
    {kind = "fieldMap",       pick = -1616161, key = "storageMonitor_fieldMap",      fallback = "Map of my fields",     board = true},
    {kind = "message",        pick = -1212121, key = "storageMonitor_message",       fallback = "Message board"},
}
StorageMonitor.MESSAGE_MAX = 240            -- characters of a message board
StorageMonitor.ONLY_MAX = 8                 -- products a monitor can be limited to
StorageMonitor.FARM_KINDS = {}
StorageMonitor.BOARD_KINDS = {}
for _, s in ipairs(StorageMonitor.FARM_SCREENS) do
    StorageMonitor.FARM_KINDS[s.kind] = s
    if s.board then
        StorageMonitor.BOARD_KINDS[s.kind] = true
    end
end
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
    {id = "field", key = "storageMonitor_theme2", fallback = "Green", texture = "textures/screen_field.dds", colors = {
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

-- colour for a fill percentage (0..100): red from the monitor's "nearly full" level, amber from 15 below it
function StorageMonitor.levelColor(percent)
    local full = StorageMonitor.fullAt or 90
    if percent >= full then
        return COLORS.full
    elseif percent >= full - 15 then
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
            fillLevels = storage.getFillLevels ~= nil and storage:getFillLevels() or {}
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

--- The history of one screen (rates, graph); a monitor keeps one per screen it shows, so a slideshow does not
-- start its rates again at every turn. Buildings that are gone drop out (weak keys).
function StorageMonitor.historyFor(spec, owner)
    if spec.histories == nil then
        spec.histories = setmetatable({}, {__mode = "k"})
    end
    local key = owner ~= nil and owner or "none"
    local h = spec.histories[key]
    if h == nil then
        h = {}
        spec.histories[key] = h
    end
    return h
end

--- Remembers a value every GRAPH_STEP in-game hours for the last GRAPH_SPAN hours (the history graph).
-- history.graph = {{t, v, cap}}; it starts again when the time jumps back or further than the span.
function StorageMonitor.updateGraph(history, now, value, capacity)
    if now == nil or value == nil then
        return
    end
    local graph = history.graph
    local last = graph ~= nil and graph[#graph] or nil
    if graph == nil or (last ~= nil and (now < last.t - 1e-6 or now - last.t > StorageMonitor.GRAPH_SPAN)) then
        graph = {}
        history.graph = graph
        last = nil
    end
    if last == nil or now - last.t >= StorageMonitor.GRAPH_STEP - 1e-6 then
        table.insert(graph, {t = now, v = value, cap = capacity})
        while #graph > 1 and now - graph[1].t > StorageMonitor.GRAPH_SPAN + 1e-6 do
            table.remove(graph, 1)
        end
    end
end

--- What a field's crop is doing, as the game's map shows it: "none", "growing", "prepare" (ready to be prepared
-- for the harvest, e.g. topped), "ready", "withered", "cut" (harvested). Second value: 0..1 on the way to ready.
function StorageMonitor.cropStage(fruit, growth)
    if fruit == nil or growth == nil or growth <= 0 then
        return "none", 0
    end
    if fruit.cutState ~= nil and growth == fruit.cutState then
        return "cut", 0
    end
    if type(fruit.getIsWithered) == "function" then
        if fruit:getIsWithered(growth) then
            return "withered", 1
        end
    end
    local minH, maxH = tonumber(fruit.minHarvestingGrowthState), tonumber(fruit.maxHarvestingGrowthState)
    local minP, maxP = tonumber(fruit.minPreparingGrowthState) or -1, tonumber(fruit.maxPreparingGrowthState) or -1
    if minP >= 0 and growth >= minP and growth <= maxP then
        return "prepare", 1
    end
    if minH ~= nil and maxH ~= nil and growth >= minH and growth <= maxH then
        return "ready", 1
    end
    local goal = (minP >= 0 and minP) or minH
    if goal ~= nil and goal > 0 and growth < goal then
        return "growing", math.max(0, math.min(1, growth / goal))
    end
    if maxH ~= nil and growth > maxH then
        return "withered", 1
    end
    return "growing", 0
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
    schema:register(XMLValueType.FLOAT, key .. "#height", "Raised mounts: height of the bottom edge above the ground in metres")
    schema:register(XMLValueType.INT, key .. "#brightness", "Brightness level 1..5", StorageMonitor.DEFAULT_BRIGHTNESS)
    schema:register(XMLValueType.INT, key .. "#theme", "Colour theme 1..4", 1)
    schema:register(XMLValueType.STRING, key .. "#title", "Custom title, empty = the storage's name", "")
    schema:register(XMLValueType.INT, key .. "#mode", "1 = the storage, 2 = prices", 1)
    schema:register(XMLValueType.INT, key .. "#alerts", "1 = off, 2 = on the screen, 3 = also as a message", StorageMonitor.DEFAULT_ALERTS)
    schema:register(XMLValueType.INT, key .. "#fullAt", "Percent from which a storage counts as nearly full", StorageMonitor.ALERT_FULL)
    schema:register(XMLValueType.STRING, key .. "#priceFillType", "Price alert: the product (fill type name)", "")
    schema:register(XMLValueType.FLOAT, key .. "#pricePerThousand", "Price alert: price per 1000 l", 0)
    schema:register(XMLValueType.INT, key .. "#slideTime", "Slideshow: 1 = off, 2..5 = 10, 20, 30, 60 s per screen", 1)
    schema:register(XMLValueType.FLOAT, key .. ".slide(?)#x", "Slideshow: position of a screen")
    schema:register(XMLValueType.FLOAT, key .. ".slide(?)#z", "Slideshow: position of a screen")
    schema:register(XMLValueType.STRING, key .. "#message", "Message board text", "")
    schema:register(XMLValueType.FLOAT, key .. "#messageTime", "Message board: in-game hours when it was written", 0)
    schema:register(XMLValueType.STRING, key .. ".only(?)#fillType", "Products shown: only these (fill type names)")
    schema:register(XMLValueType.STRING, key .. ".history#key", "History: the screen it belongs to")
    schema:register(XMLValueType.FLOAT, key .. ".history.s(?)#t", "History: in-game hours")
    schema:register(XMLValueType.FLOAT, key .. ".history.s(?)#v", "History: value")
    schema:register(XMLValueType.FLOAT, key .. ".history.s(?)#c", "History: capacity")
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
    -- one collision per screen size (a static body cannot be scaled); the one that fits is switched on, but
    -- only once the game has put the monitor into physics (onPostFinalizePlacement). Until then all are on, so
    -- the game takes every one as a pick object (construction mode selects the monitor by them).
    spec.collisions = {}
    spec.physicsReady = false
    local group = xmlFile:getValue("placeable.storageMonitor#collisions", nil, self.components, self.i3dMappings)
    spec.collisionGroup = group
    if group ~= nil then
        spec.collisionBase = {getTranslation(group)}
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
    spec.mountBottomDefault = spec.mountBottom      -- the height the model (and its collisions) is built for
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
    spec.fullAt = StorageMonitor.ALERT_FULL
    spec.priceAlert = nil           -- {fill = fill type name, price = per 1000 l}
    spec.slideTime = 1              -- index into SLIDE_TIMES (1 = no slideshow)
    spec.slides = {}                -- {x, z} of each screen in the slideshow
    spec.slideIndex = 1
    spec.slideTimer = 0
    spec.message = ""               -- the message board's text
    spec.messageTime = 0            -- in-game hours when it was written
    spec.only = {}                  -- fill type names: show only these products (one = the big single-product view)
    spec.histories = setmetatable({}, {__mode = "k"})
    spec.alertList = {}
    spec.alertKnownBy = setmetatable({}, {__mode = "k"})    -- per screen: alerts seen at its last read
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
    -- the monitor is in physics now: only the collision of its size stays on
    spec.physicsReady = true
    StorageMonitor.applyCollisions(self, false)
    StorageMonitor.registerPickCollisions(self)
end

-- Construction mode selects (to sell or move) a placeable by its pick objects, which the game collects once,
-- when it is placed, from the bodies that are on then. Every size's collision is one, so the monitor can be
-- selected at any size it is set to later.
function StorageMonitor.registerPickCollisions(monitor)
    local spec = monitor.spec_storageMonitor
    local picks = monitor.pickObjects
    if type(picks) ~= "table" then
        return
    end
    local known = {}
    for _, node in pairs(picks) do
        known[node] = true
    end
    for _, c in ipairs(spec.collisions or {}) do
        if c.node ~= nil and c.node ~= 0 and not known[c.node] then
            table.insert(picks, c.node)
            if g_currentMission ~= nil and g_currentMission.addNodeObject ~= nil then
                g_currentMission:addNodeObject(c.node, monitor)
            end
        end
    end
end

-- switches on the collision of the monitor's size and the others off (only once it is in physics). rebuild:
-- the collisions were moved (height); a static body does not follow its node, so the one that is on is made
-- again where it is now.
function StorageMonitor.applyCollisions(monitor, rebuild)
    local spec = monitor.spec_storageMonitor
    if not spec.physicsReady or setRigidBodyType == nil or RigidBodyType == nil then
        return
    end
    for _, c in ipairs(spec.collisions or {}) do
        if c.node ~= nil and c.node ~= 0 and (entityExists == nil or entityExists(c.node)) then
            local wanted = math.abs(c.width - spec.mountWidth) < 0.01 and RigidBodyType.STATIC or RigidBodyType.NONE
            if rebuild and wanted == RigidBodyType.STATIC and c.type == wanted then
                setRigidBodyType(c.node, RigidBodyType.NONE)
                c.type = RigidBodyType.NONE
            end
            if c.type ~= wanted then
                setRigidBodyType(c.node, wanted)
                c.type = wanted
            end
        end
    end
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
    settings.height = xmlFile:getValue(key .. "#height", settings.height)
    settings.brightness = xmlFile:getValue(key .. "#brightness", settings.brightness)
    settings.theme = xmlFile:getValue(key .. "#theme", settings.theme)
    settings.title = xmlFile:getValue(key .. "#title", "") or ""
    settings.mode = xmlFile:getValue(key .. "#mode", settings.mode)
    settings.alerts = xmlFile:getValue(key .. "#alerts", settings.alerts)
    settings.fullAt = xmlFile:getValue(key .. "#fullAt", settings.fullAt)
    local fill = xmlFile:getValue(key .. "#priceFillType", "") or ""
    local price = xmlFile:getValue(key .. "#pricePerThousand", 0) or 0
    settings.priceAlert = (fill ~= "" and price > 0) and {fill = fill, price = price} or nil
    settings.slideTime = xmlFile:getValue(key .. "#slideTime", 1)
    settings.slides = {}
    for i = 0, StorageMonitor.MAX_SLIDES - 1 do
        local slideKey = string.format("%s.slide(%d)", key, i)
        if xmlFile.hasProperty ~= nil and not xmlFile:hasProperty(slideKey) then
            break
        end
        local x, z = xmlFile:getValue(slideKey .. "#x"), xmlFile:getValue(slideKey .. "#z")
        if x == nil or z == nil then
            break
        end
        table.insert(settings.slides, {x, z})
    end
    settings.message = xmlFile:getValue(key .. "#message", "") or ""
    settings.messageTime = xmlFile:getValue(key .. "#messageTime", 0) or 0
    settings.only = {}
    for i = 0, StorageMonitor.ONLY_MAX - 1 do
        local name = xmlFile:getValue(string.format("%s.only(%d)#fillType", key, i))
        if name == nil or name == "" then
            break
        end
        table.insert(settings.only, name)
    end
    self:setStorageMonitorSettings(settings, true)
    -- the history the server kept
    local historyKey = xmlFile:getValue(key .. ".history#key")
    if historyKey ~= nil and historyKey ~= "" then
        local graph = {}
        for i = 0, 2 * math.floor(StorageMonitor.GRAPH_SPAN / StorageMonitor.GRAPH_STEP + 0.5) do
            local sKey = string.format("%s.history.s(%d)", key, i)
            local t, v = xmlFile:getValue(sKey .. "#t"), xmlFile:getValue(sKey .. "#v")
            if t == nil or v == nil then
                break
            end
            table.insert(graph, {t = t, v = v, cap = xmlFile:getValue(sKey .. "#c")})
        end
        spec.serverHistory = {key = historyKey, graph = graph}
    end
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
    if spec.mountMode == "silo" then
        xmlFile:setValue(key .. "#height", spec.mountBottom)
    end
    xmlFile:setValue(key .. "#brightness", spec.brightness)
    xmlFile:setValue(key .. "#theme", spec.theme)
    if spec.title ~= "" then
        xmlFile:setValue(key .. "#title", spec.title)
    end
    xmlFile:setValue(key .. "#mode", spec.mode)
    xmlFile:setValue(key .. "#alerts", spec.alerts)
    xmlFile:setValue(key .. "#fullAt", spec.fullAt)
    if spec.priceAlert ~= nil then
        xmlFile:setValue(key .. "#priceFillType", spec.priceAlert.fill)
        xmlFile:setValue(key .. "#pricePerThousand", spec.priceAlert.price)
    end
    xmlFile:setValue(key .. "#slideTime", spec.slideTime)
    for i, slide in ipairs(spec.slides) do
        local slideKey = string.format("%s.slide(%d)", key, i - 1)
        xmlFile:setValue(slideKey .. "#x", slide[1])
        xmlFile:setValue(slideKey .. "#z", slide[2])
    end
    if spec.message ~= "" then
        xmlFile:setValue(key .. "#message", spec.message)
        xmlFile:setValue(key .. "#messageTime", spec.messageTime)
    end
    for i, name in ipairs(spec.only) do
        xmlFile:setValue(string.format("%s.only(%d)#fillType", key, i - 1), name)
    end
    local history = spec.serverHistory
    if history ~= nil and history.key ~= nil and history.graph ~= nil and #history.graph > 0 then
        xmlFile:setValue(key .. ".history#key", history.key)
        for i, sample in ipairs(history.graph) do
            local sKey = string.format("%s.history.s(%d)", key, i - 1)
            xmlFile:setValue(sKey .. "#t", sample.t)
            xmlFile:setValue(sKey .. "#v", sample.v)
            if sample.cap ~= nil then
                xmlFile:setValue(sKey .. "#c", sample.cap)
            end
        end
    end
end

-- the monitor's settings as a new table: change it and pass it to setStorageMonitorSettings
function StorageMonitor:getStorageMonitorSettings()
    local spec = self.spec_storageMonitor
    local pick = spec.pick ~= nil and {spec.pick[1], spec.pick[2]} or nil
    local slides = {}
    for _, slide in ipairs(spec.slides or {}) do
        table.insert(slides, {slide[1], slide[2]})
    end
    local priceAlert = spec.priceAlert ~= nil and {fill = spec.priceAlert.fill, price = spec.priceAlert.price} or nil
    local only = {}
    for _, name in ipairs(spec.only or {}) do
        table.insert(only, name)
    end
    return {pick = pick, connected = spec.connected, size = spec.mountWidth, height = spec.mountBottom, brightness = spec.brightness,
            theme = spec.theme, title = spec.title, mode = spec.mode, alerts = spec.alerts, fullAt = spec.fullAt,
            priceAlert = priceAlert, slideTime = spec.slideTime, slides = slides, message = spec.message,
            messageTime = spec.messageTime, only = only}
end

function StorageMonitor.writeSettings(streamId, settings)
    streamWriteBool(streamId, settings.pick ~= nil)
    if settings.pick ~= nil then
        streamWriteFloat32(streamId, settings.pick[1])
        streamWriteFloat32(streamId, settings.pick[2])
    end
    streamWriteBool(streamId, settings.connected == true)
    streamWriteFloat32(streamId, settings.size or 0)
    streamWriteFloat32(streamId, settings.height or 0)
    streamWriteUInt8(streamId, settings.brightness or StorageMonitor.DEFAULT_BRIGHTNESS)
    streamWriteUInt8(streamId, settings.theme or 1)
    streamWriteString(streamId, settings.title or "")
    streamWriteUInt8(streamId, settings.mode or 1)
    streamWriteUInt8(streamId, settings.alerts or StorageMonitor.DEFAULT_ALERTS)
    streamWriteUInt8(streamId, settings.fullAt or StorageMonitor.ALERT_FULL)
    local priceAlert = settings.priceAlert
    streamWriteString(streamId, priceAlert ~= nil and priceAlert.fill or "")
    streamWriteFloat32(streamId, priceAlert ~= nil and priceAlert.price or 0)
    streamWriteUInt8(streamId, settings.slideTime or 1)
    local slides = settings.slides or {}
    local count = math.min(#slides, StorageMonitor.MAX_SLIDES)
    streamWriteUInt8(streamId, count)
    for i = 1, count do
        streamWriteFloat32(streamId, slides[i][1])
        streamWriteFloat32(streamId, slides[i][2])
    end
    streamWriteString(streamId, settings.message or "")
    streamWriteFloat32(streamId, settings.messageTime or 0)
    local only = settings.only or {}
    local onlyCount = math.min(#only, StorageMonitor.ONLY_MAX)
    streamWriteUInt8(streamId, onlyCount)
    for i = 1, onlyCount do
        streamWriteString(streamId, only[i])
    end
end

function StorageMonitor.readSettings(streamId)
    local settings = {}
    if streamReadBool(streamId) then
        settings.pick = {streamReadFloat32(streamId), streamReadFloat32(streamId)}
    end
    settings.connected = streamReadBool(streamId)
    settings.size = streamReadFloat32(streamId)
    settings.height = streamReadFloat32(streamId)
    settings.brightness = streamReadUInt8(streamId)
    settings.theme = streamReadUInt8(streamId)
    settings.title = streamReadString(streamId)
    settings.mode = streamReadUInt8(streamId)
    settings.alerts = streamReadUInt8(streamId)
    settings.fullAt = streamReadUInt8(streamId)
    local fill = streamReadString(streamId)
    local price = streamReadFloat32(streamId)
    settings.priceAlert = (fill ~= nil and fill ~= "" and price > 0) and {fill = fill, price = price} or nil
    settings.slideTime = streamReadUInt8(streamId)
    settings.slides = {}
    for _ = 1, streamReadUInt8(streamId) do
        table.insert(settings.slides, {streamReadFloat32(streamId), streamReadFloat32(streamId)})
    end
    settings.message = streamReadString(streamId)
    settings.messageTime = streamReadFloat32(streamId)
    settings.only = {}
    for _ = 1, streamReadUInt8(streamId) do
        table.insert(settings.only, streamReadString(streamId))
    end
    return settings
end

function StorageMonitor.writeSample(streamId, sample)
    streamWriteFloat32(streamId, sample.t)
    streamWriteFloat32(streamId, sample.v)
    streamWriteBool(streamId, sample.cap ~= nil)
    if sample.cap ~= nil then
        streamWriteFloat32(streamId, sample.cap)
    end
end

function StorageMonitor.readSample(streamId)
    local sample = {t = streamReadFloat32(streamId), v = streamReadFloat32(streamId)}
    if streamReadBool(streamId) then
        sample.cap = streamReadFloat32(streamId)
    end
    return sample
end

function StorageMonitor:onWriteStream(streamId, connection)
    StorageMonitor.writeSettings(streamId, self:getStorageMonitorSettings())
    -- the history the server keeps, for a player joining
    local history = self.spec_storageMonitor.serverHistory
    local graph = history ~= nil and history.graph or {}
    streamWriteString(streamId, history ~= nil and history.key or "")
    streamWriteUInt8(streamId, math.min(#graph, 255))
    for i = 1, math.min(#graph, 255) do
        StorageMonitor.writeSample(streamId, graph[i])
    end
end

function StorageMonitor:onReadStream(streamId, connection)
    self:setStorageMonitorSettings(StorageMonitor.readSettings(streamId), true)
    local key = streamReadString(streamId)
    local graph = {}
    for _ = 1, streamReadUInt8(streamId) do
        table.insert(graph, StorageMonitor.readSample(streamId))
    end
    if key ~= "" then
        self.spec_storageMonitor.serverHistory = {key = key, graph = graph}
    end
end

-- resizes the screen to the given width in metres (clamped to SIZE_WIDTHS) and, on a raised mount (silo
-- mount, wall mount, hanging), puts its bottom edge at the given height in metres (clamped to HEIGHTS; nil
-- keeps it). A raised mount grows upwards from its bottom edge and keeps its depth; a free-standing monitor
-- grows from the ground, posts and all. Each size has its own collision; the collisions move with the height.
function StorageMonitor:setStorageMonitorSize(width, bottom)
    local spec = self.spec_storageMonitor
    if spec.mountNode == nil or width == nil or width <= 0 then
        return
    end
    local widths = StorageMonitor.SIZE_WIDTHS
    spec.mountWidth = math.max(widths[1], math.min(widths[#widths], width))
    spec.sizeScale = spec.mountWidth / spec.width
    local s = spec.sizeScale
    local x, y, z = getTranslation(spec.mountNode)
    local moved = false
    if spec.mountMode == "silo" then
        local b = tonumber(bottom)
        if b ~= nil and b > 0 then
            local heights = StorageMonitor.HEIGHTS
            b = math.max(heights[1], math.min(heights[#heights], b))
            moved = math.abs(b - spec.mountBottom) > 1e-6
            spec.mountBottom = b
        end
        setScale(spec.mountNode, s, s, 1)
        y = spec.mountBottom + spec.mountLowerExtent * s
    else
        setScale(spec.mountNode, s, s, s)
    end
    setTranslation(spec.mountNode, x, y, z)
    if moved and spec.collisionGroup ~= nil and spec.collisionBase ~= nil then
        local base = spec.collisionBase
        setTranslation(spec.collisionGroup, base[1], base[2] + spec.mountBottom - (spec.mountBottomDefault or spec.mountBottom), base[3])
    end
    StorageMonitor.applyCollisions(self, moved)
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
            -- the theme's screen texture, on a new material made from the glass's own one and put on at once (the
            -- game frees a material no shape uses, so none is kept); the first look of the night theme is the model's
            if face.appliedTheme ~= theme.id and (face.appliedTheme ~= nil or theme.id ~= "night")
                and setMaterialDiffuseMapFromFile ~= nil and StorageMonitor.MOD_DIR ~= nil then
                local source = getMaterial(glass, 0)
                local material = nil
                if source ~= nil and source ~= 0 then
                    material = setMaterialDiffuseMapFromFile(source, StorageMonitor.MOD_DIR .. theme.texture, true, true, false)
                end
                if material ~= nil and material ~= 0 then
                    setMaterial(glass, material, 0)
                elseif face.loggedTheme ~= theme.id then
                    face.loggedTheme = theme.id
                    StorageMonitor.log("Warning: theme texture %s not loaded", tostring(theme.texture))
                end
            end
            face.appliedTheme = theme.id
            setShaderParameter(glass, "lightControl", StorageMonitor.GLASS_GLOW * StorageMonitor.brightnessFactor(spec), 0, 0, 0, false)
        end
    end
end

-- whether a new slideshow differs from the monitor's (then it starts again at its first screen)
function StorageMonitor.slidesChanged(spec, slides, slideTime)
    local old = spec.slides or {}
    if #old ~= #slides or spec.slideTime ~= slideTime then
        return true
    end
    for i, slide in ipairs(slides) do
        if math.abs(slide[1] - old[i][1]) > 0.01 or math.abs(slide[2] - old[i][2]) > 0.01 then
            return true
        end
    end
    return false
end

-- the screens of a running slideshow, or nil (off, or no screens in it)
function StorageMonitor.activeSlides(spec)
    if (spec.slideTime or 1) > 1 and spec.slides ~= nil and #spec.slides > 0 then
        return spec.slides
    end
    return nil
end

-- the position the monitor shows: the slideshow's current screen, else the picked one (nil: the nearest)
function StorageMonitor.currentPick(spec)
    local slides = StorageMonitor.activeSlides(spec)
    if slides ~= nil then
        if spec.slideIndex == nil or spec.slideIndex > #slides then
            spec.slideIndex = 1
        end
        return slides[spec.slideIndex]
    end
    return spec.pick
end

-- settings: see getStorageMonitorSettings. pick: {x, z} of the storage to show, or nil for the nearest;
-- connected: also show the silos connected to it; size: screen width in metres; height: a raised mount's
-- bottom edge above the ground in metres; brightness: 1..5;
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
    spec.fullAt = math.max(50, math.min(100, math.floor(settings.fullAt or StorageMonitor.ALERT_FULL)))
    local priceAlert = settings.priceAlert
    if priceAlert ~= nil and type(priceAlert.fill) == "string" and priceAlert.fill ~= "" and (tonumber(priceAlert.price) or 0) > 0 then
        spec.priceAlert = {fill = priceAlert.fill, price = tonumber(priceAlert.price)}
    else
        spec.priceAlert = nil
    end
    local slides = {}
    for _, slide in ipairs(settings.slides or {}) do
        if #slides < StorageMonitor.MAX_SLIDES and tonumber(slide[1]) ~= nil and tonumber(slide[2]) ~= nil then
            table.insert(slides, {tonumber(slide[1]), tonumber(slide[2])})
        end
    end
    local slideTime = math.max(1, math.min(#StorageMonitor.SLIDE_TIMES, math.floor(settings.slideTime or 1)))
    if StorageMonitor.slidesChanged(spec, slides, slideTime) then
        spec.slideIndex = 1
        spec.slideTimer = 0
    end
    spec.slides = slides
    spec.slideTime = slideTime
    local message = tostring(settings.message or "")
    if utf8Strlen ~= nil and utf8Substr ~= nil and utf8Strlen(message) > StorageMonitor.MESSAGE_MAX then
        message = utf8Substr(message, 0, StorageMonitor.MESSAGE_MAX)
    elseif #message > StorageMonitor.MESSAGE_MAX * 4 then
        message = string.sub(message, 1, StorageMonitor.MESSAGE_MAX * 4)
    end
    spec.message = message
    spec.messageTime = tonumber(settings.messageTime) or 0
    spec.only = {}
    for _, name in ipairs(settings.only or {}) do
        if type(name) == "string" and name ~= "" and #spec.only < StorageMonitor.ONLY_MAX then
            table.insert(spec.only, name)
        end
    end
    self:setStorageMonitorSize(settings.size, settings.height)
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
    if StorageMonitor.farmOverride ~= nil then       -- the server reading a monitor: the monitor's farm
        return StorageMonitor.farmOverride
    end
    if g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
        return g_localPlayer.farmId
    end
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        return g_currentMission:getFarmId()
    end
    return 1
end
StorageMonitor.getPlayerFarmId = getPlayerFarmId

-- the farm of the player at this game, whatever monitor is being read (alert messages, "you")
local function realPlayerFarmId()
    local saved = StorageMonitor.farmOverride
    StorageMonitor.farmOverride = nil
    local farmId = getPlayerFarmId()
    StorageMonitor.farmOverride = saved
    return farmId
end
StorageMonitor.realPlayerFarmId = realPlayerFarmId

-- the farm that owns a monitor (it shows that farm's data to everyone who looks), or nil
function StorageMonitor.monitorFarmId(monitor)
    if monitor == nil or monitor.getOwnerFarmId == nil then
        return nil
    end
    local owner = monitor:getOwnerFarmId()
    local spectator = FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID or 0
    if type(owner) == "number" and owner ~= spectator then
        return owner
    end
    return nil
end

-- runs fn(monitor, ...) as the monitor's own farm: a player of another farm looking at the board sees the
-- owner's fields, money, contracts and silos, not their own (after an error the listener clears the override)
function StorageMonitor.asMonitorFarm(monitor, fn, ...)
    local saved = StorageMonitor.farmOverride
    StorageMonitor.farmOverride = StorageMonitor.monitorFarmId(monitor) or saved
    local result = {fn(monitor, ...)}
    StorageMonitor.farmOverride = saved
    return (table.unpack or unpack)(result)
end

local function placeableName(placeable, fallback)
    if placeable ~= nil and placeable.getName ~= nil then
        local name = placeable:getName()
        if name ~= nil and name ~= "" then
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

--- The farm's production points from the game's production chain manager, the list its production menu
-- shows; nil when there is no manager or the call fails. Mods and DLCs change what it returns: Pumps N'
-- Hoses gives one merged point per biogas plant part type instead of every fermenter.
function StorageMonitor.farmProductionPoints(mission, farmId)
    local manager = mission ~= nil and mission.productionChainManager or nil
    if type(manager) ~= "table" or manager.getProductionPointsForFarmId == nil then
        return nil
    end
    local ok, list = pcall(manager.getProductionPointsForFarmId, manager, farmId)
    if not ok or type(list) ~= "table" then
        return nil
    end
    return list
end

--- True for a part of a Pumps N' Hoses biogas plant. The DLC's SandboxPlaceable is on every silo placeable,
-- so only its isSandboxPlaceable() says whether this one really is a part (its globals are not ours to see).
function StorageMonitor.isBiogasPart(placeable)
    if type(placeable) ~= "table" or placeable.isSandboxPlaceable == nil then
        return false
    end
    local ok, isPart = pcall(placeable.isSandboxPlaceable, placeable)
    return ok and isPart == true
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
    local pens, productions = {}, {}     -- the farm's own, for "all my animal pens / productions"
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
                    if ownFarm then
                        table.insert(productions, {placeable = p, pp = pp, greenhouse = p.spec_greenhouse, name = c.name})
                    end
                elseif isHusbandry then
                    c.kind = "husbandry"
                    table.insert(pens, {placeable = p, name = c.name})
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

    -- the farm's productions as the game's own production menu lists them. That list also has the ones
    -- the placeable walk above cannot see: the Pumps N' Hoses biogas plants (and mods built on them, like
    -- PlanET PnH), whose fermenters and power plants the DLC merges into one production per plant and
    -- returns only the merged ones here. Without the list (no manager) the walk's result stays as it is.
    local listed = StorageMonitor.farmProductionPoints(mission, farmId)
    if listed ~= nil then
        local scanned, inList = {}, {}
        for _, prod in ipairs(productions) do
            scanned[prod.pp] = prod
        end
        local merged = {}
        for _, pp in ipairs(listed) do
            if type(pp) == "table" and not inList[pp] then
                inList[pp] = true
                local prod = scanned[pp]
                local p = pp.owningPlaceable
                if prod == nil then
                    local ppName = pp.getName ~= nil and pp:getName() or nil
                    local name = (type(ppName) == "string" and ppName ~= "") and ppName
                        or placeableName(p, "?")
                    prod = {placeable = p, pp = pp, greenhouse = p ~= nil and p.spec_greenhouse or nil, name = name}
                    -- its own screen too, like a production found by the walk
                    if p ~= nil and p ~= self and type(pp.storage) == "table" and pp.storage.getFillLevels ~= nil
                        and isAccessible(pp.storage, farmId) then
                        local c = candidateFor(p, name)
                        near(c, nodePosition(p.rootNode))
                        c.placeable, c.kind, c.pp, c.greenhouse = p, "production", pp, p.spec_greenhouse
                        addStorage(c, pp.storage)
                        c.roles = c.roles or {}
                        for fillType in pairs(pp.inputFillTypeIds or {}) do
                            c.roles[fillType] = "in"
                        end
                        for fillType in pairs(pp.outputFillTypeIds or {}) do
                            c.roles[fillType] = (c.roles[fillType] == "in") and "inout" or "out"
                        end
                    end
                end
                table.insert(merged, prod)
            end
        end
        -- the walk's productions the list does not have stay, unless they are parts of a biogas plant:
        -- those the DLC merged into another one of the plant, which is in the list
        for _, prod in ipairs(productions) do
            if not inList[prod.pp] and not StorageMonitor.isBiogasPart(prod.placeable) then
                table.insert(merged, prod)
            end
        end
        productions = merged
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
    -- the screens of the whole farm, each only when there is something to show
    local available = {
        farm = #all > 0,
        finance = g_farmManager ~= nil and g_farmManager.getFarmById ~= nil,
        fields = g_fieldManager ~= nil and g_farmlandManager ~= nil,
        weather = mission.environment ~= nil and mission.environment.weather ~= nil,
        fleet = mission.vehicleSystem ~= nil and type(mission.vehicleSystem.vehicles) == "table",
        contracts = g_missionManager ~= nil and g_missionManager.getMissionsByFarmId ~= nil,
        allPens = #pens > 0,
        allProductions = #productions > 0,
        prodNeeds = #productions > 0,
        sellPlan = #all > 0,
        profit = #productions > 0,
        openContracts = g_missionManager ~= nil and type(g_missionManager.missions) == "table",
        farms = g_farmManager ~= nil and g_farmManager.getFarms ~= nil,
        fieldMap = g_fieldManager ~= nil and g_farmlandManager ~= nil,
        message = true,
    }
    for _, screen in ipairs(StorageMonitor.FARM_SCREENS) do
        if available[screen.kind] then
            table.insert(result, {owner = screen.kind, kind = screen.kind,
                storages = (screen.kind == "farm" or screen.kind == "sellPlan") and all or {},
                extra = {}, distance = math.huge, name = StorageMonitor.getText(screen.key, screen.fallback),
                anchor = {screen.pick, screen.pick}, pens = pens, productions = productions, silos = all})
        end
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
    for _, c in ipairs(candidates) do      -- the nearest real building, never a screen of the whole farm
        if StorageMonitor.FARM_KINDS[c.kind] == nil then
            return c
        end
    end
    return nil
end

function StorageMonitor:rescanStorageMonitor()
    return StorageMonitor.asMonitorFarm(self, StorageMonitor.rescanStorageMonitorNow)
end

function StorageMonitor:rescanStorageMonitorNow()
    local spec = self.spec_storageMonitor
    local candidates = StorageMonitor.collectStorageCandidates(self)
    spec.candidates = candidates
    spec.candidateCount = #candidates
    local previous = spec.target
    spec.target = nil
    local c = StorageMonitor.choose(candidates, StorageMonitor.currentPick(spec))
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
                       greenhouse = c.greenhouse, hives = c.hives, spawners = c.spawners,
                       pens = c.pens, productions = c.productions, silos = c.silos}
    end
    if previous == nil or spec.target == nil or previous.owner ~= spec.target.owner then
        spec.page = 1
        spec.pageTime = 0
        spec.rowCache = {}
        spec.headerTitle = nil
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

-- object:name(...) when the object has that method (the game version or the object kind may lack it), else nil
local function call(object, name, ...)
    if type(object) == "table" and type(object[name]) == "function" then
        local a, b = object[name](object, ...)
        return a, b
    end
    return nil
end

--- What the top panel shows for the kinds that are not plain storages: production lines, animals and their
-- condition, bunker silos, bale / pallet sheds. nil for silos (capacity panel).
function StorageMonitor.buildPanel(target)
    local T = StorageMonitor.getText
    if StorageMonitor.BOARD_KINDS[target.kind] then
        return StorageMonitor.buildBoard(target)
    end
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
-- boards: screens of the whole farm that list fields, the weather, vehicles, contracts, pens or productions.
-- A board panel has rows {id, title, icon, swatch, value, valueColor, sub, subColor, ratio, ratioColor} (colours
-- are COLORS keys or {r, g, b}, resolved when drawn, so the theme applies), its own numbers for the summary,
-- and problems {id, text} for the alerts.
-- ---------------------------------------------------------------------------------------------------

StorageMonitor.boardCache = {}

-- a board read at most every BOARD_INTERVAL, shared by all monitors (fields and vehicles cost the most)
local function cachedBoard(key, build)
    local c = StorageMonitor.boardCache[key]
    if c == nil or StorageMonitor.clock < c.time or StorageMonitor.clock - c.time >= StorageMonitor.BOARD_INTERVAL then
        c = {time = StorageMonitor.clock, value = build()}
        StorageMonitor.boardCache[key] = c
    end
    return c.value
end

local function clamp01(v)
    return math.max(0, math.min(1, tonumber(v) or 0))
end

-- puts a product's icon (the game's own) and colour on a row, when there is one
local function withProductIcon(row, fillTypeIndex)
    local info = fillTypeIndex ~= nil and fillTypeInfo(fillTypeIndex) or nil
    if info ~= nil and info.icon ~= nil and info.icon ~= "" then
        row.icon = info.icon
        row.iconColor = StorageMonitor.colorForName(info.name)
    end
    return row
end

-- a key of a table of fill type indices (outputs of a production), the lowest first, or nil
local function firstKey(t)
    local best = nil
    for k in pairs(t or {}) do
        if type(k) == "number" and (best == nil or k < best) then
            best = k
        end
    end
    return best
end

-- sorts rows by rank, then by title
local function sortRows(rows)
    table.sort(rows, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        if math.abs((a.order or 0) - (b.order or 0)) > 1e-9 then
            return (a.order or 0) < (b.order or 0)
        end
        return tostring(a.title) < tostring(b.title)
    end)
end

function StorageMonitor.formatArea(ha)
    ha = tonumber(ha) or 0
    if g_i18n ~= nil and g_i18n.getArea ~= nil and g_i18n.getAreaUnit ~= nil then
        local value = g_i18n:getArea(ha)
        local unit = g_i18n:getAreaUnit()
        if tonumber(value) ~= nil and unit ~= nil then
            return string.format("%.1f %s", tonumber(value), tostring(unit))
        end
    end
    return string.format("%.1f ha", ha)
end

-- degrees in the player's unit (the game converts), "12°"
function StorageMonitor.formatTemperature(celsius)
    celsius = tonumber(celsius)
    if celsius == nil then
        return "--"
    end
    local value = celsius
    if g_i18n ~= nil and g_i18n.getTemperature ~= nil then
        local converted = g_i18n:getTemperature(celsius)
        if tonumber(converted) ~= nil then
            value = tonumber(converted)
        end
    end
    return string.format("%d°", math.floor(value + 0.5))
end

-- what an empty board says
StorageMonitor.EMPTY_BOARD = {
    fields = {"storageMonitor_noFields", "Your farm has no fields"},
    weather = {"storageMonitor_noForecast", "No forecast"},
    fleet = {"storageMonitor_noVehicles", "Your farm has no vehicles"},
    contracts = {"storageMonitor_noContracts", "No contracts running"},
    allPens = {"storageMonitor_noPens", "Your farm has no animal pens"},
    allProductions = {"storageMonitor_noProductions", "Your farm has no productions"},
    prodNeeds = {"storageMonitor_noProductions", "Your farm has no productions"},
    sellPlan = {"storageMonitor_noSellable", "Nothing in your silos sells anywhere"},
    profit = {"storageMonitor_noLines", "No production line is switched on"},
    openContracts = {"storageMonitor_noOpenContracts", "No contracts to take right now"},
    farms = {"storageMonitor_noFarms", "No farms"},
    fieldMap = {"storageMonitor_noFields", "Your farm has no fields"},
}

StorageMonitor.CROP_TEXTS = {
    ready = {"storageMonitor_cropReady", "Harvest", "ok", 1},
    prepare = {"storageMonitor_cropPrepare", "Prepare", "warn", 2},
    withered = {"storageMonitor_cropWithered", "Withered", "full", 3},
    cut = {"storageMonitor_cropCut", "Harvested", "dim", 4},
    none = {"storageMonitor_cropNone", "No crop", "dim", 5},
    growing = {"storageMonitor_cropGrowing", "Growing", "accent", 6},
}

--- The farm's fields: the crop and how far it is (read at the middle of the field, as the game's field info
-- does), what the field needs, the ones to harvest first.
function StorageMonitor.readFields(farmId)
    local T = StorageMonitor.getText
    local panel = {kind = "fields", rows = {}, problems = {}, count = 0, area = 0, ready = 0, growing = 0,
                   withered = 0, toSow = 0, work = 0}
    local fm = g_fieldManager
    local fields = call(fm, "getFields") or (fm ~= nil and fm.fields) or {}
    local mission = g_currentMission or {}
    local info = mission.missionInfo or {}
    local maxSpray = nil
    if mission.fieldGroundSystem ~= nil and FieldDensityMap ~= nil and FieldDensityMap.SPRAY_LEVEL ~= nil then
        maxSpray = tonumber(call(mission.fieldGroundSystem, "getMaxValue", FieldDensityMap.SPRAY_LEVEL))
    end
    local readyRows = {}
    for _, field in pairs(fields) do
        local farmland = type(field) == "table" and field.farmland or nil
        local owner = farmland ~= nil and call(g_farmlandManager, "getFarmlandOwner", farmland.id) or nil
        if owner ~= nil and owner == farmId then
            local x, z = call(field, "getCenterOfFieldWorldPosition")
            local fruitIndex, growth = nil, nil
            x, z = tonumber(x), tonumber(z)
            if x ~= nil and z ~= nil and FSDensityMapUtil ~= nil and FSDensityMapUtil.getFruitTypeIndexAtWorldPos ~= nil then
                local a, b = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(x, z)
                fruitIndex, growth = tonumber(a), tonumber(b)
            end
            local fruit = nil
            if fruitIndex ~= nil and fruitIndex > 0 and g_fruitTypeManager ~= nil then
                fruit = call(g_fruitTypeManager, "getFruitTypeByIndex", fruitIndex)
            end
            local stage, progress = StorageMonitor.cropStage(fruit, growth)
            -- the field's ground (lime, fertilizer, plowing, rolling, weeds), read fresh at its middle
            local state = field.fieldState
            if type(state) ~= "table" then
                state = call(field, "getFieldState")
            end
            if type(state) == "table" and type(state.update) == "function" and x ~= nil and z ~= nil then
                state:update(x, z)
            end
            local needs = {}
            if type(state) == "table" then
                local early = stage == "none" or stage == "cut" or stage == "growing"
                if info.limeRequired and tonumber(state.limeLevel) == 0 then
                    table.insert(needs, T("storageMonitor_needLime", "Lime"))
                end
                if info.plowingRequiredEnabled and tonumber(state.plowLevel) == 0 and stage ~= "growing" then
                    table.insert(needs, T("storageMonitor_needPlow", "Plow"))
                end
                local spray = tonumber(state.sprayLevel)
                if early and maxSpray ~= nil and maxSpray > 0 and spray ~= nil and spray < maxSpray then
                    table.insert(needs, string.format(T("storageMonitor_needFertilizer", "Fertilizer %d%%"),
                        math.floor(spray / maxSpray * 100 + 0.5)))
                end
                if early and (tonumber(state.rollerLevel) or 0) > 0 then
                    table.insert(needs, T("storageMonitor_needRoll", "Roll"))
                end
                if info.weedsEnabled and stage == "growing" and (tonumber(state.weedState) or 0) > 0 then
                    table.insert(needs, T("storageMonitor_needWeeds", "Weeds"))
                end
            end

            local id = call(field, "getId") or field.fieldId or (farmland ~= nil and farmland.id) or "?"
            local name = string.format(T("storageMonitor_fieldNo", "Field %s"), tostring(id))
            local fillType = fruit ~= nil and fruit.fillType or nil
            local cropTitle = fillType ~= nil and fillType.title or (fruit ~= nil and fruit.name) or nil
            local stageText = StorageMonitor.CROP_TEXTS[stage]
            local value = T(stageText[1], stageText[2])
            if stage == "growing" then
                value = string.format("%s %d%%", value, math.floor(progress * 100 + 0.5))
            end
            local area = tonumber(field.areaHa) or 0
            -- the expected harvest (as the game's field info works it out) and its worth at today's best price
            local yieldText = nil
            local perSqm = fruit ~= nil and tonumber(fruit.literPerSqm) or nil
            if perSqm ~= nil and (stage == "growing" or stage == "ready" or stage == "prepare") then
                local multiplier = type(state) == "table" and tonumber(call(state, "getHarvestScaleMultiplier")) or 1
                local litres = perSqm * area * 10000 * multiplier
                local fillIndex = fillType ~= nil and tonumber(fillType.index) or nil
                local best = fillIndex ~= nil and StorageMonitor.bestPrice(fillIndex) or nil
                yieldText = "~" .. StorageMonitor.formatVolume(litres)
                if best ~= nil then
                    local value = litres * best.price
                    panel.harvestValue = (panel.harvestValue or 0) + value
                    yieldText = yieldText .. "  " .. StorageMonitor.formatMoney(value)
                end
            end
            local row = {id = "field" .. tostring(id), rank = stageText[4], order = stage == "growing" and -progress or (tonumber(id) or 0),
                title = cropTitle ~= nil and string.format("%s  %s", name, cropTitle) or name,
                icon = fillType ~= nil and fillType.hudOverlayFilename or nil,
                swatch = fruit ~= nil and StorageMonitor.colorForName(fillType ~= nil and fillType.name or fruit.name) or "track",
                value = value, valueColor = stageText[3],
                sub = #needs > 0 and table.concat(needs, ", ") or yieldText or StorageMonitor.formatArea(area),
                subColor = #needs > 0 and "warn" or "dim"}
            if stage ~= "none" and stage ~= "cut" then
                row.ratio, row.ratioColor = progress, stageText[3]
            end
            table.insert(panel.rows, row)
            panel.count = panel.count + 1
            panel.area = panel.area + area
            if stage == "ready" or stage == "prepare" then
                panel.ready = panel.ready + 1
                table.insert(readyRows, {id = id, text = string.format(T("storageMonitor_alertReady", "%s: %s ready to harvest"),
                    name, tostring(cropTitle or ""))})
            elseif stage == "growing" then
                panel.growing = panel.growing + 1
            elseif stage == "withered" then
                panel.withered = panel.withered + 1
                table.insert(panel.problems, {id = "withered_" .. tostring(id),
                    text = string.format(T("storageMonitor_alertWithered", "%s: the crop has withered"), name)})
            else
                panel.toSow = panel.toSow + 1
            end
            if #needs > 0 then
                panel.work = panel.work + 1
            end
        end
    end
    -- the harvest window: how long it stays dry (the weather screen's forecast)
    local weather = StorageMonitor.readWeather()
    if weather ~= nil then
        panel.dryFor, panel.raining = weather.dryFor, weather.raining or weather.snowing or weather.hail
        if #readyRows > 0 and panel.dryFor ~= nil and panel.dryFor > 0 and panel.dryFor <= 6 then
            table.insert(panel.problems, {id = "harvestRain", text = string.format(T("storageMonitor_alertHarvestRain",
                "%d fields ready, rain in %d h"), #readyRows, panel.dryFor)})
        end
    end
    -- a message per field ready to harvest; one for all of them when there are many
    if #readyRows > 3 then
        table.insert(panel.problems, 1, {id = "readyMany",
            text = string.format(T("storageMonitor_alertReadyMany", "%d fields ready to harvest"), #readyRows)})
    else
        for i, r in ipairs(readyRows) do
            table.insert(panel.problems, i, {id = "ready_" .. tostring(r.id), text = r.text})
        end
    end
    sortRows(panel.rows)
    return panel
end

-- weather types: text and colour by the type's name (the game's WeatherType)
StorageMonitor.WEATHER_TEXTS = {
    SUN = {"storageMonitor_wSun", "Sunny", "warn"},
    CLOUDY = {"storageMonitor_wCloudy", "Cloudy", "dim"},
    RAIN = {"storageMonitor_wRain", "Rain", "input"},
    SNOW = {"storageMonitor_wSnow", "Snow", "text"},
    FOG = {"storageMonitor_wFog", "Fog", "dim"},
    HAIL = {"storageMonitor_wHail", "Hail", "full"},
    TWISTER = {"storageMonitor_wStorm", "Storm", "full"},
    STORM = {"storageMonitor_wStorm", "Storm", "full"},
    THUNDER = {"storageMonitor_wStorm", "Storm", "full"},
}
StorageMonitor.WET_WEATHER = {RAIN = true, SNOW = true, HAIL = true, TWISTER = true, STORM = true, THUNDER = true}

--- {id, title, color} of a weather type (the game's index, name or table), nil for nil
function StorageMonitor.weatherInfo(weatherType)
    if weatherType == nil then
        return nil
    end
    local name = nil
    if type(weatherType) == "string" then
        name = weatherType
    elseif type(weatherType) == "table" then
        name = weatherType.name
    elseif type(weatherType) == "number" then
        if g_weatherTypeManager ~= nil then
            local wt = call(g_weatherTypeManager, "getWeatherTypeByIndex", weatherType)
            if type(wt) == "table" then
                name = wt.name
            end
        end
        if name == nil and type(WeatherType) == "table" then
            for k, v in pairs(WeatherType) do
                if v == weatherType and type(k) == "string" then
                    name = k
                end
            end
        end
    end
    local id = string.upper(tostring(name or "?"))
    local entry = StorageMonitor.WEATHER_TEXTS[id]
    if entry == nil then
        return {id = id, title = (string.gsub(string.lower(id), "^%l", string.upper)), color = "text"}
    end
    return {id = id, title = StorageMonitor.getText(entry[1], entry[2]), color = entry[3]}
end

--- The weather now, today's temperatures, the next hours and the next days (the game's forecast).
function StorageMonitor.readWeather()
    local T = StorageMonitor.getText
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local w = env ~= nil and env.weather or nil
    if w == nil then
        return nil
    end
    local panel = {kind = "weather", rows = {}, problems = {}}
    panel.now = StorageMonitor.weatherInfo(call(w, "getCurrentWeatherType"))
    local current = w.forecast ~= nil and call(w.forecast, "getCurrentWeather") or nil
    panel.temperature = type(current) == "table" and tonumber(current.temperature) or tonumber(call(w, "getCurrentTemperature"))
    local minT, maxT = call(w, "getCurrentMinMaxTemperatures")
    panel.minT, panel.maxT = tonumber(minT), tonumber(maxT)
    panel.trend = tonumber(call(w, "getCurrentTemperatureTrend"))
    local rain = tonumber(call(w, "getRainFallScale")) or 0
    local snow = tonumber(call(w, "getSnowFallScale")) or 0
    local hail = tonumber(call(w, "getHailFallScale")) or 0
    panel.raining = call(w, "getIsRaining") == true or rain > 0.01
    panel.snowing = snow > 0.01
    panel.hail = hail > 0.01
    local since = tonumber(call(w, "getTimeSinceLastRain"))       -- in-game minutes, when the game has it
    panel.wet = panel.raining or panel.hail or (since ~= nil and since < 30)

    local today = env.currentMonotonicDay or env.currentDay or 0
    local function typeAt(dayTime, day)
        if env.getDayAndDayTime ~= nil then
            local t, d = env:getDayAndDayTime(dayTime, day)
            if t ~= nil and d ~= nil then
                dayTime, day = t, d
            end
        else
            while dayTime >= 86400000 do
                dayTime, day = dayTime - 86400000, day + 1
            end
        end
        return StorageMonitor.weatherInfo(call(w, "getNextWeatherType", dayTime, day))
    end
    local nowTime = tonumber(env.dayTime) or 0
    -- when the weather changes next (within a day)
    -- and how many dry hours are left (the harvest window; 24 = at least a day)
    panel.dryFor = (panel.raining or panel.snowing or panel.hail) and 0 or 24
    if panel.now ~= nil then
        for h = 1, 24 do
            local info = typeAt(nowTime + h * 3600000, today)
            if info ~= nil and info.id ~= panel.now.id and panel.change == nil then
                panel.change = {hours = h, info = info}
            end
            if info ~= nil and StorageMonitor.WET_WEATHER[info.id] and panel.dryFor > h then
                panel.dryFor = h
            end
            if panel.change ~= nil and panel.dryFor <= h then
                break
            end
        end
    end
    -- the next hours, then the next days at noon
    local hour = tonumber(env.currentHour) or math.floor(nowTime / 3600000)
    for i, h in ipairs({2, 4, 6, 9, 12}) do
        local info = typeAt(nowTime + h * 3600000, today)
        if info ~= nil then
            table.insert(panel.rows, {id = "h" .. h, rank = i, title = string.format("%02d:00", (hour + h) % 24),
                sub = string.format(T("storageMonitor_inHours", "in %d h"), h), subColor = "dim",
                swatch = info.color, value = info.title, valueColor = info.color})
        end
    end
    for d = 1, 4 do
        local info = typeAt(12 * 3600000, today + d)
        if info ~= nil then
            table.insert(panel.rows, {id = "d" .. d, rank = 10 + d,
                title = d == 1 and T("storageMonitor_tomorrow", "Tomorrow") or string.format(T("storageMonitor_inDays", "In %d days"), d),
                swatch = info.color, value = info.title, valueColor = info.color})
        end
    end
    -- alerts: rain, snow or hail coming soon while it is dry; hail or a storm now
    if panel.hail or (panel.now ~= nil and (panel.now.id == "TWISTER" or panel.now.id == "STORM" or panel.now.id == "HAIL")) then
        table.insert(panel.problems, {id = "storm", text = panel.now ~= nil and panel.now.title or T("storageMonitor_wHail", "Hail")})
    elseif not panel.raining and panel.change ~= nil and panel.change.hours <= 3 and StorageMonitor.WET_WEATHER[panel.change.info.id] then
        table.insert(panel.problems, {id = "wetSoon", text = string.format(T("storageMonitor_alertWeatherSoon", "%s in %d h"),
            panel.change.info.title, panel.change.hours)})
    end
    return panel
end

-- the fill level of a vehicle's fuel (diesel, electric charge or methane) as 0..1, or nil
local function fuelRatio(vehicle)
    if vehicle.getConsumerFillUnitIndex == nil then
        return nil
    end
    for _, name in ipairs({"DIESEL", "ELECTRICCHARGE", "METHANE"}) do
        local fillType = FillType ~= nil and FillType[name] or nil
        if fillType == nil and g_fillTypeManager ~= nil then
            fillType = call(g_fillTypeManager, "getFillTypeIndexByName", name)
        end
        local unit = fillType ~= nil and call(vehicle, "getConsumerFillUnitIndex", fillType) or nil
        if unit ~= nil then
            local level = tonumber(call(vehicle, "getFillUnitFillLevel", unit)) or 0
            local capacity = tonumber(call(vehicle, "getFillUnitCapacity", unit)) or 0
            if capacity > 0 then
                return clamp01(level / capacity)
            end
        end
    end
    return nil
end

StorageMonitor.FLEET_SKIP = {pallet = true, treeSaplingPallet = true, bigBag = true, locomotive = true,
    conveyorBelt = true, pickupConveyorBelt = true}
StorageMonitor.FUEL_LOW = 0.15
StorageMonitor.DAMAGE_REPAIR = 0.3

-- a vehicle of the farm that is driven (not an implement, pallet, train, horse or a contract's loan)
function StorageMonitor.isFleetVehicle(v, farmId)
    if type(v) ~= "table" or v.isDeleted or v.isDeleting or v.spec_attachable ~= nil or v.spec_rideable ~= nil
        or StorageMonitor.FLEET_SKIP[v.typeName] or v.getIsControlled == nil then
        return false
    end
    if call(v, "getOwnerFarmId") ~= farmId then
        return false
    end
    local states = VehiclePropertyState
    if states ~= nil and v.propertyState ~= nil and v.propertyState ~= states.OWNED and v.propertyState ~= states.LEASED then
        return false
    end
    if v.getShowInVehiclesOverview ~= nil and call(v, "getShowInVehiclesOverview") == false then
        return false
    end
    return true
end

--- The farm's vehicles: helpers at work, in use, fuel and damage; the ones that need attention first.
function StorageMonitor.readFleet(farmId)
    local T = StorageMonitor.getText
    local panel = {kind = "fleet", rows = {}, problems = {}, count = 0, helpers = 0, inUse = 0, lowFuel = 0, repair = 0, leased = 0}
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    for _, v in ipairs(system ~= nil and system.vehicles or {}) do
        if StorageMonitor.isFleetVehicle(v, farmId) then
            local name = tostring(call(v, "getFullName") or v.typeName or "?")
            local fuel = fuelRatio(v)
            local damage = clamp01(call(v, "getDamageAmount"))
            local ai = call(v, "getIsAIActive") == true
            local driven = call(v, "getIsControlled") == true
            local engine = call(v, "getIsMotorStarted") == true
            local status, statusColor, rank
            if ai then
                status, statusColor, rank = T("storageMonitor_helperWorking", "Helper working"), "accent", 1
                panel.helpers = panel.helpers + 1
            elseif driven then
                status, statusColor, rank = T("storageMonitor_inUse", "In use"), "ok", 3
            elseif engine then
                status, statusColor, rank = T("storageMonitor_engineOn", "Engine on"), "ok", 3
            else
                status, statusColor, rank = T("storageMonitor_parked", "Parked"), "dim", 4
            end
            if ai or driven then
                panel.inUse = panel.inUse + 1
            end
            local lowFuel = fuel ~= nil and fuel < StorageMonitor.FUEL_LOW
            if lowFuel then
                panel.lowFuel = panel.lowFuel + 1
                rank = ai and 0 or math.min(rank, 2)
                if ai then          -- a helper stops when the tank is empty
                    table.insert(panel.problems, {id = "fuel_" .. name,
                        text = string.format(T("storageMonitor_alertFuel", "%s: fuel %d%%"), name, math.floor(fuel * 100 + 0.5))})
                end
            end
            if damage >= StorageMonitor.DAMAGE_REPAIR then
                panel.repair = panel.repair + 1
                if damage >= 0.5 then
                    rank = math.min(rank, 2)
                end
                if damage >= 0.7 then
                    table.insert(panel.problems, {id = "damage_" .. name,
                        text = string.format(T("storageMonitor_alertDamage", "%s: damage %d%%"), name, math.floor(damage * 100 + 0.5))})
                end
            end
            if VehiclePropertyState ~= nil and v.propertyState == VehiclePropertyState.LEASED then
                panel.leased = panel.leased + 1
            end
            local sub, subColor = status, statusColor
            if damage >= 0.2 then
                sub = string.format("%s, %s", status, string.format(T("storageMonitor_damage", "damage %d%%"), math.floor(damage * 100 + 0.5)))
                subColor = damage >= 0.5 and "full" or (damage >= StorageMonitor.DAMAGE_REPAIR and "warn" or statusColor)
            end
            local fuelColor = fuel == nil and "dim" or (fuel < StorageMonitor.FUEL_LOW and "full" or (fuel < 0.3 and "warn" or "ok"))
            table.insert(panel.rows, {id = "v" .. tostring(v.id or v.rootNode or name), rank = rank, title = name,
                swatch = statusColor, sub = sub, subColor = subColor,
                value = fuel ~= nil and string.format("%d%%", math.floor(fuel * 100 + 0.5)) or "--", valueColor = fuelColor,
                ratio = fuel, ratioColor = fuelColor})
            panel.count = panel.count + 1
        end
    end
    sortRows(panel.rows)
    return panel
end

--- The farm's running contracts: what, where, how far, the reward.
function StorageMonitor.readContracts(farmId)
    local T = StorageMonitor.getText
    local panel = {kind = "contracts", rows = {}, problems = {}, count = 0, reward = 0, almostDone = 0, completion = 0}
    local list = call(g_missionManager, "getMissionsByFarmId", farmId) or {}
    local running = (MissionStatus ~= nil and MissionStatus.RUNNING)
        or (AbstractMission ~= nil and AbstractMission.STATUS_RUNNING) or nil
    for _, m in pairs(list) do
        if type(m) == "table" and (running == nil or m.status == running) and call(m, "isTimedOut") ~= true then
            local title = call(m, "getTitle") or (m.type ~= nil and m.type.name) or "?"
            local location = call(m, "getLocation")
            if (location == nil or location == "") and m.field ~= nil then
                local id = call(m.field, "getId") or m.field.fieldId
                location = id ~= nil and string.format(T("storageMonitor_fieldNo", "Field %s"), tostring(id)) or nil
            end
            local completion = clamp01(call(m, "getCompletion"))
            local reward = tonumber(call(m, "getReward")) or 0
            local sub = StorageMonitor.formatMoney(reward)
            if location ~= nil and location ~= "" then
                sub = string.format("%s  %s", tostring(location), sub)
            end
            local done = completion >= 0.9
            local row = {id = "m" .. tostring(m.id or m.activeMissionId or title), rank = 1, order = -completion,
                title = tostring(title), swatch = done and "ok" or "accent", sub = sub, subColor = "dim",
                value = string.format("%d%%", math.floor(completion * 100)), valueColor = done and "ok" or "text",
                ratio = completion, ratioColor = done and "ok" or "accent"}
            -- the crop or product of the contract (harvest, baling, transport)
            local fillType = tonumber(m.fillTypeIndex) or tonumber(m.fillType)
            table.insert(panel.rows, withProductIcon(row, fillType))
            panel.count = panel.count + 1
            panel.reward = panel.reward + reward
            panel.completion = panel.completion + completion
            if done then
                panel.almostDone = panel.almostDone + 1
            end
        end
    end
    if panel.count > 0 then
        panel.completion = panel.completion / panel.count
    end
    sortRows(panel.rows)
    return panel
end

--- Every animal pen of the farm on one screen: animals, the supplies running lowest, how long the food lasts.
function StorageMonitor.readAllPens(pens)
    local T = StorageMonitor.getText
    local panel = {kind = "allPens", rows = {}, problems = {}, count = 0, animals = 0, maxAnimals = 0, lowFood = 0,
                   lowSupply = 0, tanksFull = 0}
    for i, pen in ipairs(pens) do
        local p = StorageMonitor.buildPanel({kind = "husbandry", placeable = pen.placeable})
        if p ~= nil then
            local parts, lowest, worst = {}, nil, nil     -- parts: what needs care first (full tanks, then the lowest)
            local fullTank = false
            for _, cond in ipairs(p.conditions) do
                local pct = math.floor(cond.ratio * 100 + 0.5)
                if cond.isFood or cond.supply then
                    table.insert(parts, {order = cond.ratio, text = string.format("%s %d%%", cond.title, pct)})
                    if lowest == nil or cond.ratio < lowest then
                        lowest, worst = cond.ratio, cond
                    end
                    if cond.ratio < StorageMonitor.ALERT_LOW then
                        if cond.isFood then
                            panel.lowFood = panel.lowFood + 1
                        else
                            panel.lowSupply = panel.lowSupply + 1
                        end
                        table.insert(panel.problems, {id = "low_" .. i .. "_" .. cond.title,
                            text = string.format("%s: %s", pen.name, string.format(T("storageMonitor_alertLow", "Low %s: %d%%"), cond.title, pct))})
                    end
                elseif cond.inverted and cond.ratio >= 0.95 then
                    fullTank = true
                    table.insert(parts, {order = -1, text = string.format(T("storageMonitor_alertItemFull", "%s is full"), cond.title)})
                    table.insert(panel.problems, {id = "full_" .. i .. "_" .. cond.title,
                        text = string.format("%s: %s", pen.name, string.format(T("storageMonitor_alertItemFull", "%s is full"), cond.title))})
                end
            end
            if fullTank then
                panel.tanksFull = panel.tanksFull + 1
            end
            table.sort(parts, function(a, b)
                if a.order ~= b.order then
                    return a.order < b.order
                end
                return a.text < b.text
            end)
            for k, part in ipairs(parts) do
                parts[k] = part.text
            end
            if p.food ~= nil and p.foodPerHour ~= nil and p.foodPerHour > 0 then
                local hours = p.food / p.foodPerHour
                if panel.foodHours == nil or hours < panel.foodHours then
                    panel.foodHours = hours
                end
            end
            panel.animals = panel.animals + p.animals
            panel.maxAnimals = panel.maxAnimals + p.maxAnimals
            panel.count = panel.count + 1
            local color = "ok"
            if lowest ~= nil and lowest < 0.2 then
                color = "full"
            elseif lowest ~= nil and lowest < 0.5 then
                color = "warn"
            end
            -- the pen's product (milk, eggs, wool) for its icon; manure only counts when there is nothing else
            local product, manure = nil, nil
            local spec = pen.placeable.spec_husbandry
            local levels = spec ~= nil and spec.storage ~= nil and call(spec.storage, "getFillLevels") or nil
            for fillType in pairs(type(levels) == "table" and levels or {}) do
                local ftInfo = fillTypeInfo(fillType)
                local name = ftInfo ~= nil and ftInfo.name or nil
                if name ~= nil and StorageMonitor.ANIMAL_OUTPUTS[name] then
                    if name == "MANURE" or name == "LIQUIDMANURE" or name == "SLURRY" then
                        manure = manure or fillType
                    elseif product == nil or fillType < product then
                        product = fillType
                    end
                end
            end
            table.insert(panel.rows, withProductIcon({id = "pen" .. i, rank = 1, order = lowest or 1, title = tostring(pen.name),
                swatch = color, sub = table.concat(parts, "  "), subColor = (fullTank or color == "full") and "full" or "dim",
                value = string.format("%d/%d", p.animals, p.maxAnimals),
                valueColor = (p.maxAnimals > 0 and p.animals >= p.maxAnimals) and "warn" or "text",
                ratio = lowest, ratioColor = color}, product or manure))
            if worst ~= nil then
                panel.rows[#panel.rows].worst = worst.title
            end
        end
    end
    sortRows(panel.rows)
    return panel
end

--- Every production of the farm on one screen: lines running, missing inputs, full outputs, no water.
function StorageMonitor.readAllProductions(productions)
    local T = StorageMonitor.getText
    local panel = {kind = "allProductions", rows = {}, problems = {}, count = 0, lines = 0, running = 0, missing = 0,
                   full = 0, noWater = 0, idle = 0}
    for i, prod in ipairs(productions) do
        local p = StorageMonitor.buildPanel({kind = "production", pp = prod.pp, greenhouse = prod.greenhouse})
        if p ~= nil then
            local n = #p.lines
            local lineMissing, lineFull = false, false
            for _, line in ipairs(p.lines) do
                lineMissing = lineMissing or line.state == "missing"
                lineFull = lineFull or line.state == "full"
            end
            -- the inputs that are empty
            local empty = {}
            local storage = prod.pp.storage
            local levels = storage ~= nil and call(storage, "getFillLevels") or nil
            if type(levels) == "table" then
                for fillType in pairs(prod.pp.inputFillTypeIds or {}) do
                    if (tonumber(levels[fillType]) or 0) < StorageMonitor.MIN_LEVEL then
                        local ftInfo = fillTypeInfo(fillType)
                        table.insert(empty, ftInfo ~= nil and tostring(ftInfo.title) or tostring(fillType))
                    end
                end
                table.sort(empty)
            end
            local sub, subColor, rank = nil, "dim", 3
            local rowId = "prod" .. i
            if p.noWater then
                sub, subColor, rank = T("storageMonitor_alertNoWater", "No water"), "full", 1
                panel.noWater = panel.noWater + 1
            elseif lineMissing then
                sub = #empty > 0 and string.format(T("storageMonitor_missingList", "Missing: %s"), table.concat(empty, ", "))
                    or T("storageMonitor_line_missing", "Missing inputs")
                subColor, rank = "full", 1
                panel.missing = panel.missing + 1
            elseif lineFull then
                sub, subColor, rank = T("storageMonitor_line_full", "Output full"), "full", 1
                panel.full = panel.full + 1
            elseif p.running > 0 then
                sub, subColor, rank = T("storageMonitor_line_running", "Running"), "ok", 2
            else
                sub = T("storageMonitor_line_off", "Off")
            end
            if subColor == "full" then
                table.insert(panel.problems, {id = rowId .. "_" .. sub, text = string.format("%s: %s", prod.name, sub)})
            end
            if p.running == 0 then
                panel.idle = panel.idle + 1
            end
            panel.lines = panel.lines + n
            panel.running = panel.running + p.running
            panel.count = panel.count + 1
            local color = (n > 0 and p.running == n) and "ok" or (p.running > 0 and "warn" or (rank == 1 and "full" or "dim"))
            -- the production's main product for its icon
            local product = tonumber(prod.pp.primaryProductFillType) or firstKey(prod.pp.outputFillTypeIds)
            table.insert(panel.rows, withProductIcon({id = rowId, rank = rank, title = tostring(prod.name), swatch = color,
                sub = sub, subColor = subColor, value = string.format("%d/%d", p.running, n), valueColor = color,
                ratio = n > 0 and p.running / n or nil, ratioColor = color}, product))
        end
    end
    sortRows(panel.rows)
    return panel
end

local function entryFillType(entry)
    return tonumber(entry.type or entry.fillType or entry.fillTypeIndex)
end

--- What the farm's productions need: a row for every input of every production, the ones to deliver first
-- on top. Red (and blinking): empty while a switched-on line uses it; amber: low (under PROD_LOW of its room
-- or out within PROD_LOW_HOURS); green: enough; grey: no line that is switched on uses it. Each row says how
-- much it takes to fill up, how long the stock lasts and how much of the product the farm's silos hold.
-- How fast an input goes is the lines' nominal rate (cycles per hour x amount per cycle, shared between the
-- switched-on lines), so it is an estimate.
function StorageMonitor.readProdNeeds(productions, silos)
    local T = StorageMonitor.getText
    local panel = {kind = "prodNeeds", rows = {}, problems = {}, count = 0, empty = 0, low = 0, productions = 0,
                   toFill = 0}
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local timeAdjustment = (env ~= nil and tonumber(env.timeAdjustment)) or 1
    -- how much of each product the farm's silos hold (a storage seen once)
    local inSilos, seen = {}, {}
    for _, storage in ipairs(silos or {}) do
        if not seen[storage] then
            seen[storage] = true
            local levels = call(storage, "getFillLevels")
            if type(levels) == "table" then
                for ft, level in pairs(levels) do
                    inSilos[ft] = (inSilos[ft] or 0) + (tonumber(level) or 0)
                end
            end
        end
    end
    local firstOut = nil
    for i, prod in ipairs(productions or {}) do
        local pp = prod.pp
        local storage = pp ~= nil and pp.storage or nil
        local levels = storage ~= nil and call(storage, "getFillLevels") or nil
        if type(levels) == "table" then
            panel.productions = panel.productions + 1
            -- what the switched-on lines use per in-game hour
            local active, nActive = {}, 0
            for _, line in ipairs(pp.activeProductions or {}) do
                active[line] = true
                nActive = nActive + 1
            end
            local share = (pp.sharedThroughputCapacity ~= false and nActive > 1) and 1 / nActive or 1
            local perHour, used = {}, {}
            for _, line in ipairs(pp.productions or {}) do
                if active[line] then
                    local cycles = tonumber(line.cyclesPerHour) or ((tonumber(line.cyclesPerMinute) or 0) * 60)
                    for _, entry in ipairs(line.inputs or {}) do
                        local ft = entryFillType(entry)
                        if ft ~= nil then
                            used[ft] = true
                            perHour[ft] = (perHour[ft] or 0) + (tonumber(entry.amount) or 0) * cycles * share * timeAdjustment
                        end
                    end
                end
            end
            local inputs = {}
            for ft in pairs(pp.inputFillTypeIds or {}) do
                if type(ft) == "number" then
                    table.insert(inputs, ft)
                end
            end
            table.sort(inputs)
            for _, ft in ipairs(inputs) do
                local info = fillTypeInfo(ft)
                local title = info ~= nil and tostring(info.title) or tostring(ft)
                local level = math.max(0, tonumber(levels[ft]) or 0)
                local cap = tonumber(call(storage, "getCapacity", ft))
                if cap == nil and type(storage.capacities) == "table" then
                    cap = tonumber(storage.capacities[ft])
                end
                if cap == nil then
                    cap = tonumber(storage.capacity)
                end
                local ratio = (cap ~= nil and cap > 0) and clamp01(level / cap) or nil
                local room = (cap ~= nil and cap > level) and cap - level or 0
                local rate = perHour[ft] or 0
                local empty = level < StorageMonitor.MIN_LEVEL
                local hours = (used[ft] and rate > 0 and not empty) and level / rate or nil
                local state, color, rank
                if not used[ft] then
                    state, color, rank = T("storageMonitor_needUnused", "No line uses it now"), "dim", 4
                elseif empty then
                    state, color, rank = T("storageMonitor_needEmpty", "Empty"), "full", 1
                    panel.empty = panel.empty + 1
                elseif (ratio ~= nil and ratio < StorageMonitor.PROD_LOW) or (hours ~= nil and hours < StorageMonitor.PROD_LOW_HOURS) then
                    state, color, rank = T("storageMonitor_needLow", "Low"), "warn", 2
                    panel.low = panel.low + 1
                else
                    state, color, rank = T("storageMonitor_needOk", "Enough"), "ok", 3
                end
                local parts = {state}
                if hours ~= nil then
                    table.insert(parts, string.format(T("storageMonitor_needLasts", "lasts %s"), StorageMonitor.formatDuration(hours)))
                end
                if used[ft] and (inSilos[ft] or 0) >= StorageMonitor.MIN_LEVEL then
                    table.insert(parts, string.format(T("storageMonitor_needInSilos", "silos: %s"), StorageMonitor.formatVolume(inSilos[ft])))
                end
                local rowTitle = string.format("%s: %s", tostring(prod.name), title)
                if rank <= 2 then
                    table.insert(panel.problems, {id = "need" .. i .. "_" .. ft .. "_" .. rank,
                        text = string.format("%s - %s", rowTitle, state)})
                    local out = hours or 0          -- empty: out now
                    if firstOut == nil or out < firstOut.hours then
                        firstOut = {hours = out, title = rowTitle}
                    end
                end
                if used[ft] then
                    panel.toFill = panel.toFill + room
                end
                panel.count = panel.count + 1
                table.insert(panel.rows, withProductIcon({id = "need" .. i .. "_" .. ft, rank = rank,
                    order = hours or (ratio or 0) * 1000, title = rowTitle, swatch = color,
                    titleColor = rank <= 2 and color or nil, flag = rank <= 2 and color or nil, blink = rank == 1,
                    sub = table.concat(parts, ", "), subColor = rank <= 2 and color or "dim",
                    value = room > 0 and StorageMonitor.formatVolume(room) or T("storageMonitor_needFull", "full"),
                    valueColor = rank <= 2 and color or "text", ratio = ratio, ratioColor = color}, ft))
            end
        end
    end
    panel.first = firstOut ~= nil and firstOut.title or nil
    sortRows(panel.rows)
    return panel
end

--- The month ahead (0 = now) in which a fill type sells best on the game's seasonal curve, and that price as a
-- factor of today's: bestIn, factor (nil without a curve). Looks a year ahead.
function StorageMonitor.bestMonth(fillTypeIndex)
    local fillType = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex) or nil
    local factors = fillType ~= nil and fillType.economy ~= nil and fillType.economy.factors or nil
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    local period = env ~= nil and tonumber(env.currentPeriod) or nil
    if type(factors) ~= "table" or period == nil then
        return nil
    end
    local periods = (Environment ~= nil and Environment.PERIODS_IN_YEAR) or 12
    local now = tonumber(factors[period])
    if now == nil or now <= 0 then
        return nil
    end
    local bestIn, bestFactor = 0, now
    for k = 1, periods - 1 do
        local f = tonumber(factors[(period + k - 1) % periods + 1])
        if f ~= nil and f > bestFactor + 1e-6 then
            bestIn, bestFactor = k, f
        end
    end
    return bestIn, bestFactor / now
end

--- When to sell what the farm's silos hold: for every product the best month ahead on the seasonal price curve,
-- what the stock is worth now and how much more then.
function StorageMonitor.readSellPlan(sources)
    local T = StorageMonitor.getText
    local panel = {kind = "sellPlan", rows = {}, problems = {}, count = 0, valueNow = 0, valueBest = 0, hold = 0, sellNow = 0}
    local snapshot = StorageMonitor.buildSnapshot(sources or {}, nil, fillTypeInfo)
    for _, item in ipairs(snapshot.items) do
        local best = StorageMonitor.bestPrice(item.fillType)
        if best ~= nil then
            local valueNow = item.level * best.price
            local bestIn, factor = StorageMonitor.bestMonth(item.fillType)
            factor = factor or 1
            local gain = valueNow * (factor - 1)
            local row = {id = "sell" .. tostring(item.fillType), title = tostring(item.title), icon = item.icon,
                swatch = item.color, iconColor = item.color, ratio = 1 / factor}
            if bestIn == nil then
                row.rank, row.order = 3, -valueNow
                row.sub, row.subColor = T("storageMonitor_noSeason", "No seasonal prices"), "dim"
                row.value, row.valueColor, row.ratioColor = StorageMonitor.formatMoney(valueNow), "text", "dim"
                panel.sellNow = panel.sellNow + 1
            elseif bestIn == 0 or factor < 1.01 then
                row.rank, row.order = 1, -valueNow
                row.sub, row.subColor = T("storageMonitor_sellNow", "Sell now: the best month"), "ok"
                row.value, row.valueColor, row.ratioColor = StorageMonitor.formatMoney(valueNow), "ok", "ok"
                panel.sellNow = panel.sellNow + 1
                gain = 0
            else
                row.rank, row.order = 2, -gain
                local pct = math.floor((factor - 1) * 100 + 0.5)
                row.sub = bestIn == 1 and string.format(T("storageMonitor_bestNext", "Best next month: +%d%%"), pct)
                    or string.format(T("storageMonitor_bestIn", "Best in %d months: +%d%%"), bestIn, pct)
                row.subColor = "accent"
                row.value, row.valueColor, row.ratioColor = "+" .. StorageMonitor.formatMoney(gain), "accent", "warn"
                panel.hold = panel.hold + 1
            end
            panel.valueNow = panel.valueNow + valueNow
            panel.valueBest = panel.valueBest + valueNow + gain
            panel.count = panel.count + 1
            table.insert(panel.rows, row)
        end
    end
    sortRows(panel.rows)
    return panel
end

-- a price per litre for a fill type: the best selling price, else the game's base price (what an input is
-- worth when you sell it instead), 0 when nobody pays for it
function StorageMonitor.unitPrice(fillTypeIndex)
    local best = StorageMonitor.bestPrice(fillTypeIndex)
    if best ~= nil then
        return best.price
    end
    local fillType = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex) or nil
    local base = fillType ~= nil and tonumber(fillType.pricePerLiter) or nil
    if base == nil then
        return 0
    end
    local economy = g_currentMission ~= nil and g_currentMission.economyManager or nil
    return base * (tonumber(call(economy, "getPriceMultiplier")) or 1)
end

--- What each running production line earns per in-game hour: its outputs at the best price, less its inputs
-- (at what they would sell for) and its running cost. Lines missing inputs count, marked as waiting.
function StorageMonitor.readProfit(productions)
    local T = StorageMonitor.getText
    local panel = {kind = "profit", rows = {}, problems = {}, count = 0, perHour = 0, losing = 0, waiting = 0}
    local status = ProductionPoint ~= nil and ProductionPoint.PROD_STATUS or {}
    for i, prod in ipairs(productions) do
        local pp = prod.pp
        local active = {}
        for _, line in ipairs(pp.activeProductions or {}) do
            active[line] = true
        end
        for j, line in ipairs(pp.productions or {}) do
            if active[line] then
                local cycles = tonumber(line.cyclesPerHour) or ((tonumber(line.cyclesPerMinute) or 0) * 60)
                local valueIn, valueOut, mainOutput = 0, 0, nil
                for _, entry in ipairs(line.inputs or {}) do
                    local ft = entryFillType(entry)
                    if ft ~= nil then
                        valueIn = valueIn + (tonumber(entry.amount) or 0) * cycles * StorageMonitor.unitPrice(ft)
                    end
                end
                for _, entry in ipairs(line.outputs or {}) do
                    local ft = entryFillType(entry)
                    if ft ~= nil then
                        mainOutput = mainOutput or ft
                        valueOut = valueOut + (tonumber(entry.amount) or 0) * cycles * StorageMonitor.unitPrice(ft)
                    end
                end
                local cost = tonumber(line.costsPerActiveHour) or ((tonumber(line.costsPerActiveMinute) or 0) * 60)
                local profit = valueOut - valueIn - cost
                local waiting = line.status == status.MISSING_INPUTS
                local name = line.name
                if (name == nil or name == "") and mainOutput ~= nil then
                    local info = fillTypeInfo(mainOutput)
                    name = info ~= nil and info.title or nil
                end
                local sub = string.format(T("storageMonitor_profitParts", "in %s  out %s  upkeep %s"),
                    StorageMonitor.formatMoney(valueIn), StorageMonitor.formatMoney(valueOut), StorageMonitor.formatMoney(cost))
                if waiting then
                    sub = T("storageMonitor_line_missing", "Missing inputs") .. ", " .. sub
                    panel.waiting = panel.waiting + 1
                end
                local color = profit >= 0 and "ok" or "full"
                table.insert(panel.rows, withProductIcon({id = "pl" .. i .. "_" .. j, rank = 1, order = -profit,
                    title = string.format("%s: %s", tostring(prod.name), tostring(name or j)), swatch = color,
                    sub = sub, subColor = waiting and "warn" or "dim",
                    value = (profit >= 0 and "+" or "") .. StorageMonitor.formatMoney(profit) .. "/h", valueColor = color,
                    ratio = valueOut > 0 and math.max(0, math.min(1, profit / valueOut)) or 0, ratioColor = color}, mainOutput))
                panel.count = panel.count + 1
                panel.perHour = panel.perHour + profit
                if profit < 0 then
                    panel.losing = panel.losing + 1
                end
                if panel.best == nil or profit > panel.best.profit then
                    panel.best = {profit = profit, name = tostring(name or prod.name)}
                end
            end
        end
    end
    sortRows(panel.rows)
    return panel
end

local function fieldLabel(field)
    if field == nil then
        return nil
    end
    local id = call(field, "getId") or field.fieldId or (field.farmland ~= nil and field.farmland.id) or nil
    return id ~= nil and string.format(StorageMonitor.getText("storageMonitor_fieldNo", "Field %s"), tostring(id)) or nil
end

--- Contracts nobody has taken yet: the best reward per hectare first, and how many more the farm may take.
function StorageMonitor.readOpenContracts(farmId)
    local T = StorageMonitor.getText
    local panel = {kind = "openContracts", rows = {}, problems = {}, count = 0, total = 0, bestReward = 0}
    local created = MissionStatus ~= nil and MissionStatus.CREATED or nil
    for i, m in pairs(g_missionManager ~= nil and g_missionManager.missions or {}) do
        if type(m) == "table" and m.farmId == nil and (created == nil or m.status == created) then
            local title = call(m, "getTitle") or m.title or (m.type ~= nil and m.type.name) or "?"
            local reward = tonumber(call(m, "getReward")) or 0
            local field = m.field
            local ha = field ~= nil and (tonumber(call(field, "getAreaHa")) or tonumber(field.areaHa)) or nil
            local perHa = (ha ~= nil and ha > 0) and reward / ha or nil
            local parts = {}
            local where = fieldLabel(field) or call(m, "getLocation")
            if where ~= nil and where ~= "" then
                table.insert(parts, tostring(where))
            end
            if ha ~= nil then
                table.insert(parts, StorageMonitor.formatArea(ha))
            end
            if perHa ~= nil then
                table.insert(parts, StorageMonitor.formatMoney(reward))
            end
            table.insert(panel.rows, withProductIcon({id = "oc" .. tostring(m.id or i), rank = perHa ~= nil and 1 or 2,
                order = -(perHa or reward), title = tostring(title), swatch = "accent", sub = table.concat(parts, "  "), subColor = "dim",
                value = perHa ~= nil and string.format(T("storageMonitor_perHa", "%s/ha"), StorageMonitor.formatMoney(perHa))
                    or StorageMonitor.formatMoney(reward), valueColor = "ok"}, tonumber(m.fillTypeIndex) or tonumber(m.fillType)))
            panel.count = panel.count + 1
            panel.total = panel.total + reward
            panel.bestReward = math.max(panel.bestReward, reward)
            if perHa ~= nil and (panel.bestPerHa == nil or perHa > panel.bestPerHa) then
                panel.bestPerHa = perHa
            end
        end
    end
    -- how many the farm runs, of how many it may
    local running = 0
    local runningStatus = MissionStatus ~= nil and MissionStatus.RUNNING or nil
    for _, m in pairs(call(g_missionManager, "getMissionsByFarmId", farmId) or {}) do
        if type(m) == "table" and (runningStatus == nil or m.status == runningStatus) then
            running = running + 1
        end
    end
    panel.running = running
    panel.max = MissionManager ~= nil and tonumber(MissionManager.MAX_MISSIONS_PER_FARM) or nil
    panel.limitReached = call(g_missionManager, "hasFarmReachedMissionLimit", farmId) == true
    sortRows(panel.rows)
    return panel
end

-- a farm's colour as {r, g, b}, or nil
local function farmColor(farm)
    local c = call(farm, "getColor")
    if type(c) ~= "table" and Farm ~= nil and type(Farm.COLORS) == "table" and farm.color ~= nil then
        c = Farm.COLORS[farm.color]
    end
    if type(c) == "table" and tonumber(c[1]) ~= nil then
        return {tonumber(c[1]), tonumber(c[2]) or 0, tonumber(c[3]) or 0}
    end
    return nil
end

--- Every farm on the server side by side: balance (when the game shares it), fields, vehicles and animals; the
-- richest first, the player's own farm marked.
function StorageMonitor.readFarms(myFarmId)
    local T = StorageMonitor.getText
    local panel = {kind = "farms", rows = {}, problems = {}, count = 0}
    local spectator = FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID or 0
    -- fields and hectares per farm
    local fields, hectares = {}, {}
    local farmlands = call(g_farmlandManager, "getFarmlands") or (g_farmlandManager ~= nil and g_farmlandManager.farmlands) or {}
    for _, farmland in pairs(farmlands) do
        local owner = type(farmland) == "table" and call(g_farmlandManager, "getFarmlandOwner", farmland.id) or nil
        if owner ~= nil and farmland.field ~= nil then
            fields[owner] = (fields[owner] or 0) + 1
            hectares[owner] = (hectares[owner] or 0) + (tonumber(farmland.field.areaHa) or 0)
        end
    end
    -- vehicles and animals per farm
    local vehicles, animals = {}, {}
    local system = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    for _, v in ipairs(system ~= nil and system.vehicles or {}) do
        local owner = call(v, "getOwnerFarmId")
        if owner ~= nil and StorageMonitor.isFleetVehicle(v, owner) then
            vehicles[owner] = (vehicles[owner] or 0) + 1
        end
    end
    local placeables = g_currentMission ~= nil and g_currentMission.placeableSystem ~= nil and g_currentMission.placeableSystem.placeables or {}
    for _, p in ipairs(placeables) do
        if p.getNumOfAnimals ~= nil then
            local owner = call(p, "getOwnerFarmId")
            if owner ~= nil then
                animals[owner] = (animals[owner] or 0) + (tonumber(call(p, "getNumOfAnimals")) or 0)
            end
        end
    end
    local richest = 0
    for _, farm in pairs(call(g_farmManager, "getFarms") or {}) do
        local id = type(farm) == "table" and farm.farmId or nil
        if id ~= nil and id ~= spectator then
            local money = tonumber(call(farm, "getBalance")) or tonumber(farm.money)
            if money ~= nil then
                richest = math.max(richest, money)
            end
            local mine = id == myFarmId           -- the board's farm: its place
            local you = id == realPlayerFarmId()     -- the player looking at it
            local title = tostring(farm.name or ("Farm " .. id))
            if you then
                title = string.format(T("storageMonitor_myFarm", "%s (you)"), title)
            end
            if mine then
                panel.mine = {money = money, name = tostring(farm.name or id)}
            end
            table.insert(panel.rows, {id = "farm" .. id, rank = 1, order = -(money or -math.huge), title = title,
                swatch = farmColor(farm) or (mine and "accent" or "dim"),
                sub = string.format(T("storageMonitor_farmParts", "%d fields (%s)  %d vehicles  %d animals"), fields[id] or 0,
                    StorageMonitor.formatArea(hectares[id] or 0), vehicles[id] or 0, animals[id] or 0),
                subColor = mine and "text" or "dim",
                value = money ~= nil and StorageMonitor.formatMoney(money) or "--", valueColor = mine and "accent" or "text",
                money = money, loan = tonumber(farm.loan)})
            panel.count = panel.count + 1
        end
    end
    sortRows(panel.rows)
    for i, row in ipairs(panel.rows) do
        if row.money ~= nil and richest > 0 then
            row.ratio, row.ratioColor = math.max(0, row.money) / richest, row.valueColor
        end
        if row.id == "farm" .. tostring(myFarmId) then
            panel.place = i
        end
    end
    panel.richest = panel.rows[1]
    return panel
end

-- the outline of a field as a flat list {x1, z1, x2, z2, ...} (the map's field border), or nil
local function fieldOutline(field)
    local polygon = call(field, "getDensityMapPolygon")
    local list = polygon ~= nil and call(polygon, "getVerticesList") or nil
    if type(list) == "table" and #list >= 6 then
        return list
    end
    return nil
end

local function insidePolygon(list, x, z)
    local inside = false
    local n = #list / 2
    local j = n
    for i = 1, n do
        local xi, zi = list[2 * i - 1], list[2 * i]
        local xj, zj = list[2 * j - 1], list[2 * j]
        if ((zi > z) ~= (zj > z)) and (x < (xj - xi) * (z - zi) / ((zj - zi) + 1e-9) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

StorageMonitor.MAP_AREA = {0.075, 0.455, 1.525, 0.855}     -- where the map is drawn (design units)
StorageMonitor.MAP_COLS = 72                               -- cells across

--- The farm's fields as a grid of cells (the shapes do not change, so the grid is kept until the farm's fields
-- change): runs of cells per field {u0, v0, u1, v1, id}, and a label spot per field.
function StorageMonitor.readFieldMap(farmId, fieldsPanel)
    local shapes, ids = {}, {}
    for _, field in pairs(call(g_fieldManager, "getFields") or (g_fieldManager ~= nil and g_fieldManager.fields) or {}) do
        local farmland = type(field) == "table" and field.farmland or nil
        if farmland ~= nil and call(g_farmlandManager, "getFarmlandOwner", farmland.id) == farmId then
            local id = call(field, "getId") or field.fieldId or farmland.id
            local list = fieldOutline(field)
            if list == nil then         -- no outline: a square of the field's area round its middle
                local x, z = call(field, "getCenterOfFieldWorldPosition")
                if x ~= nil and z ~= nil then
                    local h = math.sqrt((tonumber(field.areaHa) or 1) * 10000) * 0.5
                    list = {x - h, z - h, x + h, z - h, x + h, z + h, x - h, z + h}
                end
            end
            if list ~= nil then
                local s = {id = tostring(id), list = list, minX = math.huge, minZ = math.huge, maxX = -math.huge, maxZ = -math.huge}
                for k = 1, #list, 2 do
                    s.minX, s.maxX = math.min(s.minX, list[k]), math.max(s.maxX, list[k])
                    s.minZ, s.maxZ = math.min(s.minZ, list[k + 1]), math.max(s.maxZ, list[k + 1])
                end
                table.insert(shapes, s)
                table.insert(ids, s.id)
            end
        end
    end
    table.sort(ids)
    local key = table.concat(ids, ",")
    StorageMonitor.mapCache = StorageMonitor.mapCache or {}
    local cached = StorageMonitor.mapCache[farmId]
    if cached ~= nil and cached.key == key then
        return cached
    end
    local map = {key = key, runs = {}, labels = {}}
    StorageMonitor.mapCache[farmId] = map
    if #shapes == 0 then
        return map
    end
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    for _, s in ipairs(shapes) do
        minX, maxX, minZ, maxZ = math.min(minX, s.minX), math.max(maxX, s.maxX), math.min(minZ, s.minZ), math.max(maxZ, s.maxZ)
    end
    local area = StorageMonitor.MAP_AREA
    local w, h = area[3] - area[1], area[4] - area[2]
    local spanX, spanZ = math.max(1, maxX - minX), math.max(1, maxZ - minZ)
    local scale = math.min(w / spanX, h / spanZ)           -- design units per metre
    local cell = w / StorageMonitor.MAP_COLS
    local cols = math.max(1, math.floor(spanX * scale / cell + 0.5))
    local rows = math.max(1, math.floor(spanZ * scale / cell + 0.5))
    local u0 = area[1] + (w - cols * cell) * 0.5
    local v0 = area[2] + (h - rows * cell) * 0.5
    local metres = cell / scale
    local counts, sums = {}, {}
    for r = 1, rows do
        local z = minZ + (r - 0.5) * metres
        local runId, runStart = nil, nil
        for c = 1, cols + 1 do
            local id = nil
            if c <= cols then
                local x = minX + (c - 0.5) * metres
                for _, s in ipairs(shapes) do
                    if x >= s.minX and x <= s.maxX and z >= s.minZ and z <= s.maxZ and insidePolygon(s.list, x, z) then
                        id = s.id
                        break
                    end
                end
                if id ~= nil then
                    counts[id] = (counts[id] or 0) + 1
                    local sum = sums[id] or {0, 0}
                    sum[1], sum[2] = sum[1] + c, sum[2] + r
                    sums[id] = sum
                end
            end
            if id ~= runId then
                if runId ~= nil then       -- the cells of one field side by side: one bar, a hair apart from the next
                    table.insert(map.runs, {u0 + (runStart - 1) * cell, v0 + (r - 1) * cell,
                        u0 + (c - 1) * cell - cell * 0.12, v0 + r * cell, runId})
                end
                runId, runStart = id, c
            end
        end
    end
    for id, n in pairs(counts) do
        if n >= 4 then
            table.insert(map.labels, {id = id, u = u0 + (sums[id][1] / n - 0.5) * cell, v = v0 + (sums[id][2] / n - 0.5) * cell})
        end
    end
    return map
end

--- The panel of a board (see above), or nil.
function StorageMonitor.buildBoard(target)
    local farmId = getPlayerFarmId()
    local kind = target.kind
    if kind == "fields" then
        return cachedBoard("fields|" .. tostring(farmId), function() return StorageMonitor.readFields(farmId) end)
    elseif kind == "fleet" then
        return cachedBoard("fleet|" .. tostring(farmId), function() return StorageMonitor.readFleet(farmId) end)
    elseif kind == "weather" then
        return StorageMonitor.readWeather()
    elseif kind == "contracts" then
        return StorageMonitor.readContracts(farmId)
    elseif kind == "allPens" then
        return StorageMonitor.readAllPens(target.pens or {})
    elseif kind == "allProductions" then
        return StorageMonitor.readAllProductions(target.productions or {})
    elseif kind == "prodNeeds" then
        return StorageMonitor.readProdNeeds(target.productions or {}, target.silos or {})
    elseif kind == "sellPlan" then
        return StorageMonitor.readSellPlan(target.sources)
    elseif kind == "profit" then
        return StorageMonitor.readProfit(target.productions or {})
    elseif kind == "openContracts" then
        return StorageMonitor.readOpenContracts(farmId)
    elseif kind == "farms" then
        return cachedBoard("farms|" .. tostring(farmId) .. "|" .. tostring(realPlayerFarmId()), function() return StorageMonitor.readFarms(farmId) end)
    elseif kind == "fieldMap" then
        local fields = cachedBoard("fields|" .. tostring(farmId), function() return StorageMonitor.readFields(farmId) end)
        return setmetatable({kind = "fieldMap", map = StorageMonitor.readFieldMap(farmId, fields)}, {__index = fields})
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

--- The price alert's message when the product sells for at least the price set, else nil.
function StorageMonitor.priceAlertText(priceAlert)
    if priceAlert == nil or g_fillTypeManager == nil then
        return nil
    end
    local index = call(g_fillTypeManager, "getFillTypeIndexByName", priceAlert.fill)
    local best = index ~= nil and StorageMonitor.bestPrice(index) or nil
    if best == nil or best.price * 1000 < priceAlert.price - 0.005 then
        return nil
    end
    local info = fillTypeInfo(index)
    return string.format(StorageMonitor.getText("storageMonitor_alertPrice", "%s sells for %s at %s"),
        tostring(info ~= nil and info.title or priceAlert.fill), StorageMonitor.formatMoney(best.price * 1000), tostring(best.station))
end

--- The alerts of a snapshot: {key, text}, most important first. opts: {fullAt, priceAlert} of the monitor.
function StorageMonitor.computeAlerts(target, snapshot, opts)
    local T = StorageMonitor.getText
    local alerts = {}
    local function add(key, text)
        table.insert(alerts, {key = key, text = text})
    end
    opts = opts or {}
    local fullAt = opts.fullAt or StorageMonitor.ALERT_FULL
    local panel = snapshot.panel
    local kind = target.kind
    if panel ~= nil and panel.problems ~= nil then         -- a board lists its own
        for _, problem in ipairs(panel.problems) do
            add(problem.id, problem.text)
        end
    end
    if panel == nil and snapshot.capacity > 0 and kind ~= "finance" and kind ~= "beehive" then
        local pct = StorageMonitor.percent(snapshot.used, snapshot.capacity)
        if pct >= 100 then
            add("full", T("storageMonitor_alertFull", "Full"))
        elseif pct >= fullAt then
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
        if panel.capacity > 0 and pct >= fullAt then
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
    -- the monitor's price alert, whatever it shows
    local priceText = opts.priceAlert ~= nil and StorageMonitor.priceAlertText(opts.priceAlert) or nil
    if priceText ~= nil then
        add("price_" .. tostring(opts.priceAlert.fill), priceText)
    end
    return alerts
end

-- a game message for each alert that is new since the last read of that screen (a slideshow keeps one list
-- per screen; a screen read for the first time announces nothing), on the monitor's own farm only, at most
-- once per storage and alert every ALERT_REPEAT (several monitors at one storage give one message)
function StorageMonitor.announceAlerts(monitor, target, alerts)
    local spec = monitor.spec_storageMonitor
    if spec.alertKnownBy == nil then
        spec.alertKnownBy = setmetatable({}, {__mode = "k"})
    end
    local screen = target.owner ~= nil and target.owner or "none"
    local known = spec.alertKnownBy[screen]
    local now = {}
    for _, a in ipairs(alerts) do
        now[a.key] = true
    end
    spec.alertKnownBy[screen] = now
    if known == nil or spec.alerts < 3 or g_currentMission == nil or g_currentMission.addIngameNotification == nil then
        return
    end
    local owner = call(monitor, "getOwnerFarmId")
    if owner ~= nil and owner ~= realPlayerFarmId() then
        return
    end
    StorageMonitor.announced = StorageMonitor.announced or {}
    for _, a in ipairs(alerts) do
        if not known[a.key] then
            -- a price is the same news on every screen: one message for all monitors
            local isPrice = string.sub(a.key, 1, 6) == "price_"
            local id = isPrice and a.key or (tostring(target.owner) .. "|" .. a.key)
            local last = StorageMonitor.announced[id]
            if last == nil or StorageMonitor.clock - last >= StorageMonitor.ALERT_REPEAT then
                StorageMonitor.announced[id] = StorageMonitor.clock
                local kind = FSBaseMission ~= nil and FSBaseMission.INGAME_NOTIFICATION_CRITICAL or 1
                local message = isPrice and a.text or string.format("%s: %s", tostring(target.title or target.name), a.text)
                g_currentMission:addIngameNotification(kind, message)
            end
        end
    end
end

function StorageMonitor:refreshStorageMonitorData()
    return StorageMonitor.asMonitorFarm(self, StorageMonitor.refreshStorageMonitorDataNow)
end

function StorageMonitor:refreshStorageMonitorDataNow()
    local spec = self.spec_storageMonitor
    spec.dataTimer = 0
    if spec.target == nil then
        spec.snapshot = nil
        return
    end
    local snapshot = StorageMonitor.buildSnapshot(spec.target.sources, spec.target.roles, fillTypeInfo)
    spec.snapshot = snapshot
    snapshot.panel = StorageMonitor.buildPanel(spec.target)
    snapshot.countMode = spec.target.kind == "objects"
    snapshot.noPercent = spec.target.kind == "bunker"

    local history = StorageMonitor.historyFor(spec, spec.target.owner)
    local now = StorageMonitor.gameHours()
    if StorageMonitor.BOARD_KINDS[spec.target.kind] then
        -- a board: its rows instead of products; no rates, prices or graph
        snapshot.board = true
        snapshot.rows = snapshot.panel ~= nil and snapshot.panel.rows or {}
        snapshot.count = #snapshot.rows
    elseif snapshot.panel ~= nil and snapshot.panel.kind == "finance" then
        -- money: the list is the day's finances; no rates, no prices; the graph is the balance
        snapshot.finance = true
        snapshot.count = #snapshot.panel.lines
        StorageMonitor.updateGraph(history, now, snapshot.panel.money, nil)
        snapshot.graph = StorageMonitor.serverGraphFor(spec, spec.target) or history.graph
        snapshot.graphNow = {v = snapshot.panel.money}
    else
        -- rates and time left from the levels over the last in-game hours
        local food = snapshot.panel ~= nil and snapshot.panel.food or nil
        StorageMonitor.updateRates(history, snapshot, now, spec.target.owner, food)
        -- the graph: how full over the last in-game day (a shed counts its bales or pallets)
        local panel = snapshot.panel
        local value, capacity = snapshot.used, snapshot.capacity > 0 and snapshot.capacity or nil
        if panel ~= nil and panel.kind == "objects" then
            value, capacity = panel.count, panel.capacity > 0 and panel.capacity or nil
        end
        StorageMonitor.updateGraph(history, now, value, capacity)
        snapshot.graph = StorageMonitor.serverGraphFor(spec, spec.target) or history.graph
        snapshot.graphNow = {v = value, cap = capacity}
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
            StorageMonitor.addPrices(snapshot)
            snapshot.prices = true
        end
    end

    -- only the products picked (one: the big single-product view); the capacity panel keeps the whole storage
    if spec.only ~= nil and #spec.only > 0 and not snapshot.board and not snapshot.finance then
        local wanted = {}
        for _, name in ipairs(spec.only) do
            wanted[name] = true
        end
        snapshot.allItems = snapshot.items
        local kept = {}
        for _, item in ipairs(snapshot.items) do
            if wanted[item.name] then
                table.insert(kept, item)
            end
        end
        snapshot.items = kept
        snapshot.count = #kept
        if #spec.only == 1 and #kept == 1 then
            snapshot.single = kept[1]
        end
    end

    -- alerts
    if spec.alerts > 1 then
        spec.alertList = StorageMonitor.computeAlerts(spec.target, snapshot,
            {fullAt = spec.fullAt, priceAlert = spec.priceAlert}) or {}
        StorageMonitor.announceAlerts(self, spec.target, spec.alertList)
    else
        spec.alertList = {}
        spec.alertKnownBy = setmetatable({}, {__mode = "k"})
    end
    -- the history graph takes the list's place (no pages)
    snapshot.showGraph = spec.mode == StorageMonitor.MODE_HISTORY and snapshot.graph ~= nil
    spec.layout = StorageMonitor.computeListLayout(snapshot.showGraph and 0 or snapshot.count)
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
    StorageMonitor.iconFailed = StorageMonitor.iconFailed or {}
    if StorageMonitor.iconFailed[path] then
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
    -- As DashboardLive does: a new material from the slot's own one with the product's image, put on at once. The
    -- game frees a material no shape uses, so no material id is ever kept for later (1.4.0.0 and 1.4.0.1 kept them
    -- and hit "setMaterial: Unknown entity id" when a slot came back to a product).
    if slot.path ~= path then
        local source = getMaterial(slot.node, 0)
        local material = nil
        if source ~= nil and source ~= 0 then
            material = setMaterialDiffuseMapFromFile(source, path, true, true, false)
        end
        if material == nil or material == 0 then
            StorageMonitor.iconFailed[path] = true
            StorageMonitor.log("Warning: icon %s not loaded", tostring(path))
            spec.iconUsed = spec.iconUsed - 1
            return false
        end
        setMaterial(slot.node, material, 0)
        slot.path = path
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
    StorageMonitor.fullAt = spec.fullAt or StorageMonitor.ALERT_FULL
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
    -- a slideshow: which screen of how many, left of the clock, and a thin bar for the time to the next one
    local slides = StorageMonitor.activeSlides(spec)
    local titleW = slides ~= nil and 1.08 or 1.20
    if spec.headerTitle == nil or spec.headerSource ~= title or spec.headerWidth ~= titleW then
        spec.headerTitle = fitText(f, string.upper(title), 0.050, titleW, true)
        spec.headerSource = title
        spec.headerWidth = titleW
    end
    text(f, 0.050, 0.070, 0.050, spec.headerTitle, COLORS.headText, RenderText.ALIGN_LEFT, true)

    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil and env.currentHour ~= nil then
        local clock = string.format("%02d:%02d", env.currentHour, env.currentMinute or 0)
        text(f, 1.550, 0.070, 0.045, clock, COLORS.headAccent, RenderText.ALIGN_RIGHT, true)
    end
    if slides ~= nil and #slides > 1 then
        text(f, 1.395, 0.068, 0.032, string.format("%d/%d", math.min(spec.slideIndex or 1, #slides), #slides),
            COLORS.headAccent, RenderText.ALIGN_RIGHT, true)
        local duration = StorageMonitor.SLIDE_TIMES[spec.slideTime] or 0
        if duration > 0 then
            local split = 1.600 * math.max(0, math.min(1, (spec.slideTimer or 0) / duration))
            rect(f, 0.000, 0.100, split, 0.104, COLORS.headAccent, 0.6)
        end
    end

    -- the message board: the text, as big as fits
    if spec.target ~= nil and spec.target.kind == "message" then
        StorageMonitor.drawMessage(self, f)
        StorageMonitor.resetTextState(self)
        return
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
    if snapshot.board then
        StorageMonitor.drawBoardPanel(self, f, snapshot)
    elseif snapshot.prices then
        StorageMonitor.drawPricePanel(self, f, snapshot)
    elseif snapshot.panel ~= nil then
        StorageMonitor.drawKindPanel(self, f, snapshot)
    else
        StorageMonitor.drawCapacityPanel(self, f, snapshot)
    end

    -- product list: everything at once if it fits, else pages; or the history graph
    if snapshot.board and snapshot.panel ~= nil and snapshot.panel.kind == "fieldMap" then
        StorageMonitor.drawFieldMap(self, f, snapshot)
    elseif snapshot.showGraph then
        StorageMonitor.drawGraph(self, f, snapshot)
    elseif snapshot.single ~= nil and not snapshot.prices then
        StorageMonitor.drawSingle(self, f, snapshot)
    else
        StorageMonitor.drawList(self, f, snapshot)
    end
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

-- a colour of a board: a COLORS key or {r, g, b}
local function colorOf(c)
    if type(c) == "string" then
        return COLORS[c] or COLORS.text
    end
    return c or COLORS.text
end

local function countText(n)
    return tostring(math.floor((n or 0) + 0.5))
end

-- a count that is red (or amber) when it is not 0
local function warnCount(n, key)
    return {countText(n), (n or 0) > 0 and (key or "full") or "dim"}
end

--- What the top panel of a board shows: {label, big, bigColor, note, noteColor, cells = {{title, value, color}},
-- heads = {title column, middle column, value column}} (colours as COLORS keys).
function StorageMonitor.boardSummary(panel)
    local T = StorageMonitor.getText
    local kind = panel.kind
    if kind == "fields" or kind == "fieldMap" then
        local toSow, work, withered = warnCount(panel.toSow, "warn"), warnCount(panel.work, "warn"), warnCount(panel.withered)
        -- the harvest window: how long it stays dry
        local note, noteColor = nil, "dim"
        if panel.raining then
            note, noteColor = T("storageMonitor_rainingNow", "Raining now"), "input"
        elseif panel.dryFor ~= nil and panel.dryFor >= 24 then
            note, noteColor = T("storageMonitor_dryDay", "Dry for a day or more"), "ok"
        elseif panel.dryFor ~= nil then
            note = string.format(T("storageMonitor_dryFor", "Dry for %d h"), panel.dryFor)
            noteColor = panel.dryFor <= 6 and "warn" or "ok"
        end
        return {label = T("storageMonitor_readyCaps", "READY TO HARVEST"), big = countText(panel.ready),
            bigColor = panel.ready > 0 and "ok" or "dim", note = note, noteColor = noteColor,
            cells = {{T("storageMonitor_fieldsCount", "Fields"), countText(panel.count), "text"},
                     {T("storageMonitor_area", "Area"), StorageMonitor.formatArea(panel.area), "text"},
                     {T("storageMonitor_harvestWorth", "Harvest worth"), panel.harvestValue ~= nil and StorageMonitor.formatMoney(panel.harvestValue) or "--", "ok"},
                     {T("storageMonitor_toSow", "To sow"), toSow[1], toSow[2]},
                     {T("storageMonitor_needWork", "Need work"), work[1], work[2]},
                     {T("storageMonitor_cropWithered", "Withered"), withered[1], withered[2]}},
            heads = {T("storageMonitor_colField", "FIELD"), T("storageMonitor_colNeeds", "NEEDS"), T("storageMonitor_colState", "STATE")}}
    elseif kind == "weather" then
        local now = panel.now or {title = "--", color = "dim"}
        local trend = T("storageMonitor_steady", "Steady")
        if panel.trend ~= nil and panel.trend > 0 then
            trend = T("storageMonitor_rising", "Rising")
        elseif panel.trend ~= nil and panel.trend < 0 then
            trend = T("storageMonitor_falling", "Falling")
        end
        local nextText, nextColor = T("storageMonitor_noChange", "No change today"), "dim"
        if panel.change ~= nil then
            nextText = string.format(T("storageMonitor_alertWeatherSoon", "%s in %d h"), panel.change.info.title, panel.change.hours)
            nextColor = panel.change.info.color
        end
        local fall, fallColor = T("storageMonitor_fallNone", "None"), "ok"
        if panel.hail then
            fall, fallColor = T("storageMonitor_wHail", "Hail"), "full"
        elseif panel.snowing then
            fall, fallColor = T("storageMonitor_wSnow", "Snow"), "text"
        elseif panel.raining then
            fall, fallColor = T("storageMonitor_wRain", "Rain"), "input"
        end
        local today = "--"
        if panel.minT ~= nil and panel.maxT ~= nil then
            today = string.format("%s / %s", StorageMonitor.formatTemperature(panel.maxT), StorageMonitor.formatTemperature(panel.minT))
        end
        return {label = T("storageMonitor_temperature", "TEMPERATURE"), big = StorageMonitor.formatTemperature(panel.temperature),
            bigColor = "accent", note = now.title, noteColor = now.color,
            cells = {{T("storageMonitor_weatherNow", "Now"), now.title, now.color},
                     {T("storageMonitor_today", "Today"), today, "text"},
                     {T("storageMonitor_next", "Next"), nextText, nextColor},
                     {T("storageMonitor_tempTrend", "Temperature"), trend, "dim"},
                     {T("storageMonitor_precipitation", "Falling now"), fall, fallColor},
                     {T("storageMonitor_crops", "Crops"), panel.wet and T("storageMonitor_cropsWet", "Wet") or T("storageMonitor_cropsDry", "Dry"),
                      panel.wet and "warn" or "ok"}},
            heads = {T("storageMonitor_colWhen", "WHEN"), "", T("storageMonitor_colWeather", "WEATHER")}}
    elseif kind == "fleet" then
        local low, repair = warnCount(panel.lowFuel), warnCount(panel.repair, "warn")
        return {label = T("storageMonitor_helpersCaps", "HELPERS WORKING"), big = countText(panel.helpers),
            bigColor = panel.helpers > 0 and "accent" or "dim",
            cells = {{T("storageMonitor_vehicles", "Vehicles"), countText(panel.count), "text"},
                     {T("storageMonitor_inUse", "In use"), countText(panel.inUse), "ok"},
                     {T("storageMonitor_lowFuel", "Low fuel"), low[1], low[2]},
                     {T("storageMonitor_needRepair", "Need repair"), repair[1], repair[2]},
                     {T("storageMonitor_leased", "Leased"), countText(panel.leased), "dim"}},
            heads = {T("storageMonitor_colVehicle", "VEHICLE"), T("storageMonitor_colStatus", "STATUS"), T("storageMonitor_colFuel", "FUEL")}}
    elseif kind == "contracts" then
        return {label = T("storageMonitor_contractsCaps", "CONTRACTS RUNNING"), big = countText(panel.count),
            bigColor = panel.count > 0 and "accent" or "dim",
            cells = {{T("storageMonitor_reward", "Reward"), StorageMonitor.formatMoney(panel.reward), "ok"},
                     {T("storageMonitor_almostDone", "Almost done"), countText(panel.almostDone), panel.almostDone > 0 and "ok" or "dim"},
                     {T("storageMonitor_average", "Average"), string.format("%d%%", math.floor(panel.completion * 100)), "text"}},
            heads = {T("storageMonitor_colContract", "CONTRACT"), T("storageMonitor_colWhere", "WHERE  REWARD"), T("storageMonitor_colDone", "DONE")}}
    elseif kind == "allPens" then
        local lowFood, low, tanks = warnCount(panel.lowFood), warnCount(panel.lowSupply), warnCount(panel.tanksFull, "warn")
        local food, foodColor = "--", "dim"
        if panel.foodHours ~= nil then
            food = StorageMonitor.formatDuration(panel.foodHours)
            foodColor = panel.foodHours < 12 and "full" or (panel.foodHours < 48 and "warn" or "ok")
        end
        return {label = T("storageMonitor_animals", "ANIMALS"), big = countText(panel.animals), bigColor = "ok",
            cells = {{T("storageMonitor_pens", "Pens"), countText(panel.count), "text"},
                     {T("storageMonitor_places", "Places"), string.format("%d/%d", panel.animals, panel.maxAnimals), "text"},
                     {T("storageMonitor_lowFood", "Low food"), lowFood[1], lowFood[2]},
                     {T("storageMonitor_lowSupplies", "Low water, straw"), low[1], low[2]},
                     {T("storageMonitor_tanksFull", "Tanks full"), tanks[1], tanks[2]},
                     {T("storageMonitor_foodLasts", "Food lasts"), food, foodColor}},
            heads = {T("storageMonitor_colPen", "PEN"), T("storageMonitor_colSupplies", "SUPPLIES"), T("storageMonitor_animals", "ANIMALS")}}
    elseif kind == "allProductions" then
        local missing, full, water = warnCount(panel.missing), warnCount(panel.full), warnCount(panel.noWater)
        local allRunning = panel.lines > 0 and panel.running == panel.lines
        return {label = T("storageMonitor_linesRunning", "RUNNING"), big = string.format("%d/%d", panel.running, panel.lines),
            bigColor = allRunning and "ok" or (panel.running > 0 and "warn" or "full"),
            cells = {{T("storageMonitor_productions", "Productions"), countText(panel.count), "text"},
                     {T("storageMonitor_line_missing", "Missing inputs"), missing[1], missing[2]},
                     {T("storageMonitor_line_full", "Output full"), full[1], full[2]},
                     {T("storageMonitor_alertNoWater", "No water"), water[1], water[2]},
                     {T("storageMonitor_idle", "Idle"), countText(panel.idle), panel.idle > 0 and "warn" or "dim"}},
            heads = {T("storageMonitor_colProduction", "PRODUCTION"), T("storageMonitor_colStatus", "STATUS"), T("storageMonitor_colLines", "LINES")}}
    elseif kind == "prodNeeds" then
        local empty, low = warnCount(panel.empty), warnCount(panel.low, "warn")
        return {label = T("storageMonitor_needEmptyCaps", "INPUTS EMPTY"), big = countText(panel.empty),
            bigColor = panel.empty > 0 and "full" or "ok",
            note = panel.first ~= nil and string.format(T("storageMonitor_needFirst", "First: %s"), panel.first) or nil,
            noteColor = panel.empty > 0 and "full" or "warn",
            cells = {{T("storageMonitor_productions", "Productions"), countText(panel.productions), "text"},
                     {T("storageMonitor_needInputs", "Inputs"), countText(panel.count), "text"},
                     {T("storageMonitor_needEmpty", "Empty"), empty[1], empty[2]},
                     {T("storageMonitor_needLow", "Low"), low[1], low[2]},
                     {T("storageMonitor_needToFill", "To fill up"), StorageMonitor.formatVolume(panel.toFill), "accent"}},
            heads = {T("storageMonitor_colNeedInput", "PRODUCTION: INPUT"), T("storageMonitor_colStatus", "STATUS"), T("storageMonitor_colNeedRoom", "TO FILL UP")}}
    elseif kind == "sellPlan" then
        local gain = panel.valueBest - panel.valueNow
        return {label = T("storageMonitor_stockValue", "STOCK VALUE"), big = StorageMonitor.formatMoney(panel.valueNow), bigColor = "ok",
            cells = {{T("storageMonitor_atBest", "At the best months"), StorageMonitor.formatMoney(panel.valueBest), "accent"},
                     {T("storageMonitor_waitGain", "More if you wait"), "+" .. StorageMonitor.formatMoney(gain), gain > 0 and "accent" or "dim"},
                     {T("storageMonitor_sellNowCount", "Sell now"), countText(panel.sellNow), "ok"},
                     {T("storageMonitor_holdCount", "Better later"), countText(panel.hold), panel.hold > 0 and "warn" or "dim"},
                     {T("storageMonitor_productsCount", "Products"), countText(panel.count), "text"}},
            heads = {T("storageMonitor_colProduct", "PRODUCT"), T("storageMonitor_colBestTime", "BEST TIME"), T("storageMonitor_colGain", "GAIN")}}
    elseif kind == "profit" then
        local losing, waiting = warnCount(panel.losing), warnCount(panel.waiting, "warn")
        return {label = T("storageMonitor_profitCaps", "PROFIT PER HOUR"), big = StorageMonitor.formatMoney(panel.perHour),
            bigColor = panel.perHour >= 0 and "ok" or "full",
            note = panel.best ~= nil and string.format(T("storageMonitor_bestLine", "Best: %s"), panel.best.name) or nil, noteColor = "ok",
            cells = {{T("storageMonitor_perDay", "Per day"), StorageMonitor.formatMoney(panel.perHour * 24), panel.perHour >= 0 and "ok" or "full"},
                     {T("storageMonitor_linesCount", "Lines"), countText(panel.count), "text"},
                     {T("storageMonitor_losing", "Losing money"), losing[1], losing[2]},
                     {T("storageMonitor_line_missing", "Missing inputs"), waiting[1], waiting[2]}},
            heads = {T("storageMonitor_colLine", "LINE"), T("storageMonitor_colInOut", "PER IN-GAME HOUR"), T("storageMonitor_colProfit", "PROFIT")}}
    elseif kind == "openContracts" then
        local taken = panel.max ~= nil and string.format("%d/%d", panel.running, panel.max) or countText(panel.running)
        return {label = T("storageMonitor_toTakeCaps", "CONTRACTS TO TAKE"), big = countText(panel.count),
            bigColor = panel.count > 0 and "accent" or "dim",
            note = panel.limitReached and T("storageMonitor_limitReached", "Your farm is at its limit") or nil, noteColor = "warn",
            cells = {{T("storageMonitor_bestReward", "Best reward"), StorageMonitor.formatMoney(panel.bestReward), "ok"},
                     {T("storageMonitor_bestPerHa", "Best per ha"), panel.bestPerHa ~= nil and StorageMonitor.formatMoney(panel.bestPerHa) or "--", "ok"},
                     {T("storageMonitor_taken", "Running"), taken, panel.limitReached and "warn" or "text"},
                     {T("storageMonitor_allRewards", "All rewards"), StorageMonitor.formatMoney(panel.total), "text"}},
            heads = {T("storageMonitor_colContract", "CONTRACT"), T("storageMonitor_colWhere", "WHERE  REWARD"), T("storageMonitor_colReward", "REWARD")}}
    elseif kind == "farms" then
        local mine = panel.mine
        return {label = T("storageMonitor_myPlace", "MY PLACE"), big = panel.place ~= nil and string.format("#%d", panel.place) or "--",
            bigColor = panel.place == 1 and "ok" or "accent",
            note = string.format(T("storageMonitor_ofFarms", "of %d farms"), panel.count), noteColor = "dim",
            cells = {{T("storageMonitor_myBalance", "My balance"), (mine ~= nil and mine.money ~= nil) and StorageMonitor.formatMoney(mine.money) or "--", "accent"},
                     {T("storageMonitor_richest", "Richest"), panel.richest ~= nil and tostring(panel.richest.title) or "--", "text"},
                     {T("storageMonitor_farmsCount", "Farms"), countText(panel.count), "text"}},
            heads = {T("storageMonitor_colFarm", "FARM"), T("storageMonitor_colFarmParts", "FIELDS  VEHICLES  ANIMALS"), T("storageMonitor_colBalance", "BALANCE")}}
    end
    return {label = "", big = "--", bigColor = "dim", cells = {}, heads = {"", "", ""}}
end

-- the top panel of a board: a big number on the left, up to six cells on the right
function StorageMonitor:drawBoardPanel(f, snapshot)
    local panel = snapshot.panel
    if panel == nil then
        return
    end
    local cache = self.spec_storageMonitor.rowCache
    local function fitted(key, str, size, width, bold)
        local c = cache[key]
        if c == nil or c.source ~= str or math.abs(c.width - width) > 1e-6 then
            c = {source = str, width = width, text = fitText(f, str, size, width, bold)}
            cache[key] = c
        end
        return c.text
    end
    local s = StorageMonitor.boardSummary(panel)
    snapshot.heads = s.heads
    -- the label shrinks to fit (long words in some languages) before it is shortened
    local labelSize = 0.032
    local labelW = textWidth(f, labelSize, s.label, true)
    if labelW > 0.32 then
        labelSize = math.max(0.019, labelSize * 0.32 / labelW)
    end
    text(f, 0.070, 0.185, labelSize, fitted("boardLabel", s.label, labelSize, 0.32, true), COLORS.dim, RenderText.ALIGN_LEFT, true)
    bigNumber(f, s.big, colorOf(s.bigColor), 0.110)
    if s.note ~= nil and s.note ~= "" then
        text(f, 0.070, 0.356, 0.022, fitted("boardNote", s.note, 0.022, 0.30, true), colorOf(s.noteColor), RenderText.ALIGN_LEFT, true)
    end
    local x0, x1 = 0.420, 1.530
    local colW = (x1 - x0 - 0.05) / 2
    local rowV = {0.190, 0.262, 0.334}
    for i, c in ipairs(s.cells) do
        if i > StorageMonitor.PANEL_ROWS * 2 then
            break
        end
        local u0 = x0 + ((i - 1) % 2) * (colW + 0.05)
        local base = rowV[math.floor((i - 1) / 2) + 1]
        local value = fitted("cellValue" .. i, tostring(c[2]), 0.028, colW * 0.6, true)
        local valueW = textWidth(f, 0.028, value, true)
        text(f, u0, base, 0.028, fitted("cell" .. i, c[1], 0.028, colW - valueW - 0.02, false), COLORS.text, RenderText.ALIGN_LEFT, false)
        text(f, u0 + colW, base, 0.028, value, colorOf(c[3]), RenderText.ALIGN_RIGHT, true)
    end
end

-- the rows of a board: one wide column (name, middle text, a bar, value), or 2 to 3 compact columns (name and
-- value, a thin bar underneath)
function StorageMonitor:drawRowList(f, snapshot, layout, first)
    local spec = self.spec_storageMonitor
    local L = LAYOUT
    local size = layout.size
    local rows = snapshot.rows or {}
    local heads = snapshot.heads or StorageMonitor.boardSummary(snapshot.panel or {}).heads
    local cache = spec.rowCache
    local function fitted(key, str, sz, width, bold)
        local c = cache[key]
        if c == nil or c.source ~= str or math.abs(c.width - width) > 1e-6 then
            c = {source = str, width = width, text = fitText(f, str, sz, width, bold)}
            cache[key] = c
        end
        return c.text
    end
    -- the row's icon (a crop) or a coloured square
    local function mark(r, u, vc, side)
        local tint = iconColor({color = colorOf(r.iconColor or r.swatch)})
        if r.icon == nil or not icon(f, u - side * 0.05, vc - side * 0.5, side, r.icon, tint) then
            local half = side * 0.36
            rect(f, u, vc - half, u + half * 2, vc + half, colorOf(r.swatch))
        end
    end
    -- a row to act on: a stripe in its colour left of it (blinking: urgent), its name in the colour too
    local function flag(r, u1, vc)
        if r.flag ~= nil and (not r.blink or StorageMonitor.clock % 1000 < 650) then
            local half = layout.rowH * 0.38
            rect(f, u1 - 0.010, vc - half, u1, vc + half, colorOf(r.flag))
        end
    end

    if layout.cols == 1 then
        local headSize = math.min(0.026, size * 0.75)
        text(f, 0.070, L.listHeadV, headSize, heads[1] or "", COLORS.dim, RenderText.ALIGN_LEFT, true)
        text(f, 0.585, L.listHeadV, headSize, heads[2] or "", COLORS.dim, RenderText.ALIGN_LEFT, true)
        text(f, 1.535, L.listHeadV, headSize, heads[3] or "", COLORS.dim, RenderText.ALIGN_RIGHT, true)
        for row = 1, layout.rows do
            local r = rows[first + row]
            if r == nil then
                break
            end
            local vc = L.listTopV + layout.rowH * (row - 0.5)
            local baseline = vc + size * 0.36
            mark(r, 0.066, vc, size * 0.95)
            flag(r, 0.050, vc)
            text(f, 0.120, baseline, size, fitted("t" .. r.id, tostring(r.title), size, 0.445, false), colorOf(r.titleColor or "text"), RenderText.ALIGN_LEFT, false)
            if r.sub ~= nil and r.sub ~= "" then
                local subW = (r.ratio ~= nil and 1.005 or 1.240) - 0.585
                text(f, 0.585, baseline, size * 0.85, fitted("s" .. r.id, tostring(r.sub), size * 0.85, subW, false),
                    colorOf(r.subColor or "dim"), RenderText.ALIGN_LEFT, false)
            end
            if r.ratio ~= nil then
                local h = math.min(L.rowBarHalfH, layout.rowH * 0.18)
                ratioBarRow(f, 1.030, vc - h, 1.250, vc + h, r.ratio, colorOf(r.ratioColor or "accent"))
            end
            text(f, 1.535, baseline, size * 0.92, fitted("v" .. r.id, tostring(r.value or ""), size * 0.92, 0.26, true),
                colorOf(r.valueColor), RenderText.ALIGN_RIGHT, true)
        end
        return
    end

    local headSize = math.min(0.026, size * 0.85)
    for c = 1, layout.cols do
        local x0, x1 = StorageMonitor.columnBounds(layout, c)
        text(f, x0, L.listHeadV, headSize, heads[1] or "", COLORS.dim, RenderText.ALIGN_LEFT, true)
        text(f, x1, L.listHeadV, headSize, heads[3] or "", COLORS.dim, RenderText.ALIGN_RIGHT, true)
        if c < layout.cols then
            local sx = x1 + L.colGap * 0.5
            rect(f, sx - 0.0015, L.listTopV - 0.035, sx + 0.0015, L.listBottomV, COLORS.track)
        end
        for row = 1, layout.rows do
            local r = rows[first + (c - 1) * layout.rows + row]
            if r == nil then
                break
            end
            local vc = L.listTopV + layout.rowH * (row - 0.5)
            local baseline = vc + size * 0.22
            local side = size * 0.92
            mark(r, x0, baseline - size * 0.36, side)
            flag(r, x0 - 0.010, vc)
            local nameX = x0 + side * 0.85 + size * 0.3
            local value = fitted("v" .. r.id .. c, tostring(r.value or ""), size * 0.92, (x1 - x0) * 0.45, true)
            local valueW = textWidth(f, size * 0.92, value, true)
            text(f, nameX, baseline, size, fitted("t" .. r.id .. c, tostring(r.title), size, x1 - valueW - size * 0.6 - nameX, false),
                colorOf(r.titleColor or "text"), RenderText.ALIGN_LEFT, false)
            text(f, x1, baseline, size * 0.92, value, colorOf(r.valueColor), RenderText.ALIGN_RIGHT, true)
            if r.ratio ~= nil then
                local b0 = vc + size * 0.55
                ratioBarRow(f, nameX, b0, x1, b0 + math.max(0.003, layout.rowH * 0.09), r.ratio, colorOf(r.ratioColor or "accent"))
            end
        end
    end
end

--- The history graph in place of the list: a column per GRAPH_STEP over the last GRAPH_SPAN in-game hours,
-- how full (in percent of the capacity, coloured as the level) or, without a capacity, the amount (money:
-- the balance). The last column is now.
function StorageMonitor:drawGraph(f, snapshot)
    local T = StorageMonitor.getText
    local L = LAYOUT
    local graph = snapshot.graph or {}
    local live = snapshot.graphNow
    local slots = math.floor(StorageMonitor.GRAPH_SPAN / StorageMonitor.GRAPH_STEP + 0.5)
    local now = StorageMonitor.gameHours() or (graph[#graph] ~= nil and graph[#graph].t) or 0
    local values = {}
    for _, s in ipairs(graph) do
        local k = slots - math.floor((now - s.t) / StorageMonitor.GRAPH_STEP + 1e-6)
        if k >= 1 and k <= slots then
            values[k] = s
        end
    end
    if live ~= nil then
        values[slots] = live
    end
    -- percent of the capacity, or the amount between the lowest and the highest
    local cap = live ~= nil and live.cap or nil
    local function percentOf(s)
        local c = s.cap or cap
        return (c ~= nil and c > 0) and (s.v / c * 100) or nil
    end
    local usePercent = cap ~= nil and cap > 0
    local lo, hi = 0, 100
    if not usePercent then
        hi = 1
        for _, s in pairs(values) do
            lo, hi = math.min(lo, s.v), math.max(hi, s.v)
        end
        hi = hi + (hi - lo) * 0.08
    end
    local function valueOf(s)
        if usePercent then
            return math.max(0, math.min(100, percentOf(s) or 0))
        end
        return s.v
    end
    local function label(v)
        if usePercent then
            return string.format("%d%%", math.floor(v + 0.5))
        elseif snapshot.finance then
            return StorageMonitor.shortNumber(v)
        end
        return StorageMonitor.shortNumber(v)
    end

    local u0, u1, vt, vb = 0.175, 1.530, 0.468, 0.845
    local headSize = 0.026
    text(f, 0.070, L.listHeadV, headSize, T("storageMonitor_last24", "LAST 24 IN-GAME HOURS"), COLORS.dim, RenderText.ALIGN_LEFT, true)
    if live ~= nil then
        local nowText
        if usePercent then
            nowText = string.format("%d%%", StorageMonitor.percent(live.v, cap))
        elseif snapshot.finance then
            nowText = StorageMonitor.formatMoney(live.v)
        else
            nowText = StorageMonitor.formatVolume(live.v)
        end
        text(f, 1.535, L.listHeadV, headSize, string.format(T("storageMonitor_nowValue", "NOW %s"), nowText), COLORS.accent, RenderText.ALIGN_RIGHT, true)
    end
    -- the axis labels
    local function yOf(v)
        return vb - (v - lo) / (hi - lo) * (vb - vt)
    end
    text(f, 0.160, vt + 0.010, 0.022, label(hi), COLORS.dim, RenderText.ALIGN_RIGHT, false)
    text(f, 0.160, (vt + vb) * 0.5 + 0.008, 0.022, label((lo + hi) * 0.5), COLORS.dim, RenderText.ALIGN_RIGHT, false)
    text(f, 0.160, vb, 0.022, label(lo), COLORS.dim, RenderText.ALIGN_RIGHT, false)
    text(f, u0, 0.884, 0.022, T("storageMonitor_hoursAgo24", "-24 h"), COLORS.dim, RenderText.ALIGN_LEFT, false)
    text(f, (u0 + u1) * 0.5, 0.884, 0.022, T("storageMonitor_hoursAgo12", "-12 h"), COLORS.dim, RenderText.ALIGN_CENTER, false)
    text(f, u1, 0.884, 0.022, T("storageMonitor_now", "now"), COLORS.dim, RenderText.ALIGN_RIGHT, false)

    -- the columns: the value and the empty rest above (and below, under zero) side by side, never on top
    local w = (u1 - u0) / slots
    local zero = yOf(math.max(lo, math.min(hi, 0)))
    for k = 1, slots do
        local x0 = u0 + (k - 1) * w
        local x1 = x0 + w * 0.78
        local s = values[k]
        if s == nil then
            rect(f, x0, vt, x1, vb, COLORS.stackFree)
        else
            local v = valueOf(s)
            local y = math.max(vt, math.min(vb, yOf(v)))
            local color
            if usePercent then
                color = StorageMonitor.levelColor(v)
            elseif snapshot.finance then
                color = v >= 0 and COLORS.ok or COLORS.full
            else
                color = COLORS.accent
            end
            if v >= 0 then
                rect(f, x0, vt, x1, y, COLORS.track)
                rect(f, x0, y, x1, zero, color)
                rect(f, x0, zero, x1, vb, COLORS.track)
            else
                rect(f, x0, vt, x1, zero, COLORS.track)
                rect(f, x0, zero, x1, y, color)
                rect(f, x0, y, x1, vb, COLORS.track)
            end
        end
    end
    if #graph < 2 then
        text(f, 0.850, 0.650, 0.034, fitText(f, T("storageMonitor_graphFilling", "The graph fills over the next in-game day"), 0.034, 1.25, true),
            COLORS.text, RenderText.ALIGN_CENTER, true)
    end
end

-- the field map: every field of the farm in the colour of its crop's state, its number on it, and a legend
function StorageMonitor:drawFieldMap(f, snapshot)
    local T = StorageMonitor.getText
    local panel = snapshot.panel
    local map = panel.map
    if map == nil or #map.runs == 0 then
        text(f, 0.800, 0.680, 0.040, T("storageMonitor_noFields", "Your farm has no fields"), COLORS.dim, RenderText.ALIGN_CENTER, true)
        return
    end
    local colors = {}
    for _, row in ipairs(panel.rows or {}) do
        colors[string.sub(row.id, 6)] = row.valueColor         -- row ids are "field<id>"
    end
    for _, run in ipairs(map.runs) do
        rect(f, run[1], run[2], run[3], run[4], colorOf(colors[run[5]] or "dim"))
    end
    for _, label in ipairs(map.labels) do
        text(f, label.u, label.v + 0.009, 0.024, label.id, COLORS.text, RenderText.ALIGN_CENTER, true)
    end
    -- the legend
    local u = 0.075
    for _, entry in ipairs({{"ok", "storageMonitor_cropReady", "Harvest"}, {"warn", "storageMonitor_cropPrepare", "Prepare"},
                            {"accent", "storageMonitor_cropGrowing", "Growing"}, {"full", "storageMonitor_cropWithered", "Withered"},
                            {"dim", "storageMonitor_toSow", "To sow"}}) do
        rect(f, u, 0.874, u + 0.016, 0.890, COLORS[entry[1]])
        local label = T(entry[2], entry[3])
        text(f, u + 0.026, 0.889, 0.024, label, COLORS.dim, RenderText.ALIGN_LEFT, false)
        u = u + 0.06 + textWidth(f, 0.024, label, false)
    end
end

--- Splits a text into lines that fit width (design units) at size; "|" starts a new line.
function StorageMonitor.wrapText(f, str, size, width)
    local lines = {}
    for paragraph in (tostring(str) .. "|"):gmatch("(.-)|") do
        local line = ""
        for word in paragraph:gmatch("%S+") do
            local candidate = line == "" and word or (line .. " " .. word)
            if line ~= "" and textWidth(f, size, candidate, true) > width then
                table.insert(lines, line)
                line = word
            else
                line = candidate
            end
            -- a single word longer than the line is shortened
            if textWidth(f, size, line, true) > width then
                line = fitText(f, line, size, width, true)
            end
        end
        table.insert(lines, line)
    end
    while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
    end
    return lines
end

-- the message board: what players wrote, as big as fits, and when it was written
function StorageMonitor:drawMessage(f)
    local spec = self.spec_storageMonitor
    local T = StorageMonitor.getText
    local message = spec.message or ""
    if message == "" then
        text(f, 0.800, 0.500, 0.050, fitText(f, T("storageMonitor_messageEmpty", "Nothing written yet"), 0.050, 1.40, true),
            COLORS.dim, RenderText.ALIGN_CENTER, true)
        text(f, 0.800, 0.590, 0.032, fitText(f, T("storageMonitor_messageHint", "Stand here and press the activate key to write a message"), 0.032, 1.40, false),
            COLORS.dim, RenderText.ALIGN_CENTER, false)
        return
    end
    -- the text in the big lower panel, as big as fits
    local cached = spec.rowCache.message
    if cached == nil or cached.source ~= message then
        local lines, size = nil, 0.030
        for _, s in ipairs({0.070, 0.060, 0.052, 0.045, 0.039, 0.034, 0.030}) do
            size = s
            lines = StorageMonitor.wrapText(f, message, s, 1.40)
            if #lines * s * 1.30 <= 0.45 then
                break
            end
        end
        cached = {source = message, lines = lines, size = size}
        spec.rowCache.message = cached
    end
    local step = cached.size * 1.30
    local height = math.min(0.46, #cached.lines * step)
    local first = 0.420 + (0.470 - height) * 0.5 + cached.size * 0.95
    for i, line in ipairs(cached.lines) do
        local v = first + (i - 1) * step
        if v > 0.89 then
            break
        end
        text(f, 0.110, v, cached.size, line, COLORS.text, RenderText.ALIGN_LEFT, true)
    end
    rect(f, 0.065, first - cached.size * 0.95, 0.073, first - cached.size * 0.95 + height, COLORS.accent)
    -- when it was written, in the top panel
    local t = tonumber(spec.messageTime) or 0
    if t > 0 then
        local day = math.floor(t / 24)
        local minutes = math.floor((t - day * 24) * 60 + 0.5)
        text(f, 0.800, 0.275, 0.044, string.format(T("storageMonitor_messageWritten", "Written on day %d at %02d:%02d"), day,
            math.floor(minutes / 60) % 24, minutes % 60), COLORS.dim, RenderText.ALIGN_CENTER, true)
    end
end

-- one product, big: its icon, name, amount, percent and bar, how fast it changes, and what it is worth
function StorageMonitor:drawSingle(f, snapshot)
    local T = StorageMonitor.getText
    local item = snapshot.single
    local side = 0.30
    if not icon(f, 0.080, 0.455, side, item.icon, iconColor(item)) then
        rect(f, 0.110, 0.485, 0.110 + side * 0.8, 0.485 + side * 0.8, item.color)
    end
    local x0, x1 = 0.430, 1.535
    text(f, x0, 0.520, 0.068, fitText(f, string.upper(tostring(item.title)), 0.068, x1 - x0, true), COLORS.text, RenderText.ALIGN_LEFT, true)
    local amount = snapshot.countMode and item.count ~= nil and string.format("%dx", item.count) or StorageMonitor.formatVolume(item.level)
    text(f, x0, 0.625, 0.082, amount, item.missing and COLORS.full or COLORS.text, RenderText.ALIGN_LEFT, true)
    local pct = percentText(item, snapshot)
    if pct ~= "" then
        text(f, x1, 0.625, 0.082, pct, StorageMonitor.levelColor(itemPercent(item, snapshot)), RenderText.ALIGN_RIGHT, true)
    end
    ratioBarRow(f, x0, 0.655, x1, 0.690, itemFraction(item, snapshot), item.color)
    -- how fast it fills or empties, and when it is full / empty
    if item.rate ~= nil and math.abs(item.rate) >= 1 then
        local str = StorageMonitor.formatRate(item.rate)
        local left, toward = StorageMonitor.hoursLeft(item.level, item.capacity, item.rate)
        if left ~= nil then
            local key = toward == "full" and "storageMonitor_fullIn" or "storageMonitor_emptyIn"
            str = str .. "   " .. string.format(T(key, toward == "full" and "FULL IN %s" or "EMPTY IN %s"), StorageMonitor.formatDuration(left))
        end
        text(f, x0, 0.765, 0.038, str, item.rate > 0 and COLORS.accent or COLORS.warn, RenderText.ALIGN_LEFT, true)
    elseif item.capacity ~= nil and item.capacity > 0 then
        text(f, x0, 0.765, 0.038, StorageMonitor.getText("storageMonitor_free", "FREE") .. "  "
            .. StorageMonitor.formatVolume(math.max(0, item.capacity - item.level)), COLORS.ok, RenderText.ALIGN_LEFT, false)
    end
    -- what it is worth at the best price, and where
    local best = StorageMonitor.bestPrice(item.fillType)
    if best ~= nil then
        local worth = string.format(T("storageMonitor_worthAt", "Worth %s at %s"), StorageMonitor.formatMoney(item.level * best.price), tostring(best.station))
        text(f, x0, 0.845, 0.036, fitText(f, worth, 0.036, x1 - x0, false), COLORS.ok, RenderText.ALIGN_LEFT, false)
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
        elseif StorageMonitor.EMPTY_BOARD[kind] ~= nil then
            local e = StorageMonitor.EMPTY_BOARD[kind]
            msg = StorageMonitor.getText(e[1], e[2])
        end
        text(f, 0.800, 0.680, 0.040, fitText(f, msg, 0.040, 1.40, true), COLORS.dim, RenderText.ALIGN_CENTER, true)
    elseif snapshot.board then
        StorageMonitor.drawRowList(self, f, snapshot, layout, first)
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

    -- slideshow: the next screen when its time is up (not while someone holds the pages)
    local slides = StorageMonitor.activeSlides(spec)
    if slides ~= nil and #slides > 1 and spec.manualTime <= 0 then
        spec.slideTimer = (spec.slideTimer or 0) + dt
        if spec.slideTimer >= (StorageMonitor.SLIDE_TIMES[spec.slideTime] or math.huge) then
            spec.slideTimer = 0
            spec.slideIndex = (spec.slideIndex or 1) % #slides + 1
            self:rescanStorageMonitor()
            StorageMonitor.refreshStorageMonitorData(self)
        end
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
    register("STORAGE_MONITOR_PREV_SCREEN", StorageMonitor.onActionPrevScreen)
    register("STORAGE_MONITOR_NEXT_SCREEN", StorageMonitor.onActionNextScreen)
end

StorageMonitor.SCREEN_ACTIONS = {STORAGE_MONITOR_PREV_SCREEN = true, STORAGE_MONITOR_NEXT_SCREEN = true}

--- The next (+1) or previous (-1) screen, by hand: in a slideshow its next screen (for this player), else the
-- next storage nearby or screen of the farm in the pick list (a setting: everyone sees it).
function StorageMonitor:stepScreen(direction)
    local spec = self.spec_storageMonitor
    local slides = StorageMonitor.activeSlides(spec)
    if slides ~= nil then
        spec.slideIndex = ((spec.slideIndex or 1) - 1 + direction) % #slides + 1
        spec.slideTimer = 0
        self:rescanStorageMonitor()
        StorageMonitor.refreshStorageMonitorData(self)
        return
    end
    local list = StorageMonitor.pickList(spec.candidates or {})
    if #list == 0 then
        return
    end
    local current = 0
    for i, c in ipairs(list) do
        if spec.target ~= nil and c.owner == spec.target.owner then
            current = i
        end
    end
    local nextIndex = current == 0 and (direction > 0 and 1 or #list) or ((current - 1 + direction) % #list + 1)
    local c = list[nextIndex]
    local settings = self:getStorageMonitorSettings()
    settings.pick = {c.anchor[1], c.anchor[2]}
    self:setStorageMonitorSettings(settings)
    self:rescanStorageMonitor()
    StorageMonitor.refreshStorageMonitorData(self)
end

function StorageMonitor.onActionPrevScreen()
    if StorageMonitor.activeMonitor ~= nil then
        StorageMonitor.stepScreen(StorageMonitor.activeMonitor, -1)
    end
end

function StorageMonitor.onActionNextScreen()
    if StorageMonitor.activeMonitor ~= nil then
        StorageMonitor.stepScreen(StorageMonitor.activeMonitor, 1)
    end
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
    local state = (paging and "p" or "-") .. (spec ~= nil and "s" or "-")
    if state == StorageMonitor.actionState then
        return
    end
    StorageMonitor.actionState = state
    for name, eventId in pairs(StorageMonitor.actionEvents) do
        if StorageMonitor.SCREEN_ACTIONS[name] then
            g_inputBinding:setActionEventActive(eventId, spec ~= nil)
        else
            g_inputBinding:setActionEventActive(eventId, paging)
        end
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
    local kind = spec.target ~= nil and spec.target.kind or nil
    if kind == "message" then
        table.insert(entries, 1, {text = T("storageMonitor_menuMessage", "Write the message"),
            run = function() StorageMonitor.openMessage(monitor) end})
    end
    table.insert(entries, {text = spec.connected and T("storageMonitor_menuConnectedOff", "Show only this silo")
        or T("storageMonitor_menuConnectedOn", "Also show the silos connected to it"),
        run = function() change(monitor, "connected", not spec.connected) end})
    if spec.mountNode ~= nil then
        table.insert(entries, {text = string.format(T("storageMonitor_menuSize", "Screen size (now: %.1f m wide)"), spec.mountWidth),
            run = function() StorageMonitor.openSize(monitor) end})
        if spec.mountMode == "silo" then
            table.insert(entries, {text = string.format(T("storageMonitor_menuHeight", "Height (now: %.1f m above the ground)"), spec.mountBottom),
                run = function() StorageMonitor.openHeight(monitor) end})
        end
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
    if kind ~= nil and kind ~= "message" and not StorageMonitor.BOARD_KINDS[kind] and kind ~= "finance" then
        table.insert(entries, {text = string.format(T("storageMonitor_menuOnly", "Products shown (now: %s)"), StorageMonitor.onlyLabel(spec)),
            run = function() StorageMonitor.openOnly(monitor) end})
    end
    local alerts = StorageMonitor.ALERT_LEVELS[spec.alerts] or StorageMonitor.ALERT_LEVELS[1]
    table.insert(entries, {text = string.format(T("storageMonitor_menuAlerts", "Alerts (now: %s)"), T(alerts.key, alerts.fallback)),
        run = function() StorageMonitor.openAlerts(monitor) end})
    table.insert(entries, {text = string.format(T("storageMonitor_menuFullAt", "Nearly full from (now: %d%%)"), spec.fullAt),
        run = function() StorageMonitor.openFullAt(monitor) end})
    table.insert(entries, {text = string.format(T("storageMonitor_menuPriceAlert", "Price alert (now: %s)"), StorageMonitor.priceAlertLabel(spec.priceAlert)),
        run = function() StorageMonitor.openPriceAlert(monitor) end})
    table.insert(entries, {text = string.format(T("storageMonitor_menuSlideshow", "Slideshow (now: %s)"), StorageMonitor.slideshowLabel(spec)),
        run = function() StorageMonitor.openSlideshow(monitor) end})

    local options = {}
    for _, e in ipairs(entries) do
        table.insert(options, e.text)
    end
    StorageMonitor.showOptions(T("storageMonitor_menuTitle", "Better Digital Display"),
        string.format(T("storageMonitor_menuText", "Showing: %s"), current), options,
        function(index)
            local e = entries[index]
            if e ~= nil then
                e.run()
            end
        end)
end

-- what a menu offers: the storages nearby (nearest first, at most MAX_PICK), then every screen of the farm
function StorageMonitor.pickList(candidates)
    local list, nearby = {}, 0
    for _, c in ipairs(candidates) do
        if StorageMonitor.FARM_KINDS[c.kind] == nil and nearby < StorageMonitor.MAX_PICK then
            nearby = nearby + 1
            table.insert(list, c)
        end
    end
    for _, c in ipairs(candidates) do
        if StorageMonitor.FARM_KINDS[c.kind] ~= nil then
            table.insert(list, c)
        end
    end
    return list
end

local function candidateLabel(c)
    if StorageMonitor.FARM_KINDS[c.kind] ~= nil then
        return tostring(c.name)
    end
    return string.format("%s  (%s)", tostring(c.name), formatDistance(c.distance))
end

function StorageMonitor.openPick(monitor)
    local spec = monitor.spec_storageMonitor
    local candidates = StorageMonitor.pickList(spec.candidates)
    local options = {StorageMonitor.getText("storageMonitor_pickNearest", "Always the nearest") .. mark(spec.pick == nil)}
    for _, c in ipairs(candidates) do
        local isCurrent = spec.pick ~= nil and spec.target ~= nil and spec.target.owner == c.owner
        table.insert(options, candidateLabel(c) .. mark(isCurrent))
    end
    local hint = StorageMonitor.activeSlides(spec) ~= nil
        and StorageMonitor.getText("storageMonitor_pickTextSlides", "The slideshow is on: it shows its own screens. Storages near this monitor, nearest first, then your whole farm:")
        or StorageMonitor.getText("storageMonitor_pickText", "Storages near this monitor, nearest first, then your whole farm:")
    StorageMonitor.showOptions(StorageMonitor.getText("storageMonitor_pickTitle", "Pick the storage"), hint, options,
        function(index)
            if index == 1 then
                change(monitor, "pick", nil)
            elseif index ~= nil and index > 1 and candidates[index - 1] ~= nil then
                local c = candidates[index - 1]
                change(monitor, "pick", {c.anchor[1], c.anchor[2]})
            end
        end)
end

-- the message board's text: typed in the game's text dialog ("|" starts a new line); empty clears it
function StorageMonitor.openMessage(monitor)
    local spec = monitor.spec_storageMonitor
    StorageMonitor.showTextInput(StorageMonitor.getText("storageMonitor_messagePrompt", "Message for everyone (| starts a new line, empty clears it)"),
        spec.message, StorageMonitor.MESSAGE_MAX,
        function(text)
            text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            local settings = monitor:getStorageMonitorSettings()
            settings.message = text
            settings.messageTime = text ~= "" and (StorageMonitor.gameHours() or 0) or 0
            monitor:setStorageMonitorSettings(settings)
            StorageMonitor.refreshStorageMonitorData(monitor)
        end)
end

-- "all", "Wheat", or "3 products"
function StorageMonitor.onlyLabel(spec)
    local T = StorageMonitor.getText
    local only = spec.only or {}
    if #only == 0 then
        return T("storageMonitor_onlyAll", "all")
    elseif #only == 1 then
        local index = g_fillTypeManager ~= nil and call(g_fillTypeManager, "getFillTypeIndexByName", only[1]) or nil
        local info = index ~= nil and fillTypeInfo(index) or nil
        return tostring(info ~= nil and info.title or only[1])
    end
    return string.format(T("storageMonitor_onlyCount", "%d products"), #only)
end

-- which products the screen shows: all, or ticked ones (one ticked: shown big); the menu stays open while ticking
function StorageMonitor.openOnly(monitor)
    local spec = monitor.spec_storageMonitor
    local T = StorageMonitor.getText
    local snapshot = spec.snapshot
    local items = snapshot ~= nil and (snapshot.allItems or snapshot.items) or {}
    local ticked = {}
    for _, name in ipairs(spec.only) do
        ticked[name] = true
    end
    local options = {T("storageMonitor_onlyAllOption", "All products") .. mark(#spec.only == 0)}
    local listed = {}
    for _, item in ipairs(items) do
        if #listed < StorageMonitor.MAX_PICK then
            table.insert(listed, item)
            table.insert(options, (ticked[item.name] and "[x]  " or "[  ]  ") .. tostring(item.title))
        end
    end
    table.insert(options, T("storageMonitor_done", "Done"))
    StorageMonitor.showOptions(T("storageMonitor_onlyTitle", "Products shown"),
        string.format(T("storageMonitor_onlyText", "Tick the products to show (up to %d). One product is shown big:"), StorageMonitor.ONLY_MAX),
        options,
        function(index)
            local settings = monitor:getStorageMonitorSettings()
            if index == 1 then
                settings.only = {}
            else
                local item = index ~= nil and listed[index - 1] or nil
                if item == nil then
                    return          -- done
                end
                local only = {}
                for _, name in ipairs(settings.only) do
                    if name ~= item.name then
                        table.insert(only, name)
                    end
                end
                if not ticked[item.name] and #only < StorageMonitor.ONLY_MAX then
                    table.insert(only, item.name)
                end
                settings.only = only
            end
            monitor:setStorageMonitorSettings(settings)
            StorageMonitor.refreshStorageMonitorData(monitor)
            if index ~= 1 then
                StorageMonitor.openOnly(monitor)
            end
        end)
end

-- "Wheat above $480", or "off"
function StorageMonitor.priceAlertLabel(priceAlert)
    local T = StorageMonitor.getText
    if priceAlert == nil then
        return T("storageMonitor_alerts1", "Off")
    end
    local title = priceAlert.fill
    local index = g_fillTypeManager ~= nil and call(g_fillTypeManager, "getFillTypeIndexByName", priceAlert.fill) or nil
    local info = index ~= nil and fillTypeInfo(index) or nil
    if info ~= nil then
        title = info.title
    end
    return string.format(T("storageMonitor_priceAbove", "%s from %s"), tostring(title), StorageMonitor.formatMoney(priceAlert.price))
end

-- "3 screens, 20 s each", or "off"
function StorageMonitor.slideshowLabel(spec)
    local T = StorageMonitor.getText
    if StorageMonitor.activeSlides(spec) == nil then
        return T("storageMonitor_alerts1", "Off")
    end
    return string.format(T("storageMonitor_slidesNow", "%d screens, %d s each"), #spec.slides,
        math.floor((StorageMonitor.SLIDE_TIMES[spec.slideTime] or 0) / 1000))
end

function StorageMonitor.openFullAt(monitor)
    local spec = monitor.spec_storageMonitor
    local options = {}
    for _, level in ipairs(StorageMonitor.FULL_LEVELS) do
        table.insert(options, string.format("%d%%", level) .. mark(level == spec.fullAt))
    end
    StorageMonitor.showOptions(StorageMonitor.getText("storageMonitor_fullAtTitle", "Nearly full from"),
        StorageMonitor.getText("storageMonitor_fullAtText", "From what level a silo, shed or heap counts as nearly full: the alert, and red on the screen (amber from 15 below):"),
        options,
        function(index)
            if StorageMonitor.FULL_LEVELS[index] ~= nil then
                change(monitor, "fullAt", StorageMonitor.FULL_LEVELS[index])
            end
        end)
end

-- the price alert: first the product (what the screen shows, else the farm's silos), then the price
function StorageMonitor.openPriceAlert(monitor)
    local spec = monitor.spec_storageMonitor
    local T = StorageMonitor.getText
    local items = spec.snapshot ~= nil and spec.snapshot.items or {}
    if #items == 0 then          -- a screen without products: the products of all silos of the farm
        for _, c in ipairs(spec.candidates or {}) do
            if c.kind == "farm" then
                local sources = {}
                for _, storage in ipairs(c.storages) do
                    table.insert(sources, {storage = storage})
                end
                items = StorageMonitor.buildSnapshot(sources, nil, fillTypeInfo).items or {}
            end
        end
    end
    local products = {}
    for _, item in ipairs(items) do
        local best = StorageMonitor.bestPrice(item.fillType)
        if best ~= nil and #products < StorageMonitor.MAX_PICK then
            table.insert(products, {item = item, best = best})
        end
    end
    local options = {T("storageMonitor_alerts1", "Off") .. mark(spec.priceAlert == nil)}
    for _, p in ipairs(products) do
        local isCurrent = spec.priceAlert ~= nil and spec.priceAlert.fill == p.item.name
        table.insert(options, string.format(T("storageMonitor_priceNow", "%s (now %s at %s)"), tostring(p.item.title),
            StorageMonitor.formatMoney(p.best.price * 1000), tostring(p.best.station)) .. mark(isCurrent))
    end
    StorageMonitor.showOptions(T("storageMonitor_priceAlertTitle", "Price alert"),
        #products > 0 and T("storageMonitor_priceAlertText", "Tell me when a product sells for more (price per 1000 l). The product:")
            or T("storageMonitor_priceAlertNone", "Nothing here sells anywhere. Pick a storage with products first."),
        options,
        function(index)
            if index == 1 then
                change(monitor, "priceAlert", nil)
            elseif index ~= nil and products[index - 1] ~= nil then
                StorageMonitor.openPriceStep(monitor, products[index - 1])
            end
        end)
end

function StorageMonitor.openPriceStep(monitor, product)
    local T = StorageMonitor.getText
    local now = product.best.price * 1000
    local prices, options = {}, {}
    for _, step in ipairs(StorageMonitor.PRICE_STEPS) do
        local price = math.floor(now * step + 0.5)
        table.insert(prices, price)
        table.insert(options, string.format(T("storageMonitor_priceStep", "From %s (+%d%%)"), StorageMonitor.formatMoney(price),
            math.floor((step - 1) * 100 + 0.5)))
    end
    StorageMonitor.showOptions(T("storageMonitor_priceAlertTitle", "Price alert"),
        string.format(T("storageMonitor_priceStepText", "%s sells for %s per 1000 l now. Tell me from:"), tostring(product.item.title),
            StorageMonitor.formatMoney(now)),
        options,
        function(index)
            if prices[index] ~= nil then
                change(monitor, "priceAlert", {fill = product.item.name, price = prices[index]})
            end
        end)
end

-- the slideshow: its time per screen, and a tick per screen (choosing one ticks it or not, the menu stays open)
function StorageMonitor.openSlideshow(monitor)
    local spec = monitor.spec_storageMonitor
    local T = StorageMonitor.getText
    local candidates = StorageMonitor.pickList(spec.candidates or {})
    local function slideOf(c)
        for i, slide in ipairs(spec.slides) do
            if math.sqrt((slide[1] - c.anchor[1]) ^ 2 + (slide[2] - c.anchor[2]) ^ 2) <= StorageMonitor.PICK_TOLERANCE then
                return i
            end
        end
        return nil
    end
    local seconds = math.floor((StorageMonitor.SLIDE_TIMES[spec.slideTime] or 0) / 1000)
    local options = {spec.slideTime > 1 and string.format(T("storageMonitor_slideTimeNow", "Time per screen (now: %d s)"), seconds)
        or T("storageMonitor_slideTimeOff", "Time per screen (now: off)")}
    for _, c in ipairs(candidates) do
        table.insert(options, (slideOf(c) ~= nil and "[x]  " or "[  ]  ") .. candidateLabel(c))
    end
    table.insert(options, T("storageMonitor_done", "Done"))
    StorageMonitor.showOptions(T("storageMonitor_slideshowTitle", "Slideshow"),
        string.format(T("storageMonitor_slideshowText", "Tick the screens the monitor takes turns showing (up to %d):"), StorageMonitor.MAX_SLIDES),
        options,
        function(index)
            if index == 1 then
                StorageMonitor.openSlideTime(monitor)
                return
            end
            local c = index ~= nil and candidates[index - 1] or nil
            if c == nil then
                return          -- done
            end
            local settings = monitor:getStorageMonitorSettings()
            local slides = settings.slides
            local i = slideOf(c)
            if i ~= nil then
                table.remove(slides, i)
            elseif #slides < StorageMonitor.MAX_SLIDES then
                table.insert(slides, {c.anchor[1], c.anchor[2]})
            end
            if #slides > 0 and settings.slideTime <= 1 then
                settings.slideTime = StorageMonitor.DEFAULT_SLIDE_TIME
            end
            monitor:setStorageMonitorSettings(settings)
            monitor:rescanStorageMonitor()
            StorageMonitor.refreshStorageMonitorData(monitor)
            StorageMonitor.openSlideshow(monitor)
        end)
end

function StorageMonitor.openSlideTime(monitor)
    local spec = monitor.spec_storageMonitor
    local T = StorageMonitor.getText
    local options = {}
    for i, ms in ipairs(StorageMonitor.SLIDE_TIMES) do
        local label = ms == 0 and T("storageMonitor_slideOff", "Off: show the picked storage")
            or string.format(T("storageMonitor_seconds", "%d s"), math.floor(ms / 1000))
        table.insert(options, label .. mark(i == spec.slideTime))
    end
    StorageMonitor.showOptions(T("storageMonitor_slideshowTitle", "Slideshow"),
        T("storageMonitor_slideTimeText", "How long each screen shows:"), options,
        function(index)
            if StorageMonitor.SLIDE_TIMES[index] ~= nil then
                change(monitor, "slideTime", index)
                StorageMonitor.openSlideshow(monitor)
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

-- a raised mount (silo mount, wall mount, hanging): how high its bottom edge is above the ground
function StorageMonitor.openHeight(monitor)
    local spec = monitor.spec_storageMonitor
    local T = StorageMonitor.getText
    local heights, options = StorageMonitor.HEIGHTS, {}
    for _, h in ipairs(heights) do
        local option = string.format(T("storageMonitor_heightOption", "%.1f m"), h)
        if math.abs(h - (spec.mountBottomDefault or -1)) < 0.01 then
            option = option .. " " .. T("storageMonitor_heightDefault", "(as bought)")
        end
        table.insert(options, option .. mark(math.abs(h - spec.mountBottom) < 0.01))
    end
    StorageMonitor.showOptions(T("storageMonitor_heightTitle", "Height"),
        T("storageMonitor_heightText", "How high the bottom edge of the screen is above the ground. The screen grows upwards from it."), options,
        function(index)
            if heights[index] ~= nil then
                change(monitor, "height", heights[index])
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

-- ---------------------------------------------------------------------------------------------------
-- the history the server keeps: every SERVER_INTERVAL the server reads each monitor's screen (the picked one,
-- else the nearest; not the slideshow's) and keeps a sample every GRAPH_STEP, saved with the game and sent to
-- every player. Players then draw the same history, also right after joining or a restart.
-- ---------------------------------------------------------------------------------------------------

StorageMonitor.SERVER_INTERVAL = 15000      -- ms between the server's reads
StorageMonitor.SERVER_SCAN = 120000         -- ms between the server's looks for the storages around a monitor

function StorageMonitor.anchorKey(anchor)
    if anchor == nil then
        return nil
    end
    return string.format("%.1f,%.1f", anchor[1], anchor[2])
end

-- the server's history when it belongs to the screen shown, else nil
function StorageMonitor.serverGraphFor(spec, target)
    local history = spec.serverHistory
    if history == nil or history.graph == nil or #history.graph == 0 or target == nil then
        return nil
    end
    if history.key ~= StorageMonitor.anchorKey(target.anchor) then
        return nil
    end
    return history.graph
end

-- a sample from the server (an event, on every player's game): a new screen starts a new history
function StorageMonitor.addServerSample(monitor, key, sample, reset)
    local spec = monitor.spec_storageMonitor
    local history = spec.serverHistory
    if reset or history == nil or history.key ~= key then
        history = {key = key, graph = {}}
        spec.serverHistory = history
    end
    local graph = history.graph
    local last = graph[#graph]
    if last == nil or sample.t > last.t + 1e-6 then
        table.insert(graph, sample)
    end
    while #graph > 1 and sample.t - graph[1].t > StorageMonitor.GRAPH_SPAN + 1e-6 do
        table.remove(graph, 1)
    end
end

-- the value the history follows for a candidate: how full (sheds: bales or pallets), or the farm's balance
function StorageMonitor.historyValue(monitor, c)
    local spec = monitor.spec_storageMonitor
    if c.kind == "finance" then
        local panel = StorageMonitor.buildPanel({kind = "finance"})
        return panel ~= nil and panel.money or nil, nil
    end
    if c.kind == "objects" and c.objectStorage ~= nil then
        local o = c.objectStorage
        local capacity = tonumber(o.capacity) or 0
        return tonumber(o.numStoredObjects) or 0, capacity > 0 and capacity or nil
    end
    local storages = c.storages
    if spec.connected and #storages > 0 then
        storages = StorageMonitor.connectedStorages(storages, getPlayerFarmId())
    end
    local sources = {}
    for _, storage in ipairs(storages) do
        table.insert(sources, {storage = storage})
    end
    for _, extra in ipairs(c.extra or {}) do
        table.insert(sources, extra)
    end
    local snapshot = StorageMonitor.buildSnapshot(sources, c.roles, fillTypeInfo)
    return snapshot.used, snapshot.capacity > 0 and snapshot.capacity or nil
end

-- the server reads one monitor: a new sample goes to every player
function StorageMonitor.serverSample(monitor, now, dt)
    StorageMonitor.farmOverride = call(monitor, "getOwnerFarmId") or 1
    StorageMonitor.serverSampleNow(monitor, now, dt)
    StorageMonitor.farmOverride = nil
end

function StorageMonitor.serverSampleNow(monitor, now, dt)
    local spec = monitor.spec_storageMonitor
    spec.serverScanTimer = (spec.serverScanTimer or math.huge) + dt
    if spec.serverCandidates == nil or spec.serverScanTimer >= StorageMonitor.SERVER_SCAN or spec.serverPickKey ~= StorageMonitor.anchorKey(spec.pick) then
        spec.serverCandidates = StorageMonitor.collectStorageCandidates(monitor)
        spec.serverScanTimer = 0
        spec.serverPickKey = StorageMonitor.anchorKey(spec.pick)
    end
    local c = StorageMonitor.choose(spec.serverCandidates, spec.pick)
    if c == nil or StorageMonitor.BOARD_KINDS[c.kind] or c.kind == "message" then
        return
    end
    local key = StorageMonitor.anchorKey(c.anchor)
    local value, capacity = StorageMonitor.historyValue(monitor, c)
    if value == nil then
        return
    end
    local history = spec.serverHistory
    local reset = history == nil or history.key ~= key
    if reset then
        history = {key = key, graph = {}}
        spec.serverHistory = history
    end
    local last = history.graph[#history.graph]
    StorageMonitor.updateGraph(history, now, value, capacity)
    local newest = history.graph[#history.graph]
    if newest ~= nil and newest ~= last and g_server ~= nil and g_server.broadcastEvent ~= nil and StorageMonitorGraphEvent ~= nil then
        -- a history that just started (another screen, or the time jumped) starts again on every game too
        g_server:broadcastEvent(StorageMonitorGraphEvent.new(monitor, key, newest, #history.graph == 1), false)
    end
end

-- on the server: every monitor now and then
function StorageMonitor.updateServer(dt)
    StorageMonitor.serverTimer = (StorageMonitor.serverTimer or 0) + dt
    if StorageMonitor.serverTimer < StorageMonitor.SERVER_INTERVAL then
        return
    end
    local elapsed = StorageMonitor.serverTimer
    StorageMonitor.serverTimer = 0
    local now = StorageMonitor.gameHours()
    if now == nil then
        return
    end
    for _, monitor in ipairs(StorageMonitor.instances) do
        local spec = monitor.spec_storageMonitor
        if spec ~= nil and spec.serverSampling then
            -- its last sample stopped in an error (the game logged it): no history for this monitor from now on
            spec.serverSampling = nil
            spec.serverFailed = true
            StorageMonitor.log("Warning: no history kept for a monitor after the error above")
        end
        if spec ~= nil and not spec.serverFailed then
            spec.serverSampling = true
            StorageMonitor.serverSample(monitor, now, elapsed)
            spec.serverSampling = nil
        end
    end
end

StorageMonitor.Listener = {}

function StorageMonitor.Listener:update(dt)
    if g_currentMission == nil then
        return
    end
    -- An error is not caught: the game logs it with its stack. Each step marks what it is doing, so after an
    -- error the step that stopped is found on the next frame and switched off with one log line: a broken
    -- monitor neither repeats its error every frame nor keeps the other monitors from updating.
    StorageMonitor.farmOverride = nil
    -- the server keeps the history (also a dedicated server, which draws nothing)
    if g_server ~= nil then
        StorageMonitor.updateServer(dt or 0)
    end
    if not g_currentMission:getIsClient() then
        return
    end
    StorageMonitor.clock = StorageMonitor.clock + (dt or 0)
    for _, monitor in ipairs(StorageMonitor.instances) do
        local spec = monitor.spec_storageMonitor
        if spec ~= nil and spec.updating then
            spec.updating = nil
            spec.failed = true
            spec.isNear = false
            StorageMonitor.log("Error, monitor switched off after the error above")
        end
        if spec ~= nil and not spec.failed then
            spec.updating = true
            StorageMonitor.updateStorageMonitor(monitor, dt)
            spec.updating = nil
        end
    end
    if StorageMonitor.keysBusy then
        StorageMonitor.keysBusy = nil
        StorageMonitor.keysFailed = true
        StorageMonitor.log("Error, monitor keys switched off after the error above")
    end
    if not StorageMonitor.keysFailed then
        StorageMonitor.keysBusy = true
        StorageMonitor.updateActionEvents()
        StorageMonitor.openPendingDialog()
        StorageMonitor.keysBusy = nil
    end
end

function StorageMonitor.Listener:draw()
    if g_currentMission == nil or not g_currentMission:getIsClient() then
        return
    end
    -- the last draw stopped in an error (the game logged it): the text state goes back to the game's, and that
    -- monitor is switched off
    local broken = StorageMonitor.drawingMonitor
    if broken ~= nil then
        StorageMonitor.drawingMonitor = nil
        if setTextDepthTestEnabled ~= nil then
            setTextDepthTestEnabled(false)
        end
        StorageMonitor.resetTextState(broken)
        if broken.spec_storageMonitor ~= nil then
            broken.spec_storageMonitor.isNear = false
            broken.spec_storageMonitor.failed = true
        end
        StorageMonitor.log("Error drawing, monitor switched off after the error above")
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
                    StorageMonitor.drawingMonitor = monitor
                    StorageMonitor.drawStorageMonitor(monitor, face)
                    StorageMonitor.drawingMonitor = nil
                end
                -- bars of a face nobody looks at are hidden, like its text
                StorageMonitor.endBars(spec, face)
            end
        end
    end
    if depthSet then
        setTextDepthTestEnabled(false)
    end
end

addModEventListener(StorageMonitor.Listener)

-- the keys in front of a monitor (pages, screens) are registered with the player's own action events, as the
-- game's on-foot actions are (they were never registered before 1.4: Page Up / Page Down did nothing)
if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil and Utils ~= nil then
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents, function()
            StorageMonitor.registerActionEvents()
        end)
end

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
