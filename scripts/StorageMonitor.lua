-- Storage Monitor (DTM Mods): a placeable screen that shows the nearest silo, production or animal storage
-- live: used and total capacity, percent full, and every product with its own colour and bar.
--
-- The model holds a dark "screen" texture with the panels baked in. Everything that changes is drawn on
-- top of it every frame, on the client only: text with renderText3D, bars with drawDebugTriangle. Both
-- are depth tested so walls and vehicles hide them. Nothing is drawn on a dedicated server.
--
-- Screen coordinates ("design units"): u from 0 (left) to 1.6 (right), v from 0 (top) to 1 (bottom).
-- The screen node sits in the centre of the glass, x right, y up, z out of the glass towards the viewer.

StorageMonitor = {}
StorageMonitor.MOD_NAME = g_currentModName
StorageMonitor.MOD_DIR = g_currentModDirectory
StorageMonitor.SAVE_KEY = (g_currentModName or "FS25_Monitor") .. ".storageMonitor"
StorageMonitor.instances = {}

StorageMonitor.DESIGN_W = 1.6               -- screen aspect is 16:10
StorageMonitor.ROWS = 7                     -- product rows per page
StorageMonitor.PAGE_TIME = 6000             -- ms per page
StorageMonitor.DATA_INTERVAL = 1000         -- ms between fill level reads while someone is close
StorageMonitor.SCAN_INTERVAL = 15000        -- ms between looks for the nearest storage
StorageMonitor.MIN_LEVEL = 1                -- products below this many litres are not listed
StorageMonitor.OFFSET_BAR = 0.006           -- metres in front of the glass: bars
StorageMonitor.OFFSET_TEXT = 0.009          -- metres in front of the glass: text
StorageMonitor.MAX_OFFSET = 15              -- "switch storage" goes through the 16 nearest storages

-- Layout, in design units. tools/make_textures.py bakes the panels at the same places (tests compare).
StorageMonitor.LAYOUT = {
    header      = {0.000, 0.000, 1.600, 0.105},
    capPanel    = {0.035, 0.130, 1.565, 0.370},
    listPanel   = {0.035, 0.395, 1.565, 0.905},
    footer      = {0.000, 0.930, 1.600, 1.000},
    listHeadV   = 0.440,
    listTopV    = 0.468,
    rowH        = 0.062,
    stackBar    = {0.420, 0.235, 1.530, 0.285},
    rowBarU     = {0.700, 1.170},
    rowBarHalfH = 0.011,
    pageBar     = {0.600, 0.962, 1.000, 0.968},
}

-- colours (r, g, b, a)
StorageMonitor.COLORS = {
    text      = {0.90, 0.95, 1.00, 1},
    dim       = {0.50, 0.58, 0.69, 1},
    accent    = {0.22, 0.88, 1.00, 1},
    track     = {0.10, 0.15, 0.24, 1},
    stackFree = {0.10, 0.16, 0.26, 1},
    ok        = {0.20, 0.83, 0.60, 1},
    warn      = {0.98, 0.75, 0.14, 1},
    full      = {0.97, 0.44, 0.44, 1},
    input     = {0.38, 0.65, 0.98, 1},
    output    = {0.98, 0.70, 0.30, 1},
}

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
function StorageMonitor.buildSnapshot(sources, roles, fillTypeInfo)
    local levels, itemCaps = {}, {}
    local used, capacity = 0, 0

    for _, src in ipairs(sources) do
        local fillLevels, shared, perType = nil, nil, nil
        if src.storage ~= nil then
            local storage = src.storage
            fillLevels = storage:getFillLevels() or {}
            if type(storage.capacity) == "number" and storage.capacity > 0 then
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
                capacity = capacity + perType[fillType]
            end
        end
    end

    local items = {}
    for fillType, level in pairs(levels) do
        if level >= StorageMonitor.MIN_LEVEL then
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
    SpecializationUtil.registerFunction(placeableType, "setStorageMonitorOffset", StorageMonitor.setStorageMonitorOffset)
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
    schema:register(XMLValueType.FLOAT, basePath .. ".storageMonitor#searchRadius", "Storages further away are not shown", 250)
    schema:register(XMLValueType.NODE_INDEX, basePath .. ".storageMonitor#playerTrigger", "Trigger for the 'switch storage' action")
    schema:setXMLSpecializationType()
end

function StorageMonitor.initSpecialization()
    local schema = Placeable.xmlSchemaSavegame
    schema:register(XMLValueType.INT, "placeables.placeable(?)." .. StorageMonitor.SAVE_KEY .. "#offset", "Which storage is shown: 0 = the nearest, 1 = the second nearest, ...", 0)
end

function StorageMonitor:onLoad(savegame)
    self.spec_storageMonitor = {}
    local spec = self.spec_storageMonitor
    local xmlFile = self.xmlFile

    spec.screenNode = xmlFile:getValue("placeable.storageMonitor#screenNode", nil, self.components, self.i3dMappings)
    spec.width = xmlFile:getValue("placeable.storageMonitor#width", 2.4)
    spec.height = spec.width / StorageMonitor.DESIGN_W
    spec.drawDistance = xmlFile:getValue("placeable.storageMonitor#drawDistance", 45)
    spec.searchRadius = xmlFile:getValue("placeable.storageMonitor#searchRadius", 250)
    spec.playerTrigger = xmlFile:getValue("placeable.storageMonitor#playerTrigger", nil, self.components, self.i3dMappings)

    spec.offset = 0
    spec.candidateCount = 0
    spec.target = nil
    spec.snapshot = nil
    spec.page = 1
    spec.pageTime = 0
    spec.dataTimer = math.huge
    spec.scanTimer = math.huge
    spec.isNear = false
    spec.frame = nil
    spec.rowTitles = {}

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
    if spec.playerTrigger ~= nil and self.isClient then
        removeTrigger(spec.playerTrigger)
    end
    if spec.activatable ~= nil and g_currentMission ~= nil and g_currentMission.activatableObjectsSystem ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
    end
end

function StorageMonitor:loadFromXMLFile(xmlFile, key)
    local spec = self.spec_storageMonitor
    if spec ~= nil then
        spec.offset = math.max(0, math.min(StorageMonitor.MAX_OFFSET, xmlFile:getValue(key .. "#offset", 0) or 0))
    end
end

function StorageMonitor:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_storageMonitor
    if spec ~= nil then
        xmlFile:setValue(key .. "#offset", spec.offset)
    end
end

function StorageMonitor:onWriteStream(streamId, connection)
    streamWriteUInt8(streamId, self.spec_storageMonitor.offset)
end

function StorageMonitor:onReadStream(streamId, connection)
    self.spec_storageMonitor.offset = streamReadUInt8(streamId)
end

function StorageMonitor:setStorageMonitorOffset(offset, noEventSend)
    local spec = self.spec_storageMonitor
    offset = math.max(0, math.min(StorageMonitor.MAX_OFFSET, offset or 0))
    spec.offset = offset
    spec.scanTimer = math.huge
    spec.page = 1
    spec.pageTime = 0
    StorageMonitorOffsetEvent.sendEvent(self, offset, noEventSend)
end

function StorageMonitor:storageMonitorTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    local spec = self.spec_storageMonitor
    if spec.activatable == nil or g_localPlayer == nil or otherId ~= g_localPlayer.rootNode then
        return
    end
    if onEnter then
        g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
    elseif onLeave then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
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
        text = spec.target.name
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

--- All storages this monitor could show, nearest first: {name, distance, sources, roles, owner}
function StorageMonitor:collectStorageCandidates()
    local spec = self.spec_storageMonitor
    local mission = g_currentMission
    if mission == nil or mission.storageSystem == nil then
        return {}
    end
    local mx, _, mz = getWorldTranslation(self.rootNode)
    local farmId = getPlayerFarmId()
    local byOwner, order = {}, {}

    local function candidateFor(owner, name)
        local c = byOwner[owner]
        if c == nil then
            c = {owner = owner, name = name, distance = math.huge, storages = {}, storageList = {}, roles = nil, extra = {}}
            byOwner[owner] = c
            table.insert(order, c)
        end
        return c
    end
    local function near(c, pos)
        if pos ~= nil then
            local d = math.sqrt((pos[1] - mx) ^ 2 + (pos[3] - mz) ^ 2)
            if d < c.distance then
                c.distance = d
            end
        end
    end
    local function addStorage(c, storage)
        if not c.storages[storage] then
            c.storages[storage] = true
            table.insert(c.storageList, storage)
            near(c, nodePosition(storage.rootNode))
            if storage.owningPlaceable ~= nil then
                near(c, nodePosition(storage.owningPlaceable.rootNode))
            end
        end
    end

    -- silos, silo extensions, animal storages: everything behind a loading or unloading station
    local storageSystem = mission.storageSystem
    local function addStations(stations, field)
        if type(stations) ~= "table" then
            return
        end
        for _, station in pairs(stations) do
            if type(station) == "table" and not station.isSellingPoint then
                local accessible = {}
                eachStorage(station[field], function(storage)
                    local ok = true
                    if station.hasFarmAccessToStorage ~= nil then
                        ok = station:hasFarmAccessToStorage(farmId, storage)
                    end
                    if ok then
                        table.insert(accessible, storage)
                    end
                end)
                if #accessible > 0 then
                    local owner = station.owningPlaceable or station
                    local fallback = station.getName ~= nil and station:getName() or "Storage"
                    local c = candidateFor(owner, placeableName(station.owningPlaceable, fallback))
                    near(c, nodePosition(owner.rootNode))
                    near(c, nodePosition(station.rootNode))
                    for _, storage in ipairs(accessible) do
                        addStorage(c, storage)
                    end
                end
            end
        end
    end
    if storageSystem.getLoadingStations ~= nil then
        addStations(storageSystem:getLoadingStations(), "sourceStorages")
    end
    if storageSystem.getUnloadingStations ~= nil then
        addStations(storageSystem:getUnloadingStations(), "targetStorages")
    end

    -- productions of this farm: their storage and which products go in or come out
    local chain = mission.productionChainManager
    if chain ~= nil and chain.getProductionPointsForFarmId ~= nil then
        for _, pp in ipairs(chain:getProductionPointsForFarmId(farmId) or {}) do
            if pp.storage ~= nil and pp.storage.getFillLevels ~= nil then
                local owner = pp.owningPlaceable or pp
                local fallback = pp.getName ~= nil and pp:getName() or "Production"
                local c = candidateFor(owner, placeableName(pp.owningPlaceable, fallback))
                near(c, nodePosition(owner.rootNode))
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
    end

    -- animal feed troughs (not a Storage): add the food levels to the barn's entry
    for owner, c in pairs(byOwner) do
        local food = type(owner) == "table" and owner.spec_husbandryFood or nil
        if food ~= nil and type(food.fillLevels) == "table" then
            table.insert(c.extra, {levels = food.fillLevels, capacity = tonumber(food.capacity)})
        end
    end

    local result = {}
    for _, c in ipairs(order) do
        if c.distance <= spec.searchRadius then
            local sources = {}
            for _, storage in ipairs(c.storageList) do
                table.insert(sources, {storage = storage})
            end
            for _, extra in ipairs(c.extra) do
                table.insert(sources, extra)
            end
            table.insert(result, {name = c.name, distance = c.distance, sources = sources, roles = c.roles, owner = c.owner})
        end
    end
    table.sort(result, function(a, b)
        if math.abs(a.distance - b.distance) > 0.01 then
            return a.distance < b.distance
        end
        return tostring(a.name) < tostring(b.name)
    end)
    return result
end

function StorageMonitor:rescanStorageMonitor()
    local spec = self.spec_storageMonitor
    local candidates = self:collectStorageCandidates()
    spec.candidateCount = #candidates
    local previous = spec.target
    if #candidates == 0 then
        spec.target = nil
    else
        spec.target = candidates[(spec.offset % #candidates) + 1]
    end
    if previous == nil or spec.target == nil or previous.owner ~= spec.target.owner then
        spec.page = 1
        spec.pageTime = 0
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
    return {name = fillType.name, title = fillType.title or fillType.name}
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
    spec.rowTitles = {}         -- shortened titles are measured again on the next frame
    local pages = math.max(1, math.ceil(snapshot.count / StorageMonitor.ROWS))
    if spec.page > pages then
        spec.page = 1
    end
end

-- ---------------------------------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------------------------------

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

-- world frame of the screen; placeables do not move once placed, so it is read once
function StorageMonitor:getScreenFrame()
    local spec = self.spec_storageMonitor
    if spec.frame == nil then
        local node = spec.screenNode
        local ox, oy, oz = getWorldTranslation(node)
        local xx, xy, xz = localDirectionToWorld(node, 1, 0, 0)
        local yx, yy, yz = localDirectionToWorld(node, 0, 1, 0)
        local zx, zy, zz = localDirectionToWorld(node, 0, 0, 1)
        local rx, ry, rz = getWorldRotation(node)
        spec.frame = {o = {ox, oy, oz}, ex = {xx, xy, xz}, ey = {yx, yy, yz}, ez = {zx, zy, zz}, rot = {rx, ry, rz},
                      scale = spec.height}
    end
    return spec.frame
end

-- design units -> world
local function toWorld(f, u, v, dz)
    local lx = (u - StorageMonitor.DESIGN_W * 0.5) * f.scale
    local ly = (0.5 - v) * f.scale
    return f.o[1] + f.ex[1] * lx + f.ey[1] * ly + f.ez[1] * dz,
           f.o[2] + f.ex[2] * lx + f.ey[2] * ly + f.ez[2] * dz,
           f.o[3] + f.ex[3] * lx + f.ey[3] * ly + f.ez[3] * dz
end

local function rect(f, u0, v0, u1, v1, c, alpha)
    if u1 - u0 <= 0.0005 then
        return
    end
    local dz = StorageMonitor.OFFSET_BAR
    local ax, ay, az = toWorld(f, u0, v0, dz)
    local bx, by, bz = toWorld(f, u1, v0, dz)
    local cx, cy, cz = toWorld(f, u1, v1, dz)
    local dx, dy, dz2 = toWorld(f, u0, v1, dz)
    local a = alpha or c[4] or 1
    -- both windings, so it shows whatever way the engine culls
    drawDebugTriangle(ax, ay, az, bx, by, bz, cx, cy, cz, c[1], c[2], c[3], a, true)
    drawDebugTriangle(ax, ay, az, cx, cy, cz, dx, dy, dz2, c[1], c[2], c[3], a, true)
    drawDebugTriangle(ax, ay, az, cx, cy, cz, bx, by, bz, c[1], c[2], c[3], a, true)
    drawDebugTriangle(ax, ay, az, dx, dy, dz2, cx, cy, cz, c[1], c[2], c[3], a, true)
end

local function text(f, u, v, size, str, c, align, bold)
    local x, y, z = toWorld(f, u, v, StorageMonitor.OFFSET_TEXT)
    setTextColor(c[1], c[2], c[3], c[4] or 1)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    setTextBold(bold == true)
    renderText3D(x, y, z, f.rot[1], f.rot[2], f.rot[3], size * f.scale, str)
end

-- shortens str with ".." until it fits maxWidth design units
local function fitText(f, str, size, maxWidth)
    local worldSize = size * f.scale
    local maxWorld = maxWidth * f.scale
    if getText3DWidth(worldSize, str) <= maxWorld then
        return str
    end
    local len = utf8Strlen ~= nil and utf8Strlen(str) or #str
    while len > 1 do
        len = len - 1
        local short = (utf8Substr ~= nil and utf8Substr(str, 0, len) or string.sub(str, 1, len)) .. ".."
        if getText3DWidth(worldSize, short) <= maxWorld then
            return short
        end
    end
    return str
end

function StorageMonitor:drawStorageMonitor()
    local spec = self.spec_storageMonitor
    local f = self:getScreenFrame()
    local L = LAYOUT
    local snapshot = spec.snapshot

    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)

    -- header: name of the storage and the in-game time
    local title
    if spec.target ~= nil then
        title = spec.target.name
    else
        title = StorageMonitor.getText("storageMonitor_searching", "Searching for a storage...")
    end
    if spec.headerTitle == nil or spec.headerSource ~= title then
        setTextBold(true)
        spec.headerTitle = string.upper(fitText(f, title, 0.050, 1.20))
        spec.headerSource = title
    end
    text(f, 0.050, 0.070, 0.050, spec.headerTitle, COLORS.text, RenderText.ALIGN_LEFT, true)

    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil and env.currentHour ~= nil then
        local clock = string.format("%02d:%02d", env.currentHour, env.currentMinute or 0)
        text(f, 1.550, 0.070, 0.045, clock, COLORS.accent, RenderText.ALIGN_RIGHT, true)
    end

    -- footer: live dot, page, page timer
    local t = (g_time or 0) / 1000
    local pulse = 0.55 + 0.45 * math.abs(math.sin(t * 2.2))
    rect(f, 0.050, 0.954, 0.068, 0.972, COLORS.ok, pulse)
    text(f, 0.082, 0.973, 0.028, StorageMonitor.getText("storageMonitor_live", "LIVE"), COLORS.ok, RenderText.ALIGN_LEFT, true)

    if snapshot == nil then
        local msg = spec.target == nil and StorageMonitor.getText("storageMonitor_noStorage", "No storage nearby")
            or StorageMonitor.getText("storageMonitor_reading", "Reading...")
        text(f, 0.800, 0.560, 0.060, msg, COLORS.dim, RenderText.ALIGN_CENTER, true)
        self:resetTextState()
        return
    end

    -- capacity panel
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

    -- stacked bar: every product in its colour, the rest is free space
    rect(f, sb[1], sb[2], sb[3], sb[4], COLORS.stackFree)
    if snapshot.used > 0 then
        local reference = math.max(snapshot.capacity, snapshot.used)
        local width = sb[3] - sb[1]
        local u = sb[1]
        for _, item in ipairs(snapshot.items) do
            local w = width * item.level / reference
            if w > 0.002 then
                rect(f, u, sb[2], math.min(sb[3], u + w), sb[4], item.color)
                u = u + w
            end
            if u >= sb[3] then
                break
            end
        end
        -- threshold marker in the level colour along the bottom edge
        rect(f, sb[1], sb[4] + 0.004, sb[1] + width * math.min(1, snapshot.used / reference), sb[4] + 0.009, levelColor)
    end

    if snapshot.capacity > 0 then
        local free = math.max(0, snapshot.capacity - snapshot.used)
        text(f, sb[1], 0.338, 0.034,
            StorageMonitor.getText("storageMonitor_free", "FREE") .. "  " .. StorageMonitor.formatVolume(free),
            COLORS.ok, RenderText.ALIGN_LEFT, false)
    end
    text(f, sb[3], 0.338, 0.034,
        string.format(StorageMonitor.getText("storageMonitor_products", "%d PRODUCTS"), snapshot.count),
        COLORS.dim, RenderText.ALIGN_RIGHT, false)

    -- list
    text(f, 0.070, L.listHeadV, 0.028, StorageMonitor.getText("storageMonitor_colProduct", "PRODUCT"), COLORS.dim, RenderText.ALIGN_LEFT, true)
    text(f, L.rowBarU[1], L.listHeadV, 0.028, StorageMonitor.getText("storageMonitor_colLevel", "FILL"), COLORS.dim, RenderText.ALIGN_LEFT, true)
    text(f, 1.385, L.listHeadV, 0.028, StorageMonitor.getText("storageMonitor_colAmount", "AMOUNT"), COLORS.dim, RenderText.ALIGN_RIGHT, true)
    text(f, 1.535, L.listHeadV, 0.028, "%", COLORS.dim, RenderText.ALIGN_RIGHT, true)

    local pages = math.max(1, math.ceil(snapshot.count / StorageMonitor.ROWS))
    local first = (spec.page - 1) * StorageMonitor.ROWS
    if snapshot.count == 0 then
        text(f, 0.800, 0.680, 0.050, StorageMonitor.getText("storageMonitor_empty", "Empty"), COLORS.dim, RenderText.ALIGN_CENTER, true)
    end
    for row = 1, StorageMonitor.ROWS do
        local item = snapshot.items[first + row]
        if item == nil then
            break
        end
        local vc = L.listTopV + L.rowH * (row - 0.5)
        local baseline = vc + 0.014
        rect(f, 0.070, vc - 0.014, 0.098, vc + 0.014, item.color)

        local key = item.fillType
        local shown = spec.rowTitles[key]
        if shown == nil then
            setTextBold(false)
            shown = fitText(f, tostring(item.title), 0.040, item.role ~= nil and 0.43 or 0.55)
            spec.rowTitles[key] = shown
        end
        text(f, 0.120, baseline, 0.040, shown, COLORS.text, RenderText.ALIGN_LEFT, false)

        if item.role ~= nil then
            local tag, color = "OUT", COLORS.output
            if item.role == "in" then
                tag, color = "IN", COLORS.input
            elseif item.role == "inout" then
                tag, color = "IN/OUT", COLORS.output
            end
            text(f, 0.675, vc + 0.010, 0.026, tag, color, RenderText.ALIGN_RIGHT, true)
        end

        local u0, u1 = L.rowBarU[1], L.rowBarU[2]
        local h = L.rowBarHalfH
        rect(f, u0, vc - h, u1, vc + h, COLORS.track)
        local fraction
        if item.capacity ~= nil and item.capacity > 0 then
            fraction = item.level / item.capacity
        elseif snapshot.used > 0 then
            fraction = item.level / snapshot.used
        else
            fraction = 0
        end
        fraction = math.max(0, math.min(1, fraction))
        if fraction > 0 then
            rect(f, u0, vc - h, u0 + math.max(0.004, (u1 - u0) * fraction), vc + h, item.color)
        end

        text(f, 1.385, baseline, 0.040, StorageMonitor.formatVolume(item.level), COLORS.text, RenderText.ALIGN_RIGHT, false)
        local pct = item.capacity ~= nil and item.capacity > 0 and item.percent or StorageMonitor.percent(item.level, snapshot.used)
        text(f, 1.535, baseline, 0.036, string.format("%d%%", pct), item.color, RenderText.ALIGN_RIGHT, true)
    end

    -- page indicator and timer
    if pages > 1 then
        text(f, 1.550, 0.973, 0.028,
            string.format(StorageMonitor.getText("storageMonitor_page", "PAGE %d/%d"), spec.page, pages),
            COLORS.dim, RenderText.ALIGN_RIGHT, true)
        local pb = L.pageBar
        rect(f, pb[1], pb[2], pb[3], pb[4], COLORS.track)
        local progress = math.min(1, spec.pageTime / StorageMonitor.PAGE_TIME)
        rect(f, pb[1], pb[2], pb[1] + (pb[3] - pb[1]) * progress, pb[4], COLORS.accent)
    end

    self:resetTextState()
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
    local f = self:getScreenFrame()
    local dx, dy, dz = cx - f.o[1], cy - f.o[2], cz - f.o[3]
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance > spec.drawDistance then
        return
    end
    -- in front of the glass only
    spec.isNear = (dx * f.ez[1] + dy * f.ez[2] + dz * f.ez[3]) > 0.02

    spec.scanTimer = spec.scanTimer + dt
    if spec.scanTimer >= StorageMonitor.SCAN_INTERVAL then
        self:rescanStorageMonitor()
    end
    spec.dataTimer = spec.dataTimer + dt
    if spec.dataTimer >= StorageMonitor.DATA_INTERVAL then
        self:refreshStorageMonitorData()
    end

    spec.pageTime = spec.pageTime + dt
    if spec.pageTime >= StorageMonitor.PAGE_TIME then
        spec.pageTime = 0
        local count = spec.snapshot ~= nil and spec.snapshot.count or 0
        local pages = math.max(1, math.ceil(count / StorageMonitor.ROWS))
        spec.page = (spec.page % pages) + 1
    end
end

-- ---------------------------------------------------------------------------------------------------
-- mod event listener: drives all monitors on this client
-- ---------------------------------------------------------------------------------------------------

StorageMonitor.Listener = {}

function StorageMonitor.Listener:update(dt)
    if g_currentMission == nil or not g_currentMission:getIsClient() then
        return
    end
    for _, monitor in ipairs(StorageMonitor.instances) do
        monitor:updateStorageMonitor(dt)
    end
end

function StorageMonitor.Listener:draw()
    if g_currentMission == nil or not g_currentMission:getIsClient() then
        return
    end
    local depthSet = false
    for _, monitor in ipairs(StorageMonitor.instances) do
        local spec = monitor.spec_storageMonitor
        if spec ~= nil and spec.isNear then
            if not depthSet and setTextDepthTestEnabled ~= nil then
                setTextDepthTestEnabled(true)
                depthSet = true
            end
            local ok, err = pcall(monitor.drawStorageMonitor, monitor)
            if not ok then
                spec.isNear = false
                if not spec.loggedError then
                    spec.loggedError = true
                    StorageMonitor.log("Error drawing a monitor: %s", tostring(err))
                end
                monitor:resetTextState()
            end
        end
    end
    if depthSet then
        setTextDepthTestEnabled(false)
    end
end

addModEventListener(StorageMonitor.Listener)

-- ---------------------------------------------------------------------------------------------------
-- "switch storage" action
-- ---------------------------------------------------------------------------------------------------

StorageMonitorActivatable = {}
local StorageMonitorActivatable_mt = Class(StorageMonitorActivatable)

function StorageMonitorActivatable.new(placeable)
    local self = setmetatable({}, StorageMonitorActivatable_mt)
    self.placeable = placeable
    self.activateText = StorageMonitor.getText("storageMonitor_switch", "Switch storage")
    return self
end

function StorageMonitorActivatable:getIsActivatable()
    local spec = self.placeable.spec_storageMonitor
    if spec == nil then
        return false
    end
    -- candidateCount is kept up to date by the scans while someone is near the screen
    return spec.candidateCount > 1
end

function StorageMonitorActivatable:run()
    local spec = self.placeable.spec_storageMonitor
    self.placeable:rescanStorageMonitor()
    local count = math.min(spec.candidateCount, StorageMonitor.MAX_OFFSET + 1)
    if count <= 1 then
        return
    end
    self.placeable:setStorageMonitorOffset((spec.offset + 1) % count)
    self.placeable:rescanStorageMonitor()
    self.placeable:refreshStorageMonitorData()
end

function StorageMonitorActivatable:getDistance(x, y, z)
    local spec = self.placeable.spec_storageMonitor
    if spec ~= nil and spec.playerTrigger ~= nil then
        local tx, ty, tz = getWorldTranslation(spec.playerTrigger)
        return MathUtil.vector3Length(x - tx, y - ty, z - tz)
    end
    return math.huge
end
