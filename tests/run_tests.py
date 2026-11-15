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
function localDirectionToWorld(n, x, y, z) return x, y, z end
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
function newMonitor(withMount)
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
        local v = values[key]
        if v == nil then return default end
        return v
    end}
    StorageMonitor.onLoad(m)
    StorageMonitor.onPostFinalizePlacement(m)
    return m
end
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
    check(names == ["Multifruit Silo", "Bakery", "Multifruit Silo B", "Grain Silo", "All silos of my farm"],
          "one entry per building, nearest first, other farm and far ones left out, farm overview last: %s" % names)

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
    check(len(list(g.menu.values())) == 6, "menu: pick, connected, size, brightness, colours, title: %s" % list(g.menu.values()))
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
    check(len(list(g.menuG.values())) == 6, "free-standing monitors have the size entry too")
    on = [g.names[c.node] for c in s2.collisions.values() if g.rigid[c.node] == "static"]
    check(on == ["collision_120"], "free-standing: only the 1.2 m collision is on: %s" % on)


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


def test_errors_do_not_escape(lua):
    """A failing monitor must never raise out of the listener: that stops the game's update (frozen player)."""
    lua.execute(WORLD)
    lua.execute("""
        m = newMonitor(false)
        local real = StorageMonitor.collectStorageCandidates
        StorageMonitor.collectStorageCandidates = function() error("boom") end
        ok1 = pcall(function() for _, l in ipairs(listeners) do l:update(16) l:draw() end end)
        ok2 = pcall(function() for _, l in ipairs(listeners) do l:update(16) l:draw() end end)
        StorageMonitor.collectStorageCandidates = real
    """)
    g = lua.globals()
    check(g.ok1 and g.ok2, "listener update/draw never raise")
    check(g.m.spec_storageMonitor.failed is True, "failing monitor is switched off")
    check(sum(1 for l in g.logs.values() if "switched off" in l) == 1, "logged once, not every frame")


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
    keys -= {"button_ok"}          # the game's own texts
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


def main():
    test_helpers(new_runtime())
    test_snapshot(new_runtime())
    test_list_layout(new_runtime())
    test_world(new_runtime())
    test_all_products_and_paging(new_runtime())
    test_mount_size(new_runtime())
    test_look_and_title(new_runtime())
    test_kinds(new_runtime())
    test_errors_do_not_escape(new_runtime())
    test_layout_matches_texture(new_runtime())
    test_static()
    if failures:
        print("%d FAILED" % len(failures))
        sys.exit(1)
    print("all tests passed")


if __name__ == "__main__":
    main()
