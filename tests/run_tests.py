"""Offline tests: runs scripts/StorageMonitor.lua under lupa with stubs for the engine.

    python tests/run_tests.py
"""
import os
import re
import sys

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))

STUBS = r"""
logs = {}
function print(s) table.insert(logs, tostring(s)) end
g_currentModName = "FS25_DigitalDTM"
g_currentModDirectory = "/mods/FS25_DigitalDTM/"
listeners = {}
function addModEventListener(l) table.insert(listeners, l) end
function Class(base) local mt = {__index = base} return mt end
function InitEventClass() end
Event = {new = function(mt) return setmetatable({}, mt) end}
RenderText = {ALIGN_LEFT = 0, ALIGN_CENTER = 1, ALIGN_RIGHT = 2, VERTICAL_ALIGN_BASELINE = 3}
MathUtil = {vector3Length = function(x, y, z) return math.sqrt(x*x + y*y + z*z) end}
SpecializationUtil = {
    registerFunction = function(t, name, fn) t.functions[name] = fn end,
    registerEventListener = function() end,
    registerOverwrittenFunction = function() end,
}
Utils = {appendedFunction = function(a, b) return function(...) a(...) b(...) end end}
PlayerInputComponent = {registerGlobalPlayerActionEvents = function() end}
InputAction = {STORAGE_MONITOR_PAGE_UP = "STORAGE_MONITOR_PAGE_UP", STORAGE_MONITOR_PAGE_DOWN = "STORAGE_MONITOR_PAGE_DOWN"}
GS_PRIO_HIGH = 1
actionActive = {}
g_inputBinding = {
    registerActionEvent = function(self, action, target, cb) return true, action end,
    setActionEventTextPriority = function() end,
    setActionEventActive = function(self, id, active) actionActive[id] = active end,
}
dialogs = {}
OptionDialog = {show = function(callback, title, text, options) table.insert(dialogs, {callback = callback, title = title, options = options}) end}
g_gui = {getIsDialogVisible = function() return false end}

calls = {text = {}, tris = 0, depth = {}}
function setTextColor() end
function setTextAlignment() end
function setTextBold() end
function setTextVerticalAlignment() end
function setTextDepthTestEnabled(v) table.insert(calls.depth, v) end
function renderText3D(x, y, z, rx, ry, rz, size, text)
    assert(type(text) == "string", "text must be a string")
    assert(size > 0, "size")
    table.insert(calls.text, text)
    calls.sizes = calls.sizes or {}
    calls.sizes[text] = size
end
function getText3DWidth(size, text) return #text * size * 0.55 end
shapes = {}     -- copies of the bar template: node -> {visible, w, h, color}
function clone(n, a, b, c)
    assert(c ~= nil, "clone takes 4 arguments")
    local id = newNode(0, 0, 0)
    shapes[id] = {template = n, visible = false}
    return id
end
function link(parent, n) end
function getParent(n) return 0 end
scales = {}
function setScale(n, x, y, z)
    scales[n] = {x, y, z}
    if shapes[n] ~= nil then shapes[n].w, shapes[n].h = x, y end
end
function setVisibility(n, v) if shapes[n] ~= nil then shapes[n].visible = v end end
function setShaderParameter(n, name, r, g, b, a, shared)
    assert(name == "emitColor" and a == 1 and shared == false, "emitColor r g b 1 false")
    if shapes[n] ~= nil then shapes[n].color = {r, g, b} end
end
-- pairs of visible bars that cover each other (same depth: they flicker in the game)
function overlappingBars()
    local list = {}
    for n, sh in pairs(shapes) do
        if sh.visible then
            local p = nodes[n]
            table.insert(list, {p[1], p[2] - sh.h, p[1] + sh.w, p[2]})
        end
    end
    local count = 0
    for i = 1, #list do
        for j = i + 1, #list do
            local a, b = list[i], list[j]
            local ox = math.min(a[3], b[3]) - math.max(a[1], b[1])
            local oy = math.min(a[4], b[4]) - math.max(a[2], b[2])
            if ox > 1e-6 and oy > 1e-6 then count = count + 1 end
        end
    end
    return count
end
-- materials: setMaterialDiffuseMapFromFile makes a new material id that remembers its texture
materials = {[1] = {texture = "template"}}
nodeMaterial = {}
function getMaterial(n, i) return nodeMaterial[n] or 1 end
function setMaterial(n, m, i) nodeMaterial[n] = m end
function setMaterialDiffuseMapFromFile(m, path, a, b, c)
    table.insert(materials, {texture = path, from = m})
    return #materials
end
shaderParams = {}
local realSetShaderParameter = setShaderParameter
function setShaderParameter(n, name, a, b, c, d, shared)
    shaderParams[n] = shaderParams[n] or {}
    shaderParams[n][name] = {a, b, c, d}
    if name == "emitColor" then realSetShaderParameter(n, name, a, b, c, d, shared) end
end
RigidBodyType = {STATIC = "static", NONE = "none"}
rigid = {}
function setRigidBodyType(n, t) rigid[n] = t end
children, names = {}, {}
function getNumOfChildren(n) return #(children[n] or {}) end
function getChildAt(n, i) return children[n][i + 1] end
function getName(n) return names[n] end
function streamWriteBool(id, v) table.insert(id, v) end
streamWriteFloat32, streamWriteUInt8, streamWriteString = streamWriteBool, streamWriteBool, streamWriteBool
function streamReadBool(id) id.pos = (id.pos or 0) + 1 return id[id.pos] end
streamReadFloat32, streamReadUInt8, streamReadString = streamReadBool, streamReadBool, streamReadBool
function visibleIcons()
    local c = 0
    for n, sh in pairs(shapes) do if sh.visible and nodeMaterial[n] ~= nil then c = c + 1 end end
    return c
end
function visibleBars()
    local c = 0
    for n, sh in pairs(shapes) do if sh.visible and nodeMaterial[n] == nil then c = c + 1 end end
    return c
end

nodes = {}
function newNode(x, y, z) table.insert(nodes, {x, y, z}) return #nodes end
function getWorldTranslation(n) local p = nodes[n] return p[1], p[2], p[3] end
function getTranslation(n) local p = nodes[n] return p[1], p[2], p[3] end
function setTranslation(n, x, y, z) nodes[n] = {x, y, z} end
flipped = {}     -- nodes turned 180 degrees about y (a back screen; a camera looking +z)
function localDirectionToWorld(n, x, y, z) if flipped[n] then return -x, y, -z end return x, y, z end
function getWorldRotation(n) return 0, 0, 0 end
function entityExists(n) return nodes[n] ~= nil end
function getCamera() return camera end
g_time = 0

function makeStorage(levels, capacity, capacities, x, z, farm)
    local s = {fillLevels = levels, capacity = capacity, capacities = capacities, rootNode = newNode(x or 0, 0, z or 0),
               farm = farm or 1, loadingStations = {}, unloadingStations = {}}
    function s:getFillLevels() return self.fillLevels end
    function s:getOwnerFarmId() return self.farm end
    return s
end

fillTypes = {}
function addFillType(index, name, title) fillTypes[index] = {name = name, title = title} end
g_fillTypeManager = {getFillTypeByIndex = function(self, i) return fillTypes[i] end}
g_i18n = {
    formatVolume = function(self, v, p) return tostring(math.floor(v)) .. " l" end,
    hasText = function(self, k) return false end,
    getText = function(self, k) return k end,
}
"""

WORLD = r"""
for i = 1, 60 do addFillType(i, "FT" .. i, "Type " .. i) end
addFillType(100, "WHEAT", "Wheat")
addFillType(101, "CHAFF", "Chaff")
fillTypes[100].hudOverlayFilename = "$dataS/menu/hud/fillTypes/hud_fill_wheat.png"

local function placeable(name, x, z, farm)
    local p = {rootNode = newNode(x, 0, z), name = name, farm = farm or 1}
    function p:getName() return self.name end
    function p:getOwnerFarmId() return self.farm end
    return p
end
local function station(owner, storages)
    local st = {owningPlaceable = owner, rootNode = newNode(0, 0, 0), sourceStorages = {}}
    for _, s in ipairs(storages) do
        st.sourceStorages[s] = s
        s.loadingStations[st] = st
    end
    return st
end

-- a silo complex: main silo at 30 m with a storage, two multifruit extensions (one right at the monitor)
mainSilo = placeable("Grain Silo", 30, 0)
sMain = makeStorage({[100] = 600000, [101] = 1000}, 1000000, {}, 30, 0)
mainSilo.spec_silo = {storages = {sMain}}
extNear = placeable("Multifruit Silo", 4, 0)
sNear = makeStorage({[100] = 100000, [101] = 21}, 1000000, {}, 4, 0)
extNear.spec_siloExtension = {storage = sNear}
extFar = placeable("Multifruit Silo B", 16, 0)
sFar = makeStorage({[100] = 5000}, 500000, {}, 16, 0)
extFar.spec_siloExtension = {storage = sFar}
local st = station(mainSilo, {sMain, sNear, sFar})

otherFarm = placeable("Neighbour Silo", 2, 0, 2)
otherFarm.spec_silo = {storages = {makeStorage({[100] = 7}, 100000, {}, 2, 0, 2)}}
faraway = placeable("Far Silo", 300, 0)
faraway.spec_silo = {storages = {makeStorage({[100] = 7}, 100000, {}, 300, 0)}}

bakery = placeable("Bakery", 10, 5)
sProd = makeStorage({[100] = 300, [101] = 50}, nil, {[100] = 1000, [101] = 1000}, 10, 5)
bakery.spec_productionPoint = {productionPoint = {storage = sProd, inputFillTypeIds = {[101] = true}, outputFillTypeIds = {[100] = true}}}

g_currentMission = {
    placeableSystem = {placeables = {mainSilo, extNear, extFar, otherFarm, faraway, bakery}},
    storageSystem = {getLoadingStations = function() return {st} end, getUnloadingStations = function() return {} end},
    environment = {currentHour = 14, currentMinute = 5},
    getIsClient = function() return true end,
    activatableObjectsSystem = {addActivatable = function() end, removeActivatable = function() end},
}
g_localPlayer = {farmId = 1, rootNode = newNode(0, 0, 5)}
camera = newNode(0, 2, 6)

-- a monitor at the origin, screen facing +z
-- kind: "silo" (silo mount), "ground" (free-standing, resizable) or nil/false (no mount node)
function newMonitor(withMount, back, unplaced)
    -- like the game: the placeable only has the functions the specialization registers, nothing else
    local placeableType = {functions = {}}
    StorageMonitor.registerFunctions(placeableType)
    local m = {rootNode = newNode(0, 0, 0), isClient = true}
    for name, fn in pairs(placeableType.functions) do m[name] = fn end
    local mount = withMount and newNode(0, withMount == "ground" and 0 or 3, 0) or nil
    local collisions = newNode(0, 0, 0)
    children[collisions] = {}
    for _, w in ipairs(StorageMonitor.SIZE_WIDTHS) do
        local c = newNode(0, 0, 0)
        names[c] = string.format("collision_%03d", math.floor(w * 100 + 0.5))
        table.insert(children[collisions], c)
    end
    m.xmlFile = {getValue = function(self, key, default)
        local values = {
            ["placeable.storageMonitor#screenNode"] = newNode(0, 2, 0),
            ["placeable.storageMonitor#width"] = 2.4,
            ["placeable.storageMonitor#drawDistance"] = 45,
            ["placeable.storageMonitor#searchRadius"] = 40,
            ["placeable.storageMonitor#barTemplate"] = newNode(0, 0, 0),
            ["placeable.storageMonitor.mount#node"] = mount,
            ["placeable.storageMonitor.mount#mode"] = withMount == "ground" and "ground" or "silo",
            ["placeable.storageMonitor#iconTemplate"] = newNode(0, 0, 0),
            ["placeable.storageMonitor#glassNode"] = newNode(0, 0, 0),
            ["placeable.storageMonitor#collisions"] = collisions,
            ["placeable.storageMonitor.mount#bottom"] = 2,
            ["placeable.storageMonitor.mount#lowerExtent"] = 0.846,
        }
        if back then
            local screen = newNode(0, 2, -0.3)
            flipped[screen] = true
            values["placeable.storageMonitor.back#screenNode"] = screen
            values["placeable.storageMonitor.back#barTemplate"] = newNode(0, 0, 0)
            values["placeable.storageMonitor.back#iconTemplate"] = newNode(0, 0, 0)
            values["placeable.storageMonitor.back#glassNode"] = newNode(0, 0, 0)
        end
        local v = values[key]
        if v == nil then return default end
        return v
    end}
    StorageMonitor.onLoad(m)
    -- like the game: once in physics, the pick objects are the bodies that are on (all of them, before finalize)
    m.pickObjects = {}
    for _, c in ipairs(m.spec_storageMonitor.collisions) do
        if rigid[c.node] ~= "none" then table.insert(m.pickObjects, c.node) end
    end
    if not unplaced then
        StorageMonitor.onPostFinalizePlacement(m)
    end
    return m
end
function newMonitorUnplaced(withMount) return newMonitor(withMount, nil, true) end
function frame()
    calls.text = {}
    calls.tris = 0
    for _, l in ipairs(listeners) do if l.update then l:update(16) end end
    for _, l in ipairs(listeners) do if l.draw then l:draw() end end
end
StorageMonitorSettingsEvent.sendEvent = function() end
function set(m, key, value)
    local st = m:getStorageMonitorSettings()
    st[key] = value
    m:setStorageMonitorSettings(st)
end
"""

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL:", msg)


def new_runtime():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    for name in ("StorageMonitor.lua", "StorageMonitorSettingsEvent.lua"):
        lua.execute(open(os.path.join(ROOT, "scripts", name), encoding="utf-8").read())
    return lua


def texts(lua):
    return list(lua.globals().calls.text.values())


def show_logs(lua):
    for line in lua.globals().logs.values():
        print("LUA:", line)


def test_helpers(lua):
    SM = lua.globals().StorageMonitor
    check(SM.groupDigits(1234567) == "1,234,567", "groupDigits")
    check(SM.percent(0.4, 100) == 1, "tiny amounts show 1 %")
    check(SM.percent(99.7, 100) == 99, "not 100 % before full")
    check(SM.percent(100, 100) == 100, "full is 100 %")
    check(SM.percent(5, 0) == 0, "no capacity")
    check(lua.eval('StorageMonitor.colorForName("X_MOD") == StorageMonitor.colorForName("X_MOD")'), "stable colour")
    check(lua.eval("StorageMonitor.levelColor(80) == StorageMonitor.COLORS.warn"), "level colours")


def test_snapshot(lua):
    lua.execute("""
        for i = 1, 60 do addFillType(i, "FT" .. i, "Type " .. i) end
        addFillType(100, "WHEAT", "Wheat")
        addFillType(101, "CHAFF", "Chaff")
        local levels, caps = {}, {}
        for i = 1, 60 do levels[i] = 0 caps[i] = 1000000 end
        levels[100] = 250000 caps[100] = 1000000
        levels[101] = 21 caps[101] = 1000000
        silo = makeStorage(levels, 1000000, caps)
        snap1 = StorageMonitor.buildSnapshot({{storage = silo}}, nil, function(i) return fillTypes[i] end)
        prod = makeStorage({[100] = 5000, [101] = 0}, nil, {[100] = 10000, [101] = 20000})
        -- FS25_JPMFermenter: a production, 5,000,000 l per product, and the default Storage.capacity
        local caps = {}
        for i = 1, 13 do caps[i] = 5000000 end
        caps[100] = 5000000
        ferm = makeStorage({[100] = 4140863, [1] = 0}, 100000, caps)
        snap3 = StorageMonitor.buildSnapshot({{storage = ferm}}, nil, function(i) return fillTypes[i] end)
        -- FS25_Fed_Mods_Pack cowBarnBigGea, as seen in the game (1.0.0.0 showed 237 %, slurry 1671 %):
        -- slurry 2,000,000, milk 400,000, buffalo milk 400,000, straw 400,000, water 500,000, feed 1,200,000
        addFillType(201, "LIQUIDMANURE", "Slurry") addFillType(202, "MILK", "Milk") addFillType(203, "BUFFALOMILK", "Buffalo Milk")
        addFillType(204, "STRAW", "Straw") addFillType(205, "WATER", "Water") addFillType(206, "TOTALMIXEDRATION", "Total Mixed Ration")
        barn = makeStorage({[201] = 1670665, [202] = 25000, [203] = 4070, [204] = 195358, [205] = 0}, 100000,
            {[201] = 2000000, [202] = 400000, [203] = 400000, [204] = 400000, [205] = 500000})
        snap4 = StorageMonitor.buildSnapshot({{storage = barn}, {levels = {[206] = 1186773}, capacity = 1200000}}, nil,
            function(i) return fillTypes[i] end)
        snap2 = StorageMonitor.buildSnapshot({{storage = prod}}, {[100] = "in"}, function(i) return fillTypes[i] end)
    """)
    s1, s2 = lua.globals().snap1, lua.globals().snap2
    check(s1.capacity == 1000000, "shared capacity counted once (got %s)" % s1.capacity)
    check(s1.count == 2 and s1["items"][1].percent == 25 and s1["items"][2].percent == 1, "shared silo items")
    check(s2.capacity == 10000 and s2["items"][1].percent == 50, "per product capacities: room of the stored products (%s)" % s2.capacity)
    s4 = lua.globals().snap4
    pct = {s4["items"][i].title: s4["items"][i].percent for i in range(1, s4.count + 1)}
    check(pct == {"Slurry": 84, "Total Mixed Ration": 99, "Straw": 49, "Milk": 6, "Buffalo Milk": 1},
          "cow barn per product: %s" % pct)
    check(s4.capacity == 2000000 + 400000 * 3 + 1200000 and lua.globals().StorageMonitor.percent(s4.used, s4.capacity) == 70,
          "cow barn total %s, %s %%" % (s4.capacity, lua.globals().StorageMonitor.percent(s4.used, s4.capacity)))
    s3 = lua.globals().snap3
    check(s3.capacity == 5000000 and s3["items"][1].percent == 83,
          "fermenting silo: 4,140,863 of 5,000,000 l = 83 %% (got %s, %s %%)" % (s3.capacity, s3["items"][1].percent))


def test_list_layout(lua):
    SM = lua.globals().StorageMonitor
    seen_cols = []
    for n in (1, 7, 9, 10, 20, 22, 23, 42, 43, 100):
        lay = SM.computeListLayout(n)
        seen_cols.append((n, lay.cols, lay.pages))
        if n <= 42:
            check(lay.pages == 1 and lay.perPage >= n, "%d products fit on one page (%s)" % (n, (lay.cols, lay.rows)))
        else:
            check(lay.pages > 1, "%d products page" % n)
        check(lay.size >= 0.018 - 1e-9, "%d products: text not below the minimum (%.4f)" % (n, lay.size))
        check(lay.rows * lay.rowH <= 0.899 - 0.468 + 1e-9, "%d products: rows fit the panel" % n)
    check(SM.computeListLayout(7).cols == 1 and SM.computeListLayout(20).cols == 2 and SM.computeListLayout(30).cols == 3,
          "columns grow with the products: %s" % seen_cols)


def test_world(lua):
    lua.execute(WORLD)
    lua.execute("m = newMonitor(false) cands = StorageMonitor.collectStorageCandidates(m)")
    g = lua.globals()
    cands = g.cands
    names = [cands[i].name for i in range(1, len(cands) + 1)]
    check(names == ["Multifruit Silo", "Bakery", "Multifruit Silo B", "Grain Silo", "All silos of my farm", "All my productions", "What my productions need", "When to sell", "Production profit", "Message board"],
          "one entry per building, nearest first, other farm and far ones left out, farm screens last: %s" % names)

    lua.execute("frame()")
    show_logs(lua)
    spec = g.m.spec_storageMonitor
    t = texts(lua)
    check(spec.target.name == "Multifruit Silo", "shows the silo next to it, not the whole complex")
    check(spec.snapshot.capacity == 1000000 and spec.snapshot.used == 100021, "only that silo's contents")
    check("MULTIFRUIT SILO" in t and "14:05" in t and "10%" in t, "header, clock, percent: %s" % t[:6])
    check(lua.eval("overlappingBars()") == 0, "no bar lies on another (%d pairs)" % lua.eval("overlappingBars()"))
    check(lua.eval("visibleBars() + visibleIcons()") >= 9, "bars drawn: background, 2 segments, level line, icon or swatch, track and fill per product (%d)" % lua.eval("visibleBars()"))
    check(list(g.calls.depth.values()) == [True, False], "text depth test on and back off")

    # connected silos: the whole complex
    lua.execute("set(m, 'connected', true) m:rescanStorageMonitor() frame()")
    check(spec.snapshot.capacity == 2500000 and spec.snapshot.used == 706021, "connected: silo + main + other extension")
    check("MULTIFRUIT SILO + 2 CONNECTED" in texts(lua), "connected title: %s" % texts(lua)[:2])

    # pick the bakery from the settings menu
    lua.execute("""
        set(m, "connected", false)
        StorageMonitor.openSettings(m)
        StorageMonitor.openPendingDialog()
        dialogs[1].callback(1)          -- "Pick the storage"
        StorageMonitor.openPendingDialog()
        pickOptions = dialogs[2].options
        dialogs[2].callback(3)          -- 1 = nearest, 2 = Multifruit Silo, 3 = Bakery
        frame()
    """)
    check(spec.target.name == "Bakery", "picked storage shown")
    check(spec.pick is not None and abs(spec.pick[1] - 10) < 1e-6, "pick remembers where the building is")
    check("IN" in texts(lua) and "OUT" in texts(lua), "production tags")
    opts = list(g.pickOptions.values())
    check(opts[0].startswith("Always the nearest") and opts[2].startswith("Bakery"), "pick list: %s" % opts)

    # the pick survives a new building that is nearer
    lua.execute("""
        local shed = {rootNode = newNode(1, 0, 0), getName = function() return "New Silo" end, getOwnerFarmId = function() return 1 end}
        shed.spec_silo = {storages = {makeStorage({[100] = 1}, 1000, {}, 1, 0)}}
        table.insert(g_currentMission.placeableSystem.placeables, shed)
        m:rescanStorageMonitor()
    """)
    check(spec.target.name == "Bakery", "pick stays when something nearer is built")

    # behind the screen nothing is drawn
    lua.execute("nodes[camera] = {0, 2, -6} frame() nodes[camera] = {0, 2, 6}")
    check(len(g.calls.text) == 0, "not drawn from behind")
    check(lua.eval("visibleBars()") == 0, "bars hidden from behind")


def test_all_products_and_paging(lua):
    lua.execute(WORLD)
    lua.execute("""
        m = newMonitor(false)
        function fill(n)
            local levels, caps = {}, {}
            for i = 1, n do levels[i] = i * 1000 end
            local s = makeStorage(levels, 10000000, {}, 1, 0)
            m.spec_storageMonitor.target = {name = "Big", title = "Big", sources = {{storage = s}}, owner = s}
            m.spec_storageMonitor.scanTimer = -1e9
            StorageMonitor.refreshStorageMonitorData(m)
        end
        fill(30)
        frame()
    """)
    g = lua.globals()
    spec = g.m.spec_storageMonitor
    t = texts(lua)
    check(spec.layout.cols == 3 and spec.layout.pages == 1, "30 products: 3 columns, one page")
    check(lua.eval("overlappingBars()") == 0, "30 products: no bar lies on another (%d pairs)" % lua.eval("overlappingBars()"))
    check(all(("%d l" % (i * 1000)) in t for i in range(1, 31)), "all 30 amounts on screen at once")
    check(not any(x.startswith("PAGE") for x in t), "no page indicator when everything fits")

    lua.execute("fill(60) m.spec_storageMonitor.page = 1 frame()")
    t = texts(lua)
    check(spec.layout.pages == 2, "60 products: 2 pages")
    check("PAGE 1/2" in t, "page indicator")
    check(g.actionActive["STORAGE_MONITOR_PAGE_DOWN"] is not True, "page keys hidden away from the monitor")
    lua.execute("""
        StorageMonitor.registerActionEvents()
        StorageMonitor.activeMonitor = m
        frame()
        StorageMonitor.onActionPageDown()
        frame()
    """)
    check(g.actionActive["STORAGE_MONITOR_PAGE_DOWN"] is True, "page keys shown at a monitor with pages")
    check(spec.page == 2 and "PAGE 2/2" in texts(lua), "page down")
    check(spec.manualTime > 0, "manual paging pauses the automatic turn")
    lua.execute("for i = 1, 100 do for _, l in ipairs(listeners) do l:update(StorageMonitor.PAGE_TIME / 10) end end")
    check(spec.page == 2, "page stays put after page down")
    lua.execute("StorageMonitor.onActionPageUp()")
    check(spec.page == 1, "page up")


def test_mount_size(lua):
    lua.execute(WORLD)
    lua.execute("""
        m = newMonitor("silo")
        mountNode = m.spec_storageMonitor.mountNode
        frame()
        before = calls.sizes["MULTIFRUIT SILO"]
        StorageMonitor.openSettings(m)
        StorageMonitor.openPendingDialog()
        menu = dialogs[#dialogs].options
        dialogs[#dialogs].callback(3)    -- screen size
        StorageMonitor.openPendingDialog()
        sizes = dialogs[#dialogs].options
        dialogs[#dialogs].callback(9)    -- 4.8 m
        frame()
        after = calls.sizes["MULTIFRUIT SILO"]
    """)
    g = lua.globals()
    spec = g.m.spec_storageMonitor
    check(len(list(g.menu.values())) == 13, "menu: pick, connected, size, height, brightness, colours, title, screen, products, alerts, full at, price alert, slideshow: %s" % list(g.menu.values()))
    check(list(g.sizes.values())[8].startswith("4.8 m wide, 3.0 m high"), "size list: %s" % list(g.sizes.values())[:3])
    check(abs(spec.mountWidth - 4.8) < 1e-6 and abs(spec.sizeScale - 2.0) < 1e-6, "size chosen: %s" % spec.mountWidth)
    sc = g.scales[g.mountNode]
    check(abs(sc[1] - 2) < 1e-6 and abs(sc[2] - 2) < 1e-6 and abs(sc[3] - 1) < 1e-6, "silo mount scaled 2 x 2 x 1")
    check(abs(g.nodes[g.mountNode][2] - (2 + 0.846 * 2)) < 1e-6, "bottom edge stays at 2 m: %s" % g.nodes[g.mountNode][2])
    check(abs(g.after / g.before - 2) < 1e-6, "text twice as big on a twice as wide screen")
    on = [g.names[c.node] for c in spec.collisions.values() if g.rigid[c.node] == "static"]
    check(on == ["collision_480"], "only the 4.8 m collision is on: %s" % on)
    lua.execute("set(m, 'size', 50)")
    check(abs(spec.mountWidth - 6) < 1e-6, "size clamped to the largest")

    # free-standing: grows from the ground, uniformly
    lua.execute("""
        g2 = newMonitor("ground")
        set(g2, "size", 1.2)
        StorageMonitor.openSettings(g2) StorageMonitor.openPendingDialog() menuG = dialogs[#dialogs].options
    """)
    s2 = g.g2.spec_storageMonitor
    sc = g.scales[s2.mountNode]
    check(abs(sc[1] - 0.5) < 1e-6 and abs(sc[3] - 0.5) < 1e-6 and abs(g.nodes[s2.mountNode][2]) < 1e-6,
          "free-standing scaled 0.5 x 0.5 x 0.5 from the ground")
    check(len(list(g.menuG.values())) == 12, "free-standing monitors have the size entry too, but no height")
    check(not any(v.startswith("Height") for v in g.menuG.values()), "no height on a free-standing monitor")
    on = [g.names[c.node] for c in s2.collisions.values() if g.rigid[c.node] == "static"]
    check(on == ["collision_120"], "free-standing: only the 1.2 m collision is on: %s" % on)


def test_mount_height_and_collisions(lua):
    """Raised mounts: the height of the bottom edge is set in the menu, saved, synced; the collisions move with it.
    Collisions are switched only once the monitor is in physics, and every size's collision is a pick object."""
    lua.execute(WORLD)
    lua.execute("""
        pickAdded = {}
        g_currentMission.addNodeObject = function(self, node, object) table.insert(pickAdded, node) end
        m = newMonitor("silo")
        spec = m.spec_storageMonitor
        mountNode = spec.mountNode
        group = spec.collisionGroup
        StorageMonitor.openSettings(m)
        StorageMonitor.openPendingDialog()
        menu = dialogs[#dialogs].options
        dialogs[#dialogs].callback(4)    -- height
        StorageMonitor.openPendingDialog()
        heights = dialogs[#dialogs].options
        rigidCalls = {}
        local realSet = setRigidBodyType
        setRigidBodyType = function(n, t) table.insert(rigidCalls, {n, t}) realSet(n, t) end
        dialogs[#dialogs].callback(10)   -- 5.0 m
        setRigidBodyType = realSet
    """)
    g = lua.globals()
    spec = g.spec
    menu = list(g.menu.values())
    check(menu[3] == "Height (now: 2.0 m above the ground)", "height entry after the size: %s" % menu[3])
    hs = list(g.heights.values())
    check(hs[0] == "0.5 m" and hs[3] == "2.0 m (as bought)  <" and len(hs) == 16, "height list: %s" % hs[:5])
    check(abs(spec.mountBottom - 5.0) < 1e-6, "height chosen: %s" % spec.mountBottom)
    check(abs(g.nodes[g.mountNode][2] - (5.0 + 0.846)) < 1e-6, "the screen moved up: %s" % g.nodes[g.mountNode][2])
    check(abs(g.nodes[g.group][2] - 3.0) < 1e-6, "the collisions moved up 3 m with it: %s" % g.nodes[g.group][2])
    calls = [(g.names[c[1]], c[2]) for c in g.rigidCalls.values()]
    check(calls == [("collision_240", "none"), ("collision_240", "static")],
          "the collision that is on is made again where it is now: %s" % calls)
    # bigger: still from the new bottom edge
    lua.execute("set(m, 'size', 4.8)")
    check(abs(g.nodes[g.mountNode][2] - (5.0 + 0.846 * 2)) < 1e-6, "4.8 m grows up from 5 m")
    on = [g.names[c.node] for c in spec.collisions.values() if g.rigid[c.node] == "static"]
    check(on == ["collision_480"], "only the 4.8 m collision is on: %s" % on)
    check(abs(g.nodes[g.group][2] - 3.0) < 1e-6, "a size change keeps the collisions' height")
    lua.execute("set(m, 'height', 99)")
    check(abs(spec.mountBottom - 12) < 1e-6, "height clamped to the highest")

    # saved and loaded
    lua.execute("""
        set(m, 'height', 3.5)
        saved = {}
        xml = {setValue = function(self, k, v) saved[k] = v end,
               getValue = function(self, k, d) if saved[k] ~= nil then return saved[k] end return d end,
               hasProperty = function(self, k) return false end}
        StorageMonitor.saveToXMLFile(m, xml, "k")
        m2 = newMonitorUnplaced("silo")
        StorageMonitor.loadFromXMLFile(m2, xml, "k")
        loadedRigid = 0
        for _, c in ipairs(m2.spec_storageMonitor.collisions) do if rigid[c.node] ~= nil then loadedRigid = loadedRigid + 1 end end
        StorageMonitor.onPostFinalizePlacement(m2)
    """)
    s2 = g.m2.spec_storageMonitor
    check(g.saved["k#height"] == 3.5, "height saved: %s" % g.saved["k#height"])
    check(abs(s2.mountBottom - 3.5) < 1e-6 and abs(g.nodes[s2.collisionGroup][2] - 1.5) < 1e-6,
          "height loaded, collisions moved before the game puts them into physics")
    check(g.loadedRigid == 0, "no collision is switched before the monitor is in physics (%d)" % g.loadedRigid)
    on = [g.names[c.node] for c in s2.collisions.values() if g.rigid[c.node] == "static"]
    check(on == ["collision_480"], "after placing, only the saved size's collision is on: %s" % on)
    check(len(list(g.m2.pickObjects.values())) == 10, "every size's collision is a pick object")

    # a pick object the game did not collect is added to the mission
    lua.execute("""
        pickAdded = {}
        m3 = newMonitorUnplaced("silo")
        table.remove(m3.pickObjects, 1)
        StorageMonitor.onPostFinalizePlacement(m3)
    """)
    check(len(list(g.pickAdded.values())) == 1 and len(list(g.m3.pickObjects.values())) == 10,
          "a missing pick object is added (%d)" % len(list(g.pickAdded.values())))

    # synced: the height goes over the network with the other settings
    lua.execute("""
        stream = {}
        StorageMonitor.writeSettings(stream, m:getStorageMonitorSettings())
        got = StorageMonitor.readSettings(stream)
    """)
    check(abs(g.got.height - 3.5) < 1e-6 and abs(g.got.size - 4.8) < 1e-6, "height and size synced")

    # a free-standing monitor ignores a height
    lua.execute("g3 = newMonitor('ground') set(g3, 'height', 6)")
    s3 = g.g3.spec_storageMonitor
    check(abs(g.nodes[s3.mountNode][2]) < 1e-6 and abs(g.nodes[s3.collisionGroup][2]) < 1e-6, "free-standing: no height")


def test_prod_needs(lua):
    """What my productions need: every input, empty ones red and first, low ones amber, how much to fill up."""
    lua.execute(WORLD)
    lua.execute(FARM)
    lua.execute("""
        addFillType(152, "WATER", "Water") addFillType(153, "SUGAR", "Sugar") addFillType(154, "CAKE", "Cake")
        g_currentMission.environment.timeAdjustment = 1
        -- a second production: a cake line running (sugar 100 l per cycle, 5 cycles per hour) and a line that is off
        local cake = {id = "cake", name = "Cake", status = 1, cyclesPerHour = 5,
                      inputs = {{type = 153, amount = 100}, {type = 152, amount = 10}}}
        local off = {id = "x", name = "X", status = 0, cyclesPerHour = 5, inputs = {{type = 150, amount = 1}}}
        confectionery = {rootNode = newNode(460, 0, 0), name = "Confectionery", farm = 1}
        function confectionery:getName() return self.name end
        function confectionery:getOwnerFarmId() return self.farm end
        local st = makeStorage({[153] = 1000, [152] = 4000, [150] = 0, [154] = 0}, 100000, {[153] = 10000, [152] = 5000, [150] = 2000, [154] = 5000}, 460, 0)
        confectionery.spec_productionPoint = {productionPoint = {storage = st, productions = {cake, off}, activeProductions = {cake},
            sharedThroughputCapacity = false,
            inputFillTypeIds = {[153] = true, [152] = true, [150] = true}, outputFillTypeIds = {[154] = true}}}
        table.insert(g_currentMission.placeableSystem.placeables, confectionery)
        -- the bakery's bread line uses flour (empty)
        local bread = bakery.spec_productionPoint.productionPoint.productions[1]
        bread.cyclesPerHour = 10
        bread.inputs = {{type = 150, amount = 20}}
        sNear.fillLevels[150] = 7000      -- flour in a silo of the farm
    """)
    lua.execute('showScreen("prodNeeds")')
    g = lua.globals()
    spec = g.spec
    t = texts(lua)
    panel = spec.snapshot.panel
    rows = [panel.rows[i] for i in range(1, len(panel.rows) + 1)]
    titles = [r.title for r in rows]
    check(titles == ["Mill Bakery: Flour", "Confectionery: Sugar", "Confectionery: Water", "Confectionery: Flour", "Bakery: Chaff"],
          "empty first, then low, then enough, then unused: %s" % titles)
    r = {x.title: x for x in rows}
    check(r["Mill Bakery: Flour"].swatch == "full" and r["Mill Bakery: Flour"].blink and r["Mill Bakery: Flour"].flag == "full",
          "an empty input is red and blinks")
    check(r["Mill Bakery: Flour"].sub == "Empty, silos: 7000 l", "empty flour, the silos hold some: %s" % r["Mill Bakery: Flour"].sub)
    check(r["Mill Bakery: Flour"].value == "5000 l", "it takes 5,000 l to fill up: %s" % r["Mill Bakery: Flour"].value)
    check(r["Confectionery: Sugar"].swatch == "warn" and r["Confectionery: Sugar"].sub == "Low, lasts 2.0 h",
          "sugar: 1,000 l at 500 l/h lasts 2 h, low: %s" % r["Confectionery: Sugar"].sub)
    check(r["Confectionery: Water"].swatch == "ok" and r["Confectionery: Water"].flag is None, "water: enough, not flagged")
    check(r["Confectionery: Flour"].swatch == "dim" and r["Confectionery: Flour"].sub == "No line uses it now",
          "flour at the confectionery: only an off line uses it, so it is not a problem")
    check(panel.empty == 1 and panel.low == 1 and panel.count == 5 and panel.productions == 3, "counts: 1 empty, 1 low of 5 inputs at 3 productions")
    check(abs(panel.toFill - (5000 + 9000 + 1000)) < 1e-6, "to fill up counts the used inputs only: %s" % panel.toFill)
    check("INPUTS EMPTY" in t and any(x.startswith("First: Mill Bakery") for x in t), "top panel: %s" % t[:20])
    ids = lua.eval("alertIds()")
    check(ids.startswith("need") and ids.count(",") == 1, "empty and low inputs are alerts: %s" % ids)
    check(lua.eval("overlappingBars()") == 0, "needs: no bar lies on another")


def test_biogas_plant(lua):
    """Pumps N' Hoses biogas plants (issue #1): their productions come from the game's production list, where the
    DLC puts one merged point per part type; the fermenters it merged away are not listed twice."""
    lua.execute(WORLD)
    lua.execute(FARM)
    lua.execute("""
        addFillType(160, "SILAGE", "Silage") addFillType(161, "METHANE", "Methane") addFillType(162, "ELECTRICCHARGE", "Electricity")
        local function part(name, x, role)
            local p = {rootNode = newNode(x, 0, 0), name = name, role = role}
            function p:getName() return self.name end
            function p:getOwnerFarmId() return 1 end
            function p:isSandboxPlaceable() return true end
            function p:getSandboxTypeName() return self.role end
            return p
        end
        local function point(owner, title, input, output)
            local line = {id = title, name = title, status = 1, cyclesPerHour = 1, inputs = {{type = input, amount = 100}}}
            local pp = {owningPlaceable = owner, title = title,
                storage = makeStorage({[input] = 5000, [output] = 0}, 100000, {[input] = 50000, [output] = 50000}, 20, 0),
                productions = {line}, activeProductions = {line},
                inputFillTypeIds = {[input] = true}, outputFillTypeIds = {[output] = true}}
            function pp:getName() return self.title end
            return pp
        end
        -- the merged fermenter: the DLC's own specialization, no spec_productionPoint for the walk to find
        fermenter = part("PlanET Fermenter", 20, "FERMENTER")
        fermenterPP = point(fermenter, "BGA (1) Fermenter", 160, 161)
        -- a second fermenter the DLC merged into the first: it still has a point, but not in the list
        absorbed = part("PlanET Fermenter B", 24, "FERMENTER")
        absorbed.spec_productionPoint = {productionPoint = point(absorbed, "PlanET Fermenter B", 160, 161)}
        bhkw = part("PlanET BHKW", 28, "POWERPLANT")
        bhkwPP = point(bhkw, "BGA (1) Power plant", 161, 162)
        for _, p in ipairs({fermenter, absorbed, bhkw}) do
            table.insert(g_currentMission.placeableSystem.placeables, p)
        end
        local bakeryPP = bakery.spec_productionPoint.productionPoint
        g_currentMission.productionChainManager = {getProductionPointsForFarmId = function(self, farmId)
            return {bakeryPP, fermenterPP, bhkwPP}
        end}
        function prodNames(kind)
            for _, c in ipairs(StorageMonitor.collectStorageCandidates(m)) do
                if c.kind == kind then
                    local names = {}
                    for _, prod in ipairs(c.productions) do table.insert(names, prod.name) end
                    return table.concat(names, "|")
                end
            end
        end
        function hasScreen(owner)
            for _, c in ipairs(StorageMonitor.collectStorageCandidates(m)) do
                if c.placeable == owner and c.kind == "production" and c.pp ~= nil then return true end
            end
            return false
        end
    """)
    names = lua.eval('prodNames("allProductions")').split("|")
    check(names[:3] == ["Mill Bakery", "BGA (1) Fermenter", "BGA (1) Power plant"],
          "the game's list first, the biogas plant's merged points included: %s" % names)
    check("PlanET Fermenter B" not in names, "a fermenter the DLC merged away is not listed: %s" % names)
    check("Bakery" in names, "a production the walk found but the list does not have stays: %s" % names)
    check(lua.eval("hasScreen(fermenter)") and lua.eval("hasScreen(bhkw)"), "the fermenter and power plant get their own screens")
    lua.execute('showScreen("allProductions")')
    t = texts(lua)
    check(any("BGA (1) Fermenter" in x for x in t), "the all-productions screen shows the biogas plant: %s" % t[:20])
    lua.execute('showScreen("prodNeeds")')
    t = texts(lua)
    check(any("Silage" in x for x in t), "what my productions need lists the fermenter's silage: %s" % t[:30])
    # without the DLC's methods a silo is not a biogas part; without a manager the walk is all there is
    check(not lua.eval("StorageMonitor.isBiogasPart(mainSilo)"), "a plain silo is no biogas part")
    lua.execute("g_currentMission.productionChainManager = nil")
    names = lua.eval('prodNames("allProductions")').split("|")
    check("BGA (1) Fermenter" not in names and "PlanET Fermenter B" in names, "no manager: the walk's list as before: %s" % names)


def test_look_and_title(lua):
    lua.execute(WORLD)
    lua.execute("""
        m = newMonitor("silo")
        spec = m.spec_storageMonitor
        frame()
        wheatIcons = visibleIcons()
        glow1 = shaderParams[spec.glassNode].lightControl[1]
        local barNode = spec.bars[1].node
        bar1 = shapes[barNode].color[1]
        set(m, "brightness", 5)
        frame()
        glow5 = shaderParams[spec.glassNode].lightControl[1]
        bar5 = shapes[barNode].color[1]
        set(m, "theme", 3)
        glassTexture = materials[nodeMaterial[spec.glassNode]].texture
        set(m, "title", "Main Grain Silo")
        frame()
        -- saved and loaded
        local saved = {}
        local xml = {setValue = function(self, k, v) saved[k] = v end, getValue = function(self, k, d) local v = saved[k] if v == nil then return d end return v end}
        StorageMonitor.saveToXMLFile(m, xml, "k")
        m2 = newMonitor("silo")
        StorageMonitor.loadFromXMLFile(m2, xml, "k")
        -- sent over the network
        local stream = {}
        StorageMonitor.onWriteStream(m, stream)
        m3 = newMonitor("silo")
        StorageMonitor.onReadStream(m3, stream)
    """)
    g = lua.globals()
    t = texts(lua)
    check(g.wheatIcons >= 1, "wheat shows its HUD icon (%d icons)" % g.wheatIcons)
    check(abs(g.glow5 / g.glow1 - 2.2) < 1e-6 and abs(g.bar5 / g.bar1 - 2.2) < 1e-6, "brightness: screen and bars glow 2.2 x")
    check(str(g.glassTexture).endswith("textures/screen_amber.dds"), "theme 3 puts the amber texture on the glass: %s" % g.glassTexture)
    check("MAIN GRAIN SILO" in t, "custom title in the header: %s" % t[:2])
    for name in ("m2", "m3"):
        sp = g[name].spec_storageMonitor
        check(sp.title == "Main Grain Silo" and sp.theme == 3 and sp.brightness == 5,
              "%s: settings %s" % ("saved and loaded" if name == "m2" else "synced", (sp.title, sp.theme, sp.brightness)))


KINDS = r"""
ProductionPoint = {PROD_STATUS = {INACTIVE = 0, RUNNING = 1, MISSING_INPUTS = 2, NO_OUTPUT_SPACE = 3}}
BunkerSilo = {STATE_FILL = 0, STATE_CLOSED = 1, STATE_FERMENTED = 2, STATE_DRAIN = 3}
addFillType(110, "FLOUR", "Flour") addFillType(111, "BREAD", "Bread") addFillType(112, "CAKE", "Cake")
addFillType(120, "CHAFF", "Chaff") addFillType(121, "SILAGE", "Silage")
addFillType(130, "ROUNDBALE_HAY", "Hay")

local function placeable(name, x, z)
    local p = {rootNode = newNode(x, 0, z), name = name}
    function p:getName() return self.name end
    function p:getOwnerFarmId() return 1 end
    return p
end
-- a bakery: bread running, cake missing flour; flour (input) empty
bakery = placeable("Bakery", 6, 0)
local bread = {id = "bread", name = "Bread", status = 1}
local cake = {id = "cake", name = "Cake", status = 2}
local rolls = {id = "rolls", name = "Rolls", status = 0}
bakery.spec_productionPoint = {productionPoint = {
    storage = makeStorage({[110] = 0, [111] = 4200, [112] = 300}, 100000, {[110] = 50000, [111] = 50000, [112] = 50000}, 6, 0),
    productions = {bread, cake, rolls}, activeProductions = {bread, cake},
    inputFillTypeIds = {[110] = true}, outputFillTypeIds = {[111] = true, [112] = true}}}
-- a cow barn: 24 of 40 cows, food 60 %, water 30 %, straw empty
barn = placeable("Cow Barn", 12, 0)
barn.spec_husbandryAnimals = {}
barn.spec_husbandry = {storage = makeStorage({[101] = 0}, 100000, {[101] = 100000}, 12, 0)}
function barn:getNumOfAnimals() return 24 end
function barn:getMaxNumOfAnimals() return 40 end
function barn:getTotalFood() return 60000 end
function barn:getFoodCapacity() return 100000 end
function barn:getConditionInfos()
    return {{title = "Productivity", ratio = 0.8}, {title = "Water", ratio = 0.3}, {title = "Straw", ratio = 0},
            {title = "Liquid manure", ratio = 0.9, invertedBar = true}}
end
-- a bunker silo, closed and 45 % fermented; a multi bunker with one ready, one filling
bunker = placeable("Bunker Silo", 18, 0)
bunker.spec_bunkerSilo = {bunkerSilo = {state = 1, fillLevel = 250000, fermentingPercent = 0.45, compactedPercent = 80,
    inputFillType = 120, outputFillType = 121}}
multi = placeable("Bunker Row", 24, 0)
multi.spec_multiBunkerSilo = {bunkerSilos = {
    {state = 2, fillLevel = 300000, fermentingPercent = 1, inputFillType = 120, outputFillType = 121},
    {state = 0, fillLevel = 50000, compactedPercent = 35, inputFillType = 120, outputFillType = 121}}}
-- a bale shed: on a client each group has one sample object and numObjects
shed = placeable("Bale Shed", 30, 0)
shed.spec_objectStorage = {numStoredObjects = 30, capacity = 120, objectInfos = {
    {numObjects = 18, objects = {{baleAttributes = {fillType = 130, fillLevel = 4000}}}},
    {numObjects = 12, objects = {{baleAttributes = {fillType = 121, fillLevel = 4000}}}}}}

g_currentMission.placeableSystem.placeables = {bakery, barn, bunker, multi, shed}
g_currentMission.storageSystem = {getLoadingStations = function() return {} end, getUnloadingStations = function() return {} end}
m = newMonitor(false)
function show(name)
    for _, c in ipairs(StorageMonitor.collectStorageCandidates(m)) do
        if c.name == name then
            set(m, "pick", {c.anchor[1], c.anchor[2]})
            m:rescanStorageMonitor()
            frame()
            return
        end
    end
    error("no candidate " .. name)
end
"""


def test_kinds(lua):
    lua.execute(WORLD)
    lua.execute(KINDS)
    g = lua.globals()
    spec = g.m.spec_storageMonitor

    lua.execute('show("Bakery")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.kind == "production" and panel.running == 1 and len(panel.lines) == 3, "bakery: 1 of 3 lines running")
    states = [panel.lines[i].state for i in range(1, 4)]
    check(states == ["running", "missing", "off"], "bakery line states: %s" % states)
    check("1/3" in t and "Running" in t and "Missing inputs" in t, "bakery panel text: %s" % t[:12])
    flour = [spec.snapshot["items"][i] for i in range(1, spec.snapshot.count + 1) if spec.snapshot["items"][i].title == "Flour"]
    check(len(flour) == 1 and flour[0].missing is True, "empty flour (an input) is listed and marked missing")

    lua.execute('show("Cow Barn")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.kind == "husbandry" and panel.animals == 24 and panel.maxAnimals == 40, "barn: 24/40 animals")
    titles = [panel.conditions[i].title for i in range(1, len(panel.conditions) + 1)]
    check(titles == ["Food", "Productivity", "Water", "Straw", "Liquid manure"], "barn conditions: %s" % titles)
    check("24/40" in t and "60%" in t and "30%" in t, "barn panel text: %s" % t[:14])

    lua.execute('show("Bunker Silo")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.kind == "bunker" and panel.bunkers[1].state == "fermenting" and panel.bunkers[1].percent == 45, "bunker 45 % fermenting")
    check("45%" in t and spec.snapshot["items"][1].title == "Silage" and spec.snapshot["items"][1].level == 250000,
          "bunker shows silage 250,000 l: %s" % t[:8])

    lua.execute('show("Bunker Row")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.ready == 1 and len(panel.bunkers) == 2 and "1/2" in t, "multi bunker: 1 of 2 ready")

    lua.execute('show("Bale Shed")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.kind == "objects" and panel.count == 30 and panel.capacity == 120, "shed 30/120")
    hay = [spec.snapshot["items"][i] for i in range(1, spec.snapshot.count + 1) if spec.snapshot["items"][i].title == "Hay"]
    check(len(hay) == 1 and hay[0].level == 72000 and hay[0].count == 18, "18 hay bales = 72,000 l on a client")
    check("18x" in t and "25%" in t, "shed text (count column, 30/120 = 25 %%): %s" % t[:10])
    check(lua.eval("overlappingBars()") == 0, "kind panels: no bar lies on another")


def test_rates(lua):
    """Rates per in-game hour, time to full, and a rate per product in the list."""
    lua.execute(WORLD)
    lua.execute("""
        local env = g_currentMission.environment
        env.dayTime, env.currentDay = 8 * 3600000, 3
        m = newMonitor(false)
        frame()
        spec = m.spec_storageMonitor
        noRate = spec.snapshot.rate
        -- an hour later 50,000 l more wheat came in
        sNear.fillLevels[100] = sNear.fillLevels[100] + 50000
        env.dayTime = 9 * 3600000
        StorageMonitor.refreshStorageMonitorData(m)
        frame()
    """)
    g = lua.globals()
    spec = g.spec
    t = texts(lua)
    check(g.noRate is None, "no rate before a quarter of an in-game hour")
    check(abs(spec.snapshot.rate - 50000) < 1e-6, "silo rate 50,000 l/h (%s)" % spec.snapshot.rate)
    wheat = [spec.snapshot["items"][i] for i in range(1, spec.snapshot.count + 1) if spec.snapshot["items"][i].title == "Wheat"][0]
    check(abs(wheat.rate - 50000) < 1e-6, "wheat rate")
    # 1,000,000 - 150,021 free at 50,000 l/h: full in 17 h
    check(any(x.startswith("+50000 l/h") and "FULL IN 17 h" in x for x in t), "rate and time to full: %s" % [x for x in t if "/h" in x])
    check("+50k/h" in t, "rate in the product row: %s" % [x for x in t if "/h" in x])
    check(lua.eval("overlappingBars()") == 0, "rates: no bar lies on another")
    SM = g.StorageMonitor
    check(SM.formatDuration(0.5) == "30 min" and SM.formatDuration(3.25) == "3.2 h" and SM.formatDuration(60) == "2.5 days",
          "durations: %s %s %s" % (SM.formatDuration(0.5), SM.formatDuration(3.25), SM.formatDuration(60)))
    # the storage changes: the history starts again
    lua.execute("set(m, 'pick', {30, 0}) m:rescanStorageMonitor() StorageMonitor.refreshStorageMonitorData(m)")
    check(spec.snapshot.rate is None, "another storage: no rate from the old one")


def test_prices(lua):
    """Price board: best price and where, value of the stock, seasonal trend."""
    lua.execute(WORLD)
    lua.execute("""
        local env = g_currentMission.environment
        env.currentPeriod = 3
        fillTypes[100].economy = {factors = {1, 1, 1.0, 1.1, 1, 1, 1, 1, 1, 1, 1, 1}}
        fillTypes[101].economy = {factors = {1, 1, 1.0, 0.8, 1, 1, 1, 1, 1, 1, 1, 1}}
        local function station(name, prices, farm)
            local p = {rootNode = newNode(500, 0, 0), getName = function() return name end, getOwnerFarmId = function() return farm or 0 end}
            local st = {owningPlaceable = p, isSellingPoint = true, acceptedFillTypes = {}}
            for ft in pairs(prices) do st.acceptedFillTypes[ft] = true end
            function st:getEffectiveFillTypePrice(ft) return prices[ft] end
            return st, p
        end
        local a = station("Grain Elevator", {[100] = 0.42})
        local b = station("Mill", {[100] = 0.38, [101] = 0.10})
        local c, cp = station("My Bakery", {[100] = 9.99}, 1)
        cp.spec_productionPoint = {}
        g_currentMission.storageSystem.getUnloadingStations = function() return {a, b, c} end
        g_i18n.formatMoney = function(self, v) return "$" .. StorageMonitor.groupDigits(v) end
        m = newMonitor(false)
        set(m, "mode", 2)
        m:rescanStorageMonitor()
        StorageMonitor.clock = StorageMonitor.clock + StorageMonitor.PRICE_INTERVAL
        frame()
        spec = m.spec_storageMonitor
    """)
    g = lua.globals()
    spec = g.spec
    snap = spec.snapshot
    t = texts(lua)
    items = {snap["items"][i].title: snap["items"][i] for i in range(1, snap.count + 1)}
    wheat, chaff = items["Wheat"], items["Chaff"]
    check(abs(wheat.price - 0.42) < 1e-9 and wheat.station == "Grain Elevator", "wheat: best price at the elevator, not the own production")
    check(abs(wheat.value - 42000) < 1e-6 and abs(snap.value - 42002.1) < 1e-6, "stock value %s" % snap.value)
    check(abs(wheat.trend - 10) < 1e-6 and abs(chaff.trend + 20) < 1e-6, "seasonal trends %s %s" % (wheat.trend, chaff.trend))
    check(snap["items"][1].title == "Wheat", "most valuable first")
    check("$42,002" in t and "Grain Elevator" in t and "$420" in t and "+10%" in t and "-20%" in t,
          "price board text: %s" % t[:30])
    check("1 rising  1 falling" in t, "rising / falling count")
    check(lua.eval("overlappingBars()") == 0, "price board: no bar lies on another")
    lua.execute("set(m, 'mode', 1) StorageMonitor.refreshStorageMonitorData(m) frame()")
    check(not spec.snapshot.prices and "STOCK VALUE" not in texts(lua), "back to the storage")


def test_alerts(lua):
    """Nearly full: a blinking stripe and the alert in the footer; a game message only for new alerts."""
    lua.execute(WORLD)
    lua.execute("""
        notes = {}
        FSBaseMission = {INGAME_NOTIFICATION_CRITICAL = 7}
        g_currentMission.addIngameNotification = function(self, kind, text) table.insert(notes, {kind = kind, text = text}) end
        sNear.fillLevels[100] = 940000      -- 94 %
        m = newMonitor(false)
        spec = m.spec_storageMonitor
        set(m, "alerts", 3)
        StorageMonitor.clock = 0
        frame()
        stripe = visibleBars()
        afterFirst = #notes
        -- a production next to it runs out of an input: a new alert, one message
        sNear.fillLevels[100] = 990000
        StorageMonitor.refreshStorageMonitorData(m)
        StorageMonitor.refreshStorageMonitorData(m)
        afterFull = #notes
        StorageMonitor.clock = 700        -- the stripe blinks
        frame()
        stripeOff = visibleBars()
    """)
    g = lua.globals()
    spec = g.spec
    keys = [spec.alertList[i].key for i in range(1, len(spec.alertList) + 1)]
    check(keys == ["full"], "silo at 94 %%: one alert (%s)" % keys)
    check(g.afterFirst == 0, "what is already there when the monitor starts is not announced")
    lua.execute("sNear.fillLevels[100] = 100000 StorageMonitor.refreshStorageMonitorData(m) sNear.fillLevels[100] = 990000 StorageMonitor.refreshStorageMonitorData(m)")
    check(len(g.notes) == 1 and "Multifruit Silo: Nearly full: 99%" == g.notes[1].text and g.notes[1].kind == 7,
          "a new alert gives one message: %s" % [g.notes[i].text for i in range(1, len(g.notes) + 1)])
    lua.execute("sNear.fillLevels[100] = 100000 StorageMonitor.refreshStorageMonitorData(m) sNear.fillLevels[100] = 990000 StorageMonitor.refreshStorageMonitorData(m)")
    check(len(g.notes) == 1, "the same alert again within 10 minutes: no second message")
    lua.execute("frame()")
    t = texts(lua)
    check(any(x.startswith("! Nearly full: 99%") for x in t), "alert in the footer: %s" % [x for x in t if x.startswith("!")])
    check(g.stripe > g.stripeOff, "the stripe blinks (%s / %s bars)" % (g.stripe, g.stripeOff))
    lua.execute("set(m, 'alerts', 1) StorageMonitor.refreshStorageMonitorData(m) frame()")
    check(len(spec.alertList) == 0 and not any(x.startswith("!") for x in texts(lua)), "alerts off")
    # another farm's monitor never sends a message
    lua.execute("""
        m2 = newMonitor(false)
        function m2:getOwnerFarmId() return 2 end
        set(m2, "alerts", 3)
        StorageMonitor.refreshStorageMonitorData(m2)
        sNear.fillLevels[100] = 100 StorageMonitor.refreshStorageMonitorData(m2)
        sNear.fillLevels[100] = 990000 StorageMonitor.announced = {} StorageMonitor.refreshStorageMonitorData(m2)
    """)
    check(len(g.notes) == 1, "another farm's monitor: no message")


KINDS2 = r"""
local function placeable(name, x, z)
    local p = {rootNode = newNode(x, 0, z), name = name}
    function p:getName() return self.name end
    function p:getOwnerFarmId() return 1 end
    return p
end
addFillType(140, "MANURE", "Manure")
addFillType(141, "WATER", "Water")
addFillType(142, "LETTUCE", "Lettuce")
-- a manure heap without getFillLevels
heap = placeable("Manure Heap", 6, 0)
heap.spec_manureHeap = {manureHeap = {fillTypeIndex = 140, capacity = 200000,
    getFillLevel = function(self, ft) return 150000 end, getOwnerFarmId = function() return 1 end}}
-- a greenhouse without water
greenhouse = placeable("Greenhouse", 12, 0)
local line = {id = "lettuce", name = "Lettuce", status = 2}
greenhouse.spec_productionPoint = {productionPoint = {
    storage = makeStorage({[141] = 0, [142] = 900}, 100000, {[141] = 20000, [142] = 50000}, 12, 0),
    productions = {line}, activeProductions = {line}, inputFillTypeIds = {[141] = true}, outputFillTypeIds = {[142] = true}}}
greenhouse.spec_greenhouse = {hasWater = false}
-- two beehives and a pallet spot that is full
hive1 = placeable("Beehive", 18, 0) hive1.spec_beehive = {honeyPerHour = 10 / 24}
hive2 = placeable("Beehive", 19, 0) hive2.spec_beehive = {honeyPerHour = 20 / 24}
spot = placeable("Honey Pallets", 30, 0) spot.spec_beehivePalletSpawner = {palletLimitReached = true}
g_currentMission.beehiveSystem = {isProductionActive = true, isFxActive = true}
-- the farm's money
g_farmManager = {getFarmById = function(self, id) return farm end}
farm = {money = 1250000, loan = 300000, loanMax = 500000,
        stats = {finances = {harvestIncome = 42000, newVehiclesCost = -150000, fuelCost = -1200, other = 0}}}
function farm:getBalance() return self.money end
FinanceStats = {statNames = {"newVehiclesCost", "harvestIncome", "fuelCost", "other"}}
g_i18n.formatMoney = function(self, v) return "$" .. StorageMonitor.groupDigits(v) end
-- a cow barn whose cows eat 1,000 l an hour
barn = placeable("Cow Barn", 40, 0)
barn.spec_husbandryAnimals = {}
barn.spec_husbandry = {storage = makeStorage({[141] = 5000}, 100000, {[141] = 100000}, 40, 0)}
barn.spec_husbandryFood = {litersPerHour = 1000}
function barn:getNumOfAnimals() return 30 end
function barn:getMaxNumOfAnimals() return 40 end
function barn:getTotalFood() return 36000 end
function barn:getFoodCapacity() return 100000 end
function barn:getConditionInfos()
    return {{title = "Productivity", ratio = 0.9, valueText = "90 %"}, {title = "Water", ratio = 0.05}}
end

g_currentMission.placeableSystem.placeables = {heap, greenhouse, hive1, hive2, spot, barn}
g_currentMission.storageSystem = {getLoadingStations = function() return {} end, getUnloadingStations = function() return {} end}
m = newMonitor(false)
function show(name)
    for _, c in ipairs(StorageMonitor.collectStorageCandidates(m)) do
        if c.name == name then
            set(m, "pick", {c.anchor[1], c.anchor[2]})
            m:rescanStorageMonitor()
            frame()
            return
        end
    end
    error("no candidate " .. name)
end
"""


def test_more_kinds(lua):
    lua.execute(WORLD)
    lua.execute(KINDS2)
    g = lua.globals()
    spec = g.m.spec_storageMonitor
    names = [c.name for c in g.StorageMonitor.collectStorageCandidates(g.m).values()]
    check(names == ["Manure Heap", "Greenhouse", "Beehives", "Cow Barn", "My farm's money", "All my animal pens", "All my productions", "What my productions need", "Production profit", "Message board"],
          "candidates: heap, greenhouse, the beehives as one, barn, then money, all pens, all productions: %s" % names)

    lua.execute('show("Manure Heap")')
    t = texts(lua)
    check(spec.snapshot.capacity == 200000 and spec.snapshot.used == 150000 and "75%" in t, "manure heap 150,000 of 200,000 l")

    lua.execute('show("Greenhouse")')
    t = texts(lua)
    keys = [spec.alertList[i].key for i in range(1, len(spec.alertList) + 1)]
    check(spec.snapshot.panel.noWater is True and "No water" in t, "greenhouse without water: %s" % t[:12])
    check("noWater" in keys and "empty_141" in keys, "greenhouse alerts: %s" % keys)

    lua.execute('show("Beehives")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.kind == "beehive" and panel.hives == 2 and abs(panel.honeyPerDay - 30) < 1e-6 and panel.palletFull,
          "beehives: 2 hives, 30 l a day, pallet spot full")
    check("2" in t and "30 l" in t and "Full" in t, "beehive panel text: %s" % t[:16])
    check([spec.alertList[i].key for i in range(1, len(spec.alertList) + 1)] == ["palletFull"], "beehive alert")

    lua.execute('show("Cow Barn")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(abs(panel.foodHours - 36) < 1e-6 and "Food for 36 h" in t, "36,000 l of food at 1,000 l/h: 36 h (%s)" % panel.foodHours)
    keys = [spec.alertList[i].key for i in range(1, len(spec.alertList) + 1)]
    check(keys == ["low_Water"], "barn: water low; productivity is not a supply (%s)" % keys)

    lua.execute('show("My farm\'s money")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.kind == "finance" and panel.money == 1250000 and panel.income == 42000 and panel.expenses == -151200,
          "finance panel %s %s %s" % (panel.money, panel.income, panel.expenses))
    check(spec.snapshot.count == 3 and panel.lines[1].name == "newVehiclesCost", "finance lines, biggest first, zero left out")
    check("$1,250,000" in t and "$200,000" in t and "+$42,000" in t and "-$109,200" in t, "finance text: %s" % t[:22])
    check(lua.eval("overlappingBars()") == 0, "new kinds: no bar lies on another")
    # money and prices do not mix: the money screen stays
    lua.execute("set(m, 'mode', 2) StorageMonitor.refreshStorageMonitorData(m) frame()")
    check(spec.snapshot.finance is True and not spec.snapshot.prices, "money ignores the price board setting")


FARM = r"""
local function placeable(name, x, z)
    local p = {rootNode = newNode(x, 0, z), name = name}
    function p:getName() return self.name end
    function p:getOwnerFarmId() return 1 end
    return p
end
ProductionPoint = {PROD_STATUS = {INACTIVE = 0, RUNNING = 1, MISSING_INPUTS = 2, NO_OUTPUT_SPACE = 3}}
addFillType(150, "FLOUR", "Flour") addFillType(151, "BREAD", "Bread")
-- two pens and a production of the farm, far from the monitor (the farm screens list them anyway)
barn = placeable("Cow Barn", 400, 0)
barn.spec_husbandryAnimals = {}
barn.spec_husbandry = {storage = makeStorage({}, 100000, {}, 400, 0)}
barn.spec_husbandryFood = {litersPerHour = 1000}
function barn:getNumOfAnimals() return 30 end
function barn:getMaxNumOfAnimals() return 40 end
function barn:getTotalFood() return 36000 end
function barn:getFoodCapacity() return 100000 end
function barn:getConditionInfos() return {{title = "Water", ratio = 0.05}, {title = "Straw", ratio = 0.6}} end
sty = placeable("Pig Barn", 420, 0)
sty.spec_husbandryAnimals = {}
sty.spec_husbandry = {storage = makeStorage({}, 100000, {}, 420, 0)}
function sty:getNumOfAnimals() return 10 end
function sty:getMaxNumOfAnimals() return 20 end
function sty:getTotalFood() return 90000 end
function sty:getFoodCapacity() return 100000 end
function sty:getConditionInfos() return {{title = "Water", ratio = 0.9}} end
bakery = placeable("Mill Bakery", 440, 0)
local line = {id = "bread", name = "Bread", status = 2}
bakery.spec_productionPoint = {productionPoint = {storage = makeStorage({[150] = 0, [151] = 10}, 100000, {[150] = 5000, [151] = 5000}, 440, 0),
    productions = {line}, activeProductions = {line}, inputFillTypeIds = {[150] = true}, outputFillTypeIds = {[151] = true}}}
table.insert(g_currentMission.placeableSystem.placeables, barn)
table.insert(g_currentMission.placeableSystem.placeables, sty)
table.insert(g_currentMission.placeableSystem.placeables, bakery)

-- fields: 12 wheat ready, 7 canola growing (needs lime), 3 withered
local function fruit(i, name, title)
    local f = {index = i, name = name, fillType = {name = name, title = title}, minHarvestingGrowthState = 7,
               maxHarvestingGrowthState = 8, minPreparingGrowthState = -1, maxPreparingGrowthState = -1, cutState = 10}
    function f:getIsWithered(g) return g == 9 end
    return f
end
fruits = {fruit(1, "WHEAT", "Wheat"), fruit(2, "CANOLA", "Canola")}
g_fruitTypeManager = {getFruitTypeByIndex = function(self, i) return fruits[i] end}
local spots = {[1200] = {1, 8}, [700] = {2, 3}, [300] = {1, 9}, [500] = {2, 8}}
fieldUpdates = 0
local function field(id, ha, owner, lime)
    local f = {farmland = {id = id, owner = owner}, areaHa = ha, fieldState = {limeLevel = lime, plowLevel = 1, sprayLevel = 2, rollerLevel = 0, weedState = 0}}
    function f.fieldState:update(x, z) fieldUpdates = fieldUpdates + 1 end
    function f:getCenterOfFieldWorldPosition() return id * 100, 0 end
    function f:getId() return id end
    return f
end
fields = {field(12, 10, 1, 1), field(7, 5, 1, 0), field(3, 2, 1, 1), field(5, 9, 2, 1)}
g_fieldManager = {getFields = function() return fields end}
g_farmlandManager = {getFarmlandOwner = function(self, id) for _, f in ipairs(fields) do if f.farmland.id == id then return f.farmland.owner end end end}
FSDensityMapUtil = {getFruitTypeIndexAtWorldPos = function(x, z) local s = spots[x] return s[1], s[2] end}
FieldDensityMap = {SPRAY_LEVEL = 1}
g_currentMission.missionInfo = {limeRequired = true}
g_currentMission.fieldGroundSystem = {getMaxValue = function() return 2 end}

-- weather: sunny now, rain from 17:00
WeatherType = {SUN = 1, CLOUDY = 2, RAIN = 3}
local env = g_currentMission.environment
env.dayTime, env.currentDay, env.currentHour = 15 * 3600000, 4, 15
weather = {forecast = {getCurrentWeather = function() return {temperature = 18.4} end}}
function weather:getCurrentWeatherType() return 1 end
function weather:getNextWeatherType(dayTime, day)
    if day == 4 and dayTime >= 17 * 3600000 then return 3 end
    if day == 4 then return 1 end
    return 2
end
function weather:getCurrentMinMaxTemperatures() return 9, 21 end
function weather:getIsRaining() return false end
env.weather = weather

-- vehicles: a helper at 5 % fuel, a parked tractor with 75 % damage, an implement and another farm's truck
VehiclePropertyState = {OWNED = 1, LEASED = 2, MISSION = 3}
FillType = {DIESEL = 1}
local function vehicle(id, name, fuel, damage, ai, farm, extra)
    local v = {id = id, typeName = "tractor", propertyState = 1}
    function v:getFullName() return name end
    function v:getOwnerFarmId() return farm or 1 end
    function v:getIsControlled() return false end
    function v:getIsAIActive() return ai end
    function v:getDamageAmount() return damage end
    function v:getConsumerFillUnitIndex(ft) return ft == 1 and 1 or nil end
    function v:getFillUnitFillLevel() return fuel * 400 end
    function v:getFillUnitCapacity() return 400 end
    for k, x in pairs(extra or {}) do v[k] = x end
    return v
end
g_currentMission.vehicleSystem = {vehicles = {vehicle(1, "Fendt 942", 0.05, 0.1, true), vehicle(2, "Case Magnum", 0.8, 0.75, false),
    vehicle(3, "Plough", 0, 0, false, 1, {spec_attachable = {}}), vehicle(4, "Neighbour Truck", 0.5, 0, false, 2),
    vehicle(5, "Contract Combine", 0.5, 0, false, 1, {propertyState = 3})}}

-- contracts: one running at 95 %, one finished
MissionStatus = {RUNNING = 2, FINISHED = 3}
local function mission(title, status, completion, reward)
    local m = {status = status}
    function m:getTitle() return title end
    function m:getLocation() return "Field 9" end
    function m:getCompletion() return completion end
    function m:getReward() return reward end
    return m
end
g_missionManager = {getMissionsByFarmId = function() return {mission("Harvesting", 2, 0.95, 40000), mission("Baling", 3, 1, 9000)} end}
g_i18n.formatMoney = function(self, v) return "$" .. StorageMonitor.groupDigits(v) end

m = newMonitor(false)
spec = m.spec_storageMonitor
function showScreen(kind)
    for _, c in ipairs(StorageMonitor.collectStorageCandidates(m)) do
        if c.kind == kind then
            set(m, "pick", {c.anchor[1], c.anchor[2]})
            m:rescanStorageMonitor()
            frame()
            return
        end
    end
    error("no screen " .. kind)
end
function alertIds()
    local ids = {}
    for _, a in ipairs(spec.alertList) do table.insert(ids, a.key) end
    return table.concat(ids, ",")
end
"""


def test_farm_screens(lua):
    """The screens of the whole farm: fields, weather, vehicles, contracts, all pens, all productions."""
    lua.execute(WORLD)
    lua.execute(FARM)
    g = lua.globals()
    spec = g.spec
    kinds = [c.kind for c in g.StorageMonitor.collectStorageCandidates(g.m).values()]
    check(kinds[-12:] == ["farm", "fields", "weather", "fleet", "contracts", "allPens", "allProductions", "prodNeeds", "sellPlan", "profit", "fieldMap", "message"],
          "farm screens at the end of the list: %s" % kinds)
    pick_nearest = lua.eval("StorageMonitor.choose(StorageMonitor.collectStorageCandidates(m), nil).kind")
    check(pick_nearest == "silo", "the nearest is never a farm screen (%s)" % pick_nearest)

    lua.execute('showScreen("fields")')
    t = texts(lua)
    panel = spec.snapshot.panel
    titles = [panel.rows[i].title for i in range(1, len(panel.rows) + 1)]
    check(panel.count == 3 and panel.ready == 1 and panel.withered == 1 and panel.growing == 1,
          "fields: 3 own, 1 ready, 1 withered, 1 growing (%s)" % titles)
    check(titles == ["Field 12  Wheat", "Field 3  Wheat", "Field 7  Canola"], "ready first, then withered, then growing: %s" % titles)
    check(abs(panel.area - 17) < 1e-6 and "17.0 ha" in t, "own area 17 ha")
    check(panel.rows[3].sub == "Lime" and panel.work == 1, "the canola field needs lime: %s" % panel.rows[3].sub)
    check(g.fieldUpdates == 3, "each own field's ground is read fresh (%d)" % g.fieldUpdates)
    check("READY TO HARVEST" in t and "Harvest" in t and "Withered" in t and "Growing 43%" in t, "fields text: %s" % t[:30])
    ids = lua.eval("alertIds()")
    check(ids == "ready_12,withered_3,harvestRain", "fields alerts (rain in 2 h with a field ready): %s" % ids)
    check(spec.layout.pages == 1 and not spec.snapshot.prices, "a board has no prices")
    check(lua.eval("overlappingBars()") == 0, "fields: no bar lies on another")
    # read once for all monitors every 10 s
    lua.execute("frame() frame()")
    check(g.fieldUpdates == 3, "fields are read at most every 10 s (%d)" % g.fieldUpdates)

    lua.execute('showScreen("weather")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.now.id == "SUN" and panel.change.hours == 2 and panel.change.info.id == "RAIN", "sunny, rain in 2 h")
    check("18°" in t and "Rain in 2 h" in t and "21° / 9°" in t and "17:00" in t and "Tomorrow" in t, "weather text: %s" % t[:40])
    check(lua.eval("alertIds()") == "wetSoon", "rain within 3 h is an alert")

    lua.execute('showScreen("fleet")')
    t = texts(lua)
    panel = spec.snapshot.panel
    names = [panel.rows[i].title for i in range(1, len(panel.rows) + 1)]
    check(names == ["Fendt 942", "Case Magnum"], "fleet: own driven vehicles, the helper low on fuel first: %s" % names)
    check(panel.helpers == 1 and panel.lowFuel == 1 and panel.repair == 1, "1 helper, 1 low on fuel, 1 to repair")
    ids = lua.eval("alertIds()")
    check(ids == "fuel_Fendt 942,damage_Case Magnum", "fleet alerts: %s" % ids)
    check("Helper working" in t and "5%" in t and "Parked, damage 75%" in t, "fleet text: %s" % t[:30])

    lua.execute('showScreen("contracts")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.count == 1 and panel.almostDone == 1 and panel.reward == 40000, "1 contract running, almost done")
    check("Harvesting" in t and "95%" in t and "Field 9  $40,000" in t, "contracts text: %s" % t[:24])

    lua.execute('showScreen("allPens")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.count == 2 and panel.animals == 40 and panel.maxAnimals == 60 and panel.lowSupply == 1, "pens: 40/60 animals, 1 low on water")
    check(panel.rows[1].title == "Cow Barn" and panel.rows[1].sub.startswith("Water 5%"), "the pen lowest on a supply first, lowest supply first: %s" % panel.rows[1].sub)
    check("36 h" in t, "food lasts 36 h (36,000 l at 1,000 l/h): %s" % t[:30])
    check(any("Cow Barn" in spec.alertList[i].text for i in range(1, len(spec.alertList) + 1)), "a pen low on water is an alert")

    lua.execute('showScreen("allProductions")')
    t = texts(lua)
    panel = spec.snapshot.panel
    rows = {panel.rows[i].title: panel.rows[i] for i in range(1, len(panel.rows) + 1)}
    check(panel.count == 2 and panel.missing == 1 and rows["Mill Bakery"].sub == "Missing: Flour" and panel.rows[1].title == "Mill Bakery",
          "productions: the mill bakery misses flour, first: %s" % list(rows))
    check("0/1" in t and "Missing: Flour" in t, "productions text: %s" % t[:24])
    check(lua.eval("overlappingBars()") == 0, "farm screens: no bar lies on another")


def test_history_and_settings(lua):
    """History graph, nearly-full level, price alert, slideshow; all saved and synced."""
    lua.execute(WORLD)
    lua.execute("""
        notes = {}
        FSBaseMission = {INGAME_NOTIFICATION_CRITICAL = 7}
        g_currentMission.addIngameNotification = function(self, kind, text) table.insert(notes, text) end
        local env = g_currentMission.environment
        env.dayTime, env.currentDay = 6 * 3600000, 2
        m = newMonitor(false)
        spec = m.spec_storageMonitor
        set(m, "mode", 3)
        frame()
        for h = 1, 30 do       -- 30 in-game hours, a read every half hour
            env.dayTime = env.dayTime + 1800000
            if env.dayTime >= 86400000 then env.dayTime, env.currentDay = env.dayTime - 86400000, env.currentDay + 1 end
            StorageMonitor.refreshStorageMonitorData(m)
        end
        frame()
    """)
    g = lua.globals()
    spec = g.spec
    t = texts(lua)
    n = len(spec.snapshot.graph)
    check(spec.snapshot.showGraph and 30 <= n <= 49, "history: a sample per half hour for 24 h (%d)" % n)
    check("LAST 24 IN-GAME HOURS" in t and "NOW 10%" in t and "100%" in t, "graph text: %s" % [x for x in t if "%" in x or "HOURS" in x])
    check(spec.layout.pages == 1, "the graph has no pages")
    check(lua.eval("overlappingBars()") == 0, "graph: no bar lies on another")

    # nearly full from 10 %: red, an alert
    lua.execute("set(m, 'fullAt', 50) set(m, 'alerts', 2) StorageMonitor.refreshStorageMonitorData(m)")
    check(spec.fullAt == 50 and len(spec.alertList) == 0, "10 % is not nearly full at 50 %")
    lua.execute("sNear.fillLevels[100] = 600000 StorageMonitor.refreshStorageMonitorData(m)")
    check([spec.alertList[i].key for i in range(1, len(spec.alertList) + 1)] == ["full"], "60 % is nearly full at 50 %")
    lua.execute("StorageMonitor.fullAt = 50 colorsOk = StorageMonitor.levelColor(60) == StorageMonitor.COLORS.full and StorageMonitor.levelColor(40) == StorageMonitor.COLORS.warn")
    check(g.colorsOk,
          "colours follow the level: red from 50, amber from 35")
    lua.execute("StorageMonitor.fullAt = 90")

    # price alert: wheat from $400 per 1000 l; the elevator pays $420
    lua.execute("""
        local p = {getName = function() return "Grain Elevator" end}
        local st = {owningPlaceable = p, isSellingPoint = true, acceptedFillTypes = {[100] = true}}
        function st:getEffectiveFillTypePrice(ft) return 0.42 end
        g_currentMission.storageSystem.getUnloadingStations = function() return {st} end
        g_fillTypeManager.getFillTypeIndexByName = function(self, name) for i, f in pairs(fillTypes) do if f.name == name then return i end end end
        StorageMonitor.priceCache = nil
        set(m, "alerts", 3)
        set(m, "priceAlert", {fill = "WHEAT", price = 450})
        StorageMonitor.refreshStorageMonitorData(m)
        noPrice = #spec.alertList
        set(m, "priceAlert", {fill = "WHEAT", price = 400})
        StorageMonitor.refreshStorageMonitorData(m)
    """)
    check(g.noPrice == 1, "below the price: no price alert")
    texts_ = [spec.alertList[i].text for i in range(1, len(spec.alertList) + 1)]
    check("Wheat sells for $420 at Grain Elevator" in texts_, "price alert: %s" % texts_)
    check("Wheat sells for $420 at Grain Elevator" in list(g.notes.values()), "the price alert is a game message: %s" % list(g.notes.values()))

    # slideshow: two screens, 10 s each
    lua.execute("""
        set(m, "slides", {{30, 0}, {4, 0}})
        set(m, "slideTime", 2)
        m:rescanStorageMonitor()
        first = spec.target.name
        for i = 1, 700 do frame() end       -- 11 s
        second = spec.target.name
        for i = 1, 650 do frame() end
        third = spec.target.name
    """)
    check(g.first == "Grain Silo" and g.second == "Multifruit Silo" and g.third == "Grain Silo",
          "slideshow takes turns: %s, %s, %s" % (g.first, g.second, g.third))
    check("2/2" in texts(lua) or "1/2" in texts(lua), "the slideshow counter in the header")

    # saved and synced: write and read the settings
    lua.execute("""
        stream = {}
        StorageMonitor.writeSettings(stream, m:getStorageMonitorSettings())
        back = StorageMonitor.readSettings(stream)
        saved = {}
        local xml = {setValue = function(self, k, v) saved[k] = v end,
                     getValue = function(self, k, d) if saved[k] == nil then return d end return saved[k] end,
                     hasProperty = function(self, k) return saved[k .. "#x"] ~= nil end}
        StorageMonitor.saveToXMLFile(m, xml, "k")
        m2 = newMonitor(false)
        StorageMonitor.loadFromXMLFile(m2, xml, "k")
    """)
    back = g.back
    check(back.fullAt == 50 and back.priceAlert.fill == "WHEAT" and back.priceAlert.price == 400 and back.slideTime == 2
          and len(back.slides) == 2 and back.slides[2][1] == 4, "settings stream round trip")
    s2 = g.m2.spec_storageMonitor
    check(s2.fullAt == 50 and s2.priceAlert.price == 400 and s2.slideTime == 2 and len(s2.slides) == 2 and s2.slides[1][1] == 30,
          "settings saved and loaded")


V14 = r"""
-- seasonal prices: wheat best in 3 months (+20 %), chaff best now
local env = g_currentMission.environment
env.currentPeriod = 3
fillTypes[100].economy = {factors = {1, 1, 1.0, 1.05, 1.1, 1.2, 1, 1, 1, 1, 1, 1}}
fillTypes[101].economy = {factors = {1, 1, 1.0, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9}}
local p = {getName = function() return "Grain Elevator" end}
local st = {owningPlaceable = p, isSellingPoint = true, acceptedFillTypes = {[100] = true, [101] = true, [1] = true, [2] = true}}
function st:getEffectiveFillTypePrice(ft) return ({[100] = 0.5, [101] = 0.1, [1] = 0.2, [2] = 1.0})[ft] end
g_currentMission.storageSystem.getUnloadingStations = function() return {st} end
StorageMonitor.priceCache = nil
fruits[1].literPerSqm = 0.9
fruits[1].fillType.index = 100
for _, f in ipairs(fields) do function f.fieldState:getHarvestScaleMultiplier() return 1.5 end end
-- a production line: 2 l of type 1 ($0.20) -> 1 l of type 2 ($1.00), 100 cycles an hour, $30 an hour upkeep
local bakeryPP = bakery.spec_productionPoint.productionPoint
bakeryPP.productions[1].inputs = {{type = 1, amount = 2}}
bakeryPP.productions[1].outputs = {{type = 2, amount = 1}}
bakeryPP.productions[1].cyclesPerHour = 100
bakeryPP.productions[1].costsPerActiveHour = 30
-- contracts to take: one on a 10 ha field, one transport
MissionStatus.CREATED = 0
local function open(title, reward, field)
    local m = {status = 0, field = field}
    function m:getTitle() return title end
    function m:getReward() return reward end
    return m
end
local f14 = {areaHa = 10} function f14:getId() return 14 end
g_missionManager.missions = {open("Sowing", 20000, f14), open("Transport", 9000, nil)}
MissionManager = {MAX_MISSIONS_PER_FARM = 3}
-- farms: mine and a richer neighbour
FarmManager = {SPECTATOR_FARM_ID = 0}
local farms = {{farmId = 0, name = "Spectators", money = 0}, {farmId = 1, name = "DTM", money = 500000, loan = 0},
               {farmId = 2, name = "Neighbours", money = 900000, loan = 100000}}
g_farmManager = {getFarms = function() return farms end, getFarmById = function(self, id) return farms[id + 1] end}
-- field outlines: field 12 a 100 x 100 square, field 7 a 50 x 100 strip next to it
fields[1].getDensityMapPolygon = function() return {getVerticesList = function() return {0, 0, 100, 0, 100, 100, 0, 100} end} end
fields[2].getDensityMapPolygon = function() return {getVerticesList = function() return {120, 0, 170, 0, 170, 100, 120, 100} end} end
StorageMonitor.boardCache = {}
"""


def test_v14(lua):
    """1.4: when to sell, yield and harvest window, profit, contracts to take, all farms, field map, message board,
    products shown, screens by hand, the server's history."""
    lua.execute(WORLD)
    lua.execute(FARM)
    lua.execute(V14)
    g = lua.globals()
    spec = g.spec
    kinds = [c.kind for c in g.StorageMonitor.collectStorageCandidates(g.m).values()]
    check(all(k in kinds for k in ["sellPlan", "profit", "openContracts", "farms", "fieldMap", "message"]), "new screens listed: %s" % kinds)

    lua.execute('showScreen("sellPlan")')
    t = texts(lua)
    panel = spec.snapshot.panel
    rows = {panel.rows[i].title: panel.rows[i] for i in range(1, len(panel.rows) + 1)}
    check(rows["Chaff"].sub == "Sell now: the best month" and rows["Wheat"].sub == "Best in 3 months: +20%",
          "sell plan: chaff now, wheat in 3 months: %s / %s" % (rows["Chaff"].sub, rows["Wheat"].sub))
    check(panel.rows[1].title == "Chaff", "sell now first")
    check(abs(panel.valueBest - panel.valueNow - 705000 * 0.5 * 0.2) < 1, "waiting gains 20 %% of the wheat: %s" % (panel.valueBest - panel.valueNow))

    lua.execute('showScreen("fields")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(abs(panel.harvestValue - 0.9 * 10 * 10000 * 1.5 * 0.5) < 1 and "~135000 l  $67,500" in t,
          "field 12: 135,000 l of wheat worth $67,500: %s" % [x for x in t if x.startswith("~")])
    check(panel.dryFor == 2 and "Dry for 2 h" in t, "harvest window: dry for 2 h (%s)" % panel.dryFor)

    lua.execute('showScreen("profit")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.count == 1 and abs(panel.perHour - (100 * 1.0 - 200 * 0.2 - 30)) < 1e-6, "profit: $100 out - $40 in - $30 = $30/h (%s)" % panel.perHour)
    check("+$30/h" in t and "$720" in t, "profit text (and $720 a day): %s" % t[:20])

    lua.execute('showScreen("openContracts")')
    t = texts(lua)
    panel = spec.snapshot.panel
    check(panel.count == 2 and panel.rows[1].title == "Sowing" and "$2,000/ha" in t and panel.running == 1 and panel.max == 3,
          "contracts to take: sowing $2,000/ha first, 1 of 3 running: %s" % t[:24])

    lua.execute('showScreen("farms")')
    t = texts(lua)
    panel = spec.snapshot.panel
    names = [panel.rows[i].title for i in range(1, len(panel.rows) + 1)]
    check(names == ["Neighbours", "DTM (you)"] and panel.place == 2 and "#2" in t and "$900,000" in t,
          "all farms: the richest first, mine marked: %s" % names)

    lua.execute('showScreen("fieldMap")')
    t = texts(lua)
    panel = spec.snapshot.panel
    runs = panel.map.runs
    ids = sorted(set(runs[i][5] for i in range(1, len(runs) + 1)))
    check(len(runs) > 10 and ids == ["12", "3", "7"], "field map: runs of cells for fields 12 and 7 (outlines) and 3 (a square of its area) (%d runs, %s)" % (len(runs), ids))
    check("12" in t and "7" in t and "Harvest" in t, "field map labels and legend: %s" % t[:24])
    check(lua.eval("overlappingBars()") == 0, "field map: no bar lies on another")

    # message board
    lua.execute("""
        showScreen("message")
        emptyTexts = calls.text
        set(m, "message", "Do not unload corn here|it is for the BGA")
        set(m, "messageTime", 12 * 24 + 14.5)
        frame()
    """)
    t = texts(lua)
    check("Nothing written yet" in list(g.emptyTexts.values()), "empty message board says so")
    check("Do not unload corn here" in t and "it is for the BGA" in t and "Written on day 12 at 14:30" in t,
          "message board: two lines and when: %s" % t)

    # only wheat: the big single-product view
    lua.execute("""
        set(m, "pick", {4, 0}) set(m, "only", {"WHEAT"}) m:rescanStorageMonitor() frame()
    """)
    t = texts(lua)
    check(spec.snapshot.single is not None and spec.snapshot.single.title == "Wheat" and "WHEAT" in t, "one product: shown big")
    check(lua.eval("overlappingBars()") == 0, "single product: no bar lies on another")
    lua.execute("set(m, 'only', {}) m:rescanStorageMonitor() frame()")
    check(spec.snapshot.single is None and spec.snapshot.count == 2, "all products again")

    # screens by hand: the next one in the pick list
    lua.execute("""
        before = spec.target.name
        StorageMonitor.activeMonitor = m
        StorageMonitor.onActionNextScreen()
        after = spec.target.name
        StorageMonitor.onActionPrevScreen()
        back = spec.target.name
    """)
    check(g.after != g.before and g.back == g.before, "next / previous screen: %s -> %s -> %s" % (g.before, g.after, g.back))

    # the server's history: a sample, an event to the players, saved and sent to a player joining
    lua.execute("""
        sentEvents = {}
        g_server = {broadcastEvent = function(self, event) table.insert(sentEvents, event) end}
        set(m, "pick", {4, 0})
        local env = g_currentMission.environment
        env.dayTime, env.currentDay = 10 * 3600000, 5
        for i = 1, 3 do
            StorageMonitor.updateServer(StorageMonitor.SERVER_INTERVAL)
            env.dayTime = env.dayTime + 3600000
        end
        g_server = nil
        saved = {}
        local xml = {setValue = function(self, k, v) saved[k] = v end,
                     getValue = function(self, k, d) if saved[k] == nil then return d end return saved[k] end,
                     hasProperty = function(self, k) return saved[k .. "#x"] ~= nil end}
        StorageMonitor.saveToXMLFile(m, xml, "k")
        m3 = newMonitor(false)
        StorageMonitor.loadFromXMLFile(m3, xml, "k")
        stream = {}
        StorageMonitor.onWriteStream(m, stream)
        m4 = newMonitor(false)
        StorageMonitor.onReadStream(m4, stream)
        -- a player gets the event
        StorageMonitorGraphEvent.run(sentEvents[#sentEvents])
    """)
    h = spec.serverHistory
    check(h is not None and h.key == "4.0,0.0" and len(h.graph) == 3, "server history: 3 samples for the silo extension (%s)" % (h and len(h.graph)))
    check(len(g.sentEvents) == 3 and g.sentEvents[1].reset is True and g.sentEvents[2].reset is False, "a sample event each, the first starts the history")
    check(len(g.m3.spec_storageMonitor.serverHistory.graph) == 3, "server history saved and loaded")
    check(len(g.m4.spec_storageMonitor.serverHistory.graph) == 3, "server history sent to a player joining")
    lua.execute("set(m, 'mode', 3) m:rescanStorageMonitor() StorageMonitor.refreshStorageMonitorData(m)")
    check(spec.snapshot.graph is not None and len(spec.snapshot.graph) == 3, "the graph is the server's history")


def test_visitor_sees_owner_farm(lua):
    """A player of another farm looking at a farm's board sees that farm's data, not their own; no messages."""
    lua.execute(WORLD)
    lua.execute(FARM)
    lua.execute(V14)
    lua.execute("""
        function m:getOwnerFarmId() return 1 end
        g_localPlayer.farmId = 2            -- the visitor
        notes = {}
        FSBaseMission = {INGAME_NOTIFICATION_CRITICAL = 7}
        g_currentMission.addIngameNotification = function(self, kind, text) table.insert(notes, text) end
        set(m, "alerts", 3)
    """)
    g = lua.globals()
    spec = g.spec
    lua.execute('showScreen("fields")')
    panel = spec.snapshot.panel
    check(panel.count == 3 and panel.ready == 1, "visitor: the owner's 3 fields, not the visitor's 1 (%s)" % panel.count)
    lua.execute('showScreen("fleet")')
    names = [spec.snapshot.panel.rows[i].title for i in range(1, len(spec.snapshot.panel.rows) + 1)]
    check(names == ["Fendt 942", "Case Magnum"], "visitor: the owner's vehicles, not the neighbour's truck: %s" % names)
    lua.execute('showScreen("farms")')
    panel = spec.snapshot.panel
    titles = [panel.rows[i].title for i in range(1, len(panel.rows) + 1)]
    check(panel.place == 2 and titles == ["Neighbours (you)", "DTM"], "visitor: the board's place is the owner's, 'you' is the visitor: %s" % titles)
    lua.execute("""
        StorageMonitor.boardCache = {}
        showScreen("fields")
        StorageMonitor.announced = {}
        fields[2].farmland.owner = 2       -- something changes: a new alert on the owner's board
        fields[1].farmland.owner = 1
        StorageMonitor.boardCache = {}
        StorageMonitor.refreshStorageMonitorData(m)
    """)
    check(len(g.notes) == 0, "visitor: no game messages from another farm's board (%s)" % list(g.notes.values()))
    check(lua.eval("StorageMonitor.farmOverride") is None, "the farm is put back after reading")
    check(lua.eval("StorageMonitor.getPlayerFarmId()") == 2, "outside a board the player's own farm")


def test_materials_never_kept(lua):
    """The game frees a material no shape uses. Icons and themes must never reuse a material id they made earlier:
    1.4.0.0 / 1.4.0.1 kept them and hit 'setMaterial: Unknown entity id' when a slot came back to a product."""
    lua.execute(WORLD)
    lua.execute("""
        -- the engine: after each frame every made material no node uses is gone; setMaterial on a gone one fails
        freed = {}
        badSets = 0
        local realSetMaterial = setMaterial
        function setMaterial(n, m, i)
            if freed[m] then badSets = badSets + 1 end
            realSetMaterial(n, m, i)
        end
        local realDerive = setMaterialDiffuseMapFromFile
        function setMaterialDiffuseMapFromFile(m, path, a, b, c)
            if freed[m] then badSets = badSets + 1 end
            return realDerive(m, path, a, b, c)
        end
        function freeUnused()
            local used = {}
            for _, m in pairs(nodeMaterial) do used[m] = true end
            for id = 2, #materials do
                if not used[id] then freed[id] = true end
            end
        end
        a = newMonitor(false)
        b = newMonitor(false)
        -- many products on pages: the icon slots change product every page and come back
        for i = 1, 60 do sNear.fillLevels[i] = 1000 + i end
        for i = 1, 60 do fillTypes[i].hudOverlayFilename = "$dataS/hud/fill_" .. i .. ".png" end
        StorageMonitor.refreshStorageMonitorData(a) StorageMonitor.refreshStorageMonitorData(b)
        for step = 1, 8 do
            frame() freeUnused()
            StorageMonitor.scrollStorageMonitor(a, 1) StorageMonitor.scrollStorageMonitor(b, 1)
        end
        -- themes back and forth, and a monitor removed
        for _, t in ipairs({2, 3, 1, 2, 4, 2}) do set(a, "theme", t) set(b, "theme", t) frame() freeUnused() end
        StorageMonitor.onDelete(a)
        for step = 1, 4 do frame() freeUnused() StorageMonitor.scrollStorageMonitor(b, 1) end
        iconsShown = visibleIcons()
        local glass = b.spec_storageMonitor.faces[1].glassNode
        bGlass = materials[nodeMaterial[glass]].texture
    """)
    g = lua.globals()
    check(g.badSets == 0, "no material id is used after the game freed it (%d times)" % g.badSets)
    check(g.iconsShown > 0, "icons still shown (%d)" % g.iconsShown)
    check(str(g.bGlass).endswith("screen_field.dds"), "the theme is on the glass: %s" % g.bGlass)


def test_two_faces(lua):
    """A two-sided billboard draws on the side the camera is in front of, with that side's own bars."""
    lua.execute(WORLD)
    lua.execute("""
        m = newMonitor(false, true)
        spec = m.spec_storageMonitor
        frame()
        frontBars, frontTexts = 0, #calls.text
        for _, slot in ipairs(spec.faces[1].bars) do if shapes[slot.node].visible then frontBars = frontBars + 1 end end
        backBefore = #spec.faces[2].bars
        nodes[camera] = {0, 2, -6} flipped[camera] = true
        frame()
        backBars, backTexts = 0, #calls.text
        for _, slot in ipairs(spec.faces[2].bars) do if shapes[slot.node].visible then backBars = backBars + 1 end end
        frontAfter = 0
        for _, slot in ipairs(spec.faces[1].bars) do if shapes[slot.node].visible then frontAfter = frontAfter + 1 end end
        set(m, "theme", 2)
        nodes[camera] = {0, 2, 6} flipped[camera] = nil
    """)
    g = lua.globals()
    spec = g.spec
    check(len(spec.faces) == 2, "two faces")
    check(g.frontBars > 0 and g.frontTexts > 0 and g.backBefore == 0, "in front: the front face only")
    check(g.backBars > 0 and g.backTexts > 0 and g.frontAfter == 0, "behind: the back face, the front's bars hidden")
    tex = [str(lua.eval("materials[nodeMaterial[%d]].texture" % spec.faces[i].glassNode)) for i in (1, 2)]
    check(all(x.endswith("screen_field.dds") for x in tex), "theme on both glasses: %s" % tex)


def test_performance(lua):
    """Far monitors read their storage every 10 s, not every second; at most MAX_DRAWN are drawn."""
    lua.execute(WORLD)
    lua.execute("""
        m = newMonitor(false)
        spec = m.spec_storageMonitor
        nodes[camera] = {0, 2, 300}
        reads = 0
        local real = StorageMonitor.refreshStorageMonitorData
        StorageMonitor.refreshStorageMonitorData = function(...) reads = reads + 1 return real(...) end
        for i = 1, 600 do for _, l in ipairs(listeners) do l:update(50) end end     -- 30 s far away
        farReads = reads
        farTarget = spec.target ~= nil and spec.target.name
        nodes[camera] = {0, 2, 6}
        reads = 0
        for i = 1, 600 do for _, l in ipairs(listeners) do l:update(50) end end     -- 30 s in front of it
        nearReads = reads
        StorageMonitor.refreshStorageMonitorData = real
        -- 12 monitors in sight: 8 are drawn
        StorageMonitor.instances = {}
        for i = 1, 12 do newMonitor(false) end
        frame()
        headers = 0
        for _, s in ipairs(calls.text) do if s == "MULTIFRUIT SILO" then headers = headers + 1 end end
        -- the camera looks away: nothing is drawn
        flipped[camera] = true
        frame()
        awayTexts = #calls.text
        flipped[camera] = nil
    """)
    g = lua.globals()
    check(g.farTarget == "Multifruit Silo", "a far monitor still finds its storage (rates, alerts)")
    check(3 <= g.farReads <= 4, "far: a read every 10 s (%d in 30 s)" % g.farReads)
    check(g.nearReads >= 29, "near: a read every second (%d in 30 s)" % g.nearReads)
    check(g.headers == 8, "at most 8 monitors drawn (%d)" % g.headers)
    check(g.awayTexts == 0, "monitors behind the camera are not drawn (%d texts)" % g.awayTexts)


def test_errors_do_not_escape(lua):
    """A failing monitor's error is not hidden (ModHub: no pcall): it reaches the game's log once, and on the next
    frame that monitor is switched off, so the error does not repeat every frame and the others keep working."""
    lua.execute(WORLD)
    lua.execute("""
        m = newMonitor(false)
        other = newMonitor(false)
        local real = StorageMonitor.collectStorageCandidates
        StorageMonitor.collectStorageCandidates = function(monitor)
            if monitor == m then error("boom") end
            return real(monitor)
        end
        local function frameOnce() for _, l in ipairs(listeners) do l:update(16) l:draw() end end
        ok1, err1 = pcall(frameOnce)       -- the test catches what the game would log
        ok2 = pcall(frameOnce)
        ok3 = pcall(frameOnce)
        StorageMonitor.collectStorageCandidates = real
        otherWorking = not other.spec_storageMonitor.failed
        -- an error while drawing: the next frame puts the text state back and switches that monitor off
        local realDraw = StorageMonitor.drawStorageMonitor
        StorageMonitor.drawStorageMonitor = function(monitor, face)
            if monitor == other then error("draw boom") end
            return realDraw(monitor, face)
        end
        okDraw1 = pcall(frameOnce)
        okDraw2 = pcall(frameOnce)
        StorageMonitor.drawStorageMonitor = realDraw
    """)
    g = lua.globals()
    check(not g.ok1 and "boom" in str(g.err1), "the error reaches the game (and its log): %s" % g.err1)
    check(g.ok2 and g.ok3, "after that the listener runs again without errors")
    check(g.m.spec_storageMonitor.failed is True, "failing monitor is switched off")
    check(g.otherWorking, "the other monitor keeps working")
    check(g.StorageMonitor.farmOverride is None, "no farm override left behind")
    check(not g.okDraw1 and g.okDraw2, "a draw error reaches the game once, then the listener runs again")
    check(g.other.spec_storageMonitor.failed is True, "the monitor that failed to draw is switched off")
    check(g.StorageMonitor.drawingMonitor is None, "nothing left half drawn")
    check(sum(1 for l in g.logs.values() if "switched off" in l) == 2, "each logged once, not every frame")


def test_layout_matches_texture(lua):
    import make_textures as mt
    L = lua.globals().StorageMonitor.LAYOUT
    for key, value in mt.LAYOUT.items():
        lv = L[key]
        if isinstance(value, tuple):
            got = tuple(lv[i] for i in range(1, len(value) + 1))
            check(all(abs(a - b) < 1e-9 for a, b in zip(got, value)), "layout %s: lua %s, texture %s" % (key, got, value))
        else:
            check(abs(lv - value) < 1e-9, "layout %s" % key)


def test_static():
    src = open(os.path.join(ROOT, "scripts", "StorageMonitor.lua"), encoding="utf-8").read()
    code = re.sub(r"--[^\n]*", "", src)
    check("//" not in code, "no Lua 5.3 integer division")
    check("goto" not in code, "no goto (Lua 5.1)")
    keys = set(re.findall(r'getText\("([A-Za-z0-9_]+)"', src))
    keys |= set(re.findall(r'key = "([A-Za-z0-9_]+)"', src))
    keys |= set(re.findall(r'\bT\("([A-Za-z0-9_]+)"', src))       # local T = StorageMonitor.getText
    keys -= {"button_ok"}          # the game's own texts
    keys = {k for k in keys if not k.endswith("_")}      # prefixes of built keys ("storageMonitor_line_" .. state)
    keys |= {"storageMonitor_fullIn", "storageMonitor_emptyIn"}
    trans = {lang: open(os.path.join(ROOT, "translations", "translation_%s.xml" % lang), encoding="utf-8").read()
             for lang in ("en", "de", "fr")}
    mod = open(os.path.join(ROOT, "modDesc.xml"), encoding="utf-8").read()
    for action in re.findall(r'<action name="([A-Z_]+)"', mod):
        keys.add("input_" + action)
    for f in os.listdir(os.path.join(ROOT, "placeables")):
        keys |= set(re.findall(r"\$l10n_([A-Za-z0-9_]+)", open(os.path.join(ROOT, "placeables", f), encoding="utf-8").read()))
    for lang, t in trans.items():
        for k in keys:
            check('name="%s"' % k in t, "%s missing in %s" % (k, lang))
    test_all_languages()


# every language of the game; each file has the English keys and the same placeholders (a wrong one breaks
# string.format in the game)
LANGUAGES = "br cs ct cz da de ea en es fc fi fr hu id it jp kr nl no pl pt ro ru sv tr uk vi".split()


def test_all_languages():
    import xml.dom.minidom
    placeholder = re.compile(r"%(?:%|[-+ #0]*\d*(?:\.\d+)?[sdif])")

    def read(lang):
        dom = xml.dom.minidom.parse(os.path.join(ROOT, "translations", "translation_%s.xml" % lang))
        return [(t.getAttribute("name"), t.getAttribute("text")) for t in dom.getElementsByTagName("text")]
    en = read("en")
    for lang in LANGUAGES:
        path = os.path.join(ROOT, "translations", "translation_%s.xml" % lang)
        if not os.path.exists(path):
            check(False, "translation_%s.xml missing" % lang)
            continue
        texts_ = dict(read(lang))
        missing = [k for k, _ in en if k not in texts_]
        check(not missing, "%s: %d texts missing (%s)" % (lang, len(missing), missing[:3]))
        bad = [k for k, v in en if k in texts_ and placeholder.findall(v) != placeholder.findall(texts_[k])]
        check(not bad, "%s: placeholders differ from English in %s" % (lang, bad[:5]))
    mod = open(os.path.join(ROOT, "modDesc.xml"), encoding="utf-8").read()
    described = set(re.findall(r"<([a-z]{2})><!\[CDATA\[", mod))
    check(described >= set(LANGUAGES), "modDesc description missing for %s" % sorted(set(LANGUAGES) - described))


def main():
    test_helpers(new_runtime())
    test_snapshot(new_runtime())
    test_list_layout(new_runtime())
    test_world(new_runtime())
    test_all_products_and_paging(new_runtime())
    test_mount_size(new_runtime())
    test_mount_height_and_collisions(new_runtime())
    test_prod_needs(new_runtime())
    test_biogas_plant(new_runtime())
    test_look_and_title(new_runtime())
    test_kinds(new_runtime())
    test_rates(new_runtime())
    test_prices(new_runtime())
    test_alerts(new_runtime())
    test_more_kinds(new_runtime())
    test_farm_screens(new_runtime())
    test_history_and_settings(new_runtime())
    test_v14(new_runtime())
    test_visitor_sees_owner_farm(new_runtime())
    test_materials_never_kept(new_runtime())
    test_two_faces(new_runtime())
    test_performance(new_runtime())
    test_errors_do_not_escape(new_runtime())
    test_layout_matches_texture(new_runtime())
    test_static()
    if failures:
        print("%d FAILED" % len(failures))
        sys.exit(1)
    print("all tests passed")


if __name__ == "__main__":
    main()
