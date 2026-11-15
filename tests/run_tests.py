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
g_currentModName = "FS25_Monitor"
g_currentModDirectory = "/mods/FS25_Monitor/"
listeners = {}
function addModEventListener(l) table.insert(listeners, l) end
function Class(base) local mt = {__index = base} return mt end
function InitEventClass() end
Event = {new = function(mt) return setmetatable({}, mt) end}
RenderText = {ALIGN_LEFT = 0, ALIGN_CENTER = 1, ALIGN_RIGHT = 2, VERTICAL_ALIGN_BASELINE = 3}
MathUtil = {vector3Length = function(x, y, z) return math.sqrt(x*x + y*y + z*z) end}

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
end
function getText3DWidth(size, text) return #text * size * 0.55 end
function drawDebugTriangle(...)
    local n = select("#", ...)
    assert(n == 14, "drawDebugTriangle takes 14 arguments, got " .. n)
    calls.tris = calls.tris + 1
end

nodes = {}
function newNode(x, y, z) table.insert(nodes, {x, y, z}) return #nodes end
function getWorldTranslation(n) local p = nodes[n] return p[1], p[2], p[3] end
function localDirectionToWorld(n, x, y, z) return x, y, z end
function getWorldRotation(n) return 0, 0, 0 end
function entityExists(n) return nodes[n] ~= nil end
function getCamera() return camera end
g_time = 0

function makeStorage(levels, capacity, capacities, x, z)
    local s = {fillLevels = levels, capacity = capacity, capacities = capacities, rootNode = newNode(x or 0, 0, z or 0)}
    function s:getFillLevels() return self.fillLevels end
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

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print("FAIL:", msg)


def new_runtime():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    src = open(os.path.join(ROOT, "scripts", "StorageMonitor.lua"), encoding="utf-8").read()
    lua.execute(src)
    src = open(os.path.join(ROOT, "scripts", "StorageMonitorOffsetEvent.lua"), encoding="utf-8").read()
    lua.execute(src)
    return lua


def test_helpers(lua):
    g = lua.globals()
    SM = g.StorageMonitor
    check(SM.groupDigits(1234567) == "1,234,567", "groupDigits")
    check(SM.groupDigits(999) == "999", "groupDigits small")
    check(SM.percent(0, 100) == 0, "percent 0")
    check(SM.percent(0.4, 100) == 1, "tiny amounts show 1 %")
    check(SM.percent(99.7, 100) == 99, "not 100 % before full")
    check(SM.percent(100, 100) == 100, "full is 100 %")
    check(SM.percent(5, 0) == 0, "no capacity")
    check(SM.colorForName("WHEAT")[1] == 0.93, "known colour")
    same = lua.eval('StorageMonitor.colorForName("SOME_MOD_TYPE") == StorageMonitor.colorForName("SOME_MOD_TYPE")')
    check(same, "unknown colour is stable")
    check(lua.eval("StorageMonitor.levelColor(50) == StorageMonitor.COLORS.ok and StorageMonitor.levelColor(80) == "
                   "StorageMonitor.COLORS.warn and StorageMonitor.levelColor(95) == StorageMonitor.COLORS.full"), "level colours")


def test_snapshot(lua):
    lua.execute("""
        for i = 1, 60 do addFillType(i, "FT" .. i, "Type " .. i) end
        addFillType(100, "WHEAT", "Wheat")
        addFillType(101, "CHAFF", "Chaff")
        -- shared 1,000,000 l silo with 60 products, as FS25_AmericanMultifruitSilos
        local levels, caps = {}, {}
        for i = 1, 60 do levels[i] = 0 caps[i] = 1000000 end
        levels[100] = 250000 caps[100] = 1000000
        levels[101] = 21 caps[101] = 1000000
        silo = makeStorage(levels, 1000000, caps)
        snap1 = StorageMonitor.buildSnapshot({{storage = silo}}, nil, function(i) return fillTypes[i] end)

        -- production: per product capacities, no shared capacity
        prod = makeStorage({[100] = 5000, [101] = 0}, nil, {[100] = 10000, [101] = 20000})
        snap2 = StorageMonitor.buildSnapshot({{storage = prod}}, {[100] = "in", [101] = "out"}, function(i) return fillTypes[i] end)

        -- silo + extension (both shared) + animal food trough
        ext = makeStorage({[100] = 100000}, 500000, {[100] = 500000})
        snap3 = StorageMonitor.buildSnapshot({{storage = silo}, {storage = ext}, {levels = {[101] = 300}, capacity = 1000}}, nil,
            function(i) return fillTypes[i] end)
    """)
    g = lua.globals()
    s1 = g.snap1
    check(s1.capacity == 1000000, "shared capacity counted once (got %s)" % s1.capacity)
    check(s1.used == 250021, "used")
    check(s1.count == 2, "only products with stock are listed (got %s)" % s1.count)
    check(s1["items"][1].title == "Wheat" and s1["items"][2].title == "Chaff", "sorted by amount")
    check(s1["items"][1].percent == 25, "item percent of the shared capacity")
    check(s1["items"][2].percent == 1, "21 l shows 1 %")

    s2 = g.snap2
    check(s2.capacity == 30000, "per product capacities add up (got %s)" % s2.capacity)
    check(s2.count == 1 and s2["items"][1].role == "in" and s2["items"][1].percent == 50, "production item")

    s3 = g.snap3
    check(s3.capacity == 1000000 + 500000 + 1000, "silo + extension + trough capacity (got %s)" % s3.capacity)
    check(s3["items"][1].level == 350000, "levels of the same product add up")
    check(s3["items"][1].capacity == 1500000, "item capacity over both silos")


def test_candidates_and_draw(lua):
    lua.execute("""
        local function station(owner, storages, field, x, z, isSellingPoint)
            local st = {owningPlaceable = owner, rootNode = newNode(x, 0, z), isSellingPoint = isSellingPoint}
            st[field] = {}
            for _, s in ipairs(storages) do st[field][s] = s end
            function st:hasFarmAccessToStorage(farmId, s) return s.farm == nil or s.farm == farmId end
            function st:getName() return "station" end
            return st
        end
        local function placeable(name, x, z)
            local p = {rootNode = newNode(x, 0, z), name = name}
            function p:getName() return self.name end
            return p
        end

        for i = 1, 10 do addFillType(i, "FT" .. i, "Type " .. i) end
        addFillType(100, "WHEAT", "Wheat")
        addFillType(101, "CHAFF", "Chaff")
        siloA = placeable("Grain Silo", 10, 0)
        siloB = placeable("Far Silo", 120, 0)
        farmSilo = placeable("Other Farm Silo", 2, 0)
        prodP = placeable("Bakery", 40, 0)
        sA = makeStorage({[100] = 600000, [101] = 1000}, 1000000, {[100] = 1000000, [101] = 1000000}, 10, 0)
        sExt = makeStorage({[100] = 100000}, 500000, {[100] = 500000}, 4, 0)      -- extension right next to the monitor
        sB = makeStorage({[100] = 5}, 100000, {[100] = 100000}, 120, 0)
        sOther = makeStorage({[100] = 7}, 100000, {[100] = 100000}, 2, 0)
        sOther.farm = 2
        sProd = makeStorage({[100] = 300, [101] = 50}, nil, {[100] = 1000, [101] = 1000}, 40, 0)

        local loading = {
            station(siloA, {sA, sExt}, "sourceStorages", 10, 0),
            station(siloB, {sB}, "sourceStorages", 120, 0),
            station(farmSilo, {sOther}, "sourceStorages", 2, 0),
        }
        local unloading = {
            station(siloA, {sA, sExt}, "targetStorages", 11, 0),
            station(nil, {}, "targetStorages", 1, 0, true),            -- selling point, no storage
        }
        g_currentMission = {
            storageSystem = {getLoadingStations = function() return loading end, getUnloadingStations = function() return unloading end},
            productionChainManager = {getProductionPointsForFarmId = function(self, farmId)
                return {{storage = sProd, owningPlaceable = prodP, inputFillTypeIds = {[101] = true}, outputFillTypeIds = {[100] = true},
                         getName = function() return "Bakery" end}}
            end},
            environment = {currentHour = 14, currentMinute = 5},
            getIsClient = function() return true end,
            activatableObjectsSystem = {addActivatable = function() end, removeActivatable = function() end},
        }
        g_localPlayer = {farmId = 1, rootNode = newNode(0, 0, 5)}
        camera = newNode(0, 2, 6)

        -- a monitor at the origin, screen facing +z
        monitor = setmetatable({rootNode = newNode(0, 0, 0), isClient = true}, {__index = StorageMonitor})
        monitor.spec_storageMonitor = {screenNode = newNode(0, 2, 0), width = 2.4, height = 1.5, drawDistance = 45,
            searchRadius = 250, offset = 0, candidateCount = 0, page = 1, pageTime = 0, dataTimer = math.huge,
            scanTimer = math.huge, rowTitles = {}}
        table.insert(StorageMonitor.instances, monitor)
        cands = monitor:collectStorageCandidates()
    """)
    g = lua.globals()
    cands = g.cands
    names = [cands[i].name for i in range(1, len(cands) + 1)]
    check(names == ["Grain Silo", "Bakery", "Far Silo"], "candidates nearest first, other farm and selling point left out: %s" % names)
    check(cands[1].distance < 5, "an extension next to the monitor makes its silo the nearest")
    check(len(cands[1].sources) == 2, "silo shows its extension too (no double storages from loading + unloading)")
    check(cands[2].roles[100] == "out" and cands[2].roles[101] == "in", "production roles")

    # frame: scan, read, draw
    lua.execute("""
        for _, l in ipairs(listeners) do if l.update then l:update(16) end end
        for _, l in ipairs(listeners) do if l.draw then l:draw() end end
    """)
    for line in g.logs.values():
        print("LUA:", line)
    spec = g.monitor.spec_storageMonitor
    check(spec.target.name == "Grain Silo", "shows the nearest")
    check(spec.snapshot.capacity == 1500000, "silo capacity with extension")
    texts = list(g.calls.text.values())
    check("GRAIN SILO" in texts, "header title drawn: %s" % texts[:3])
    check("14:05" in texts, "clock drawn")
    check("47%" in texts, "used percent drawn (701000 of 1500000): %s" % [t for t in texts if t.endswith("%")])
    check(g.calls.tris > 20, "bars drawn (%d triangles)" % g.calls.tris)
    check(list(g.calls.depth.values()) == [True, False], "text depth test switched on and back off")

    # switch storage: offset 1 -> Bakery, with IN/OUT tags
    lua.execute("""
        StorageMonitorOffsetEvent.sendEvent = function() end
        monitor:setStorageMonitorOffset(1)
        calls.text = {}
        for _, l in ipairs(listeners) do if l.update then l:update(16) end end
        for _, l in ipairs(listeners) do if l.draw then l:draw() end end
    """)
    texts = list(g.calls.text.values())
    check(spec.target.name == "Bakery", "offset 1 shows the second nearest")
    check("IN" in texts and "OUT" in texts, "production tags drawn")

    # behind the screen nothing is drawn
    lua.execute("""
        nodes[camera] = {0, 2, -6}
        calls.text = {}
        for _, l in ipairs(listeners) do if l.update then l:update(16) end end
        for _, l in ipairs(listeners) do if l.draw then l:draw() end end
    """)
    check(len(g.calls.text) == 0, "not drawn from behind")

    # paging: 10 products -> 2 pages, turns after PAGE_TIME
    lua.execute("""
        nodes[camera] = {0, 2, 6}
        local levels, caps = {}, {}
        for i = 1, 10 do levels[i] = i * 1000 caps[i] = 100000 end
        big = makeStorage(levels, 100000, caps, 1, 0)
        monitor.spec_storageMonitor.target = {name = "Big", sources = {{storage = big}}, owner = big}
        monitor.spec_storageMonitor.scanTimer = -1e9
        monitor:refreshStorageMonitorData()
        monitor.spec_storageMonitor.page = 1
        monitor.spec_storageMonitor.pageTime = 0
        for _, l in ipairs(listeners) do if l.update then l:update(StorageMonitor.PAGE_TIME + 1) end end
        calls.text = {}
        for _, l in ipairs(listeners) do if l.draw then l:draw() end end
    """)
    texts = list(g.calls.text.values())
    check(spec.page == 2, "page turned")
    check("PAGE 2/2" in texts, "page indicator: %s" % [t for t in texts if "PAGE" in t])
    check("3000 l" in texts and "10000 l" not in texts, "second page shows products 8-10")


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
    check(lua.globals().StorageMonitor.ROWS == mt.ROWS, "rows")


def test_static():
    src = open(os.path.join(ROOT, "scripts", "StorageMonitor.lua"), encoding="utf-8").read()
    code = re.sub(r"--[^\n]*", "", src)
    check("//" not in code, "no Lua 5.3 integer division")
    check("goto" not in code, "no goto (Lua 5.1)")
    # every l10n key used in Lua exists in en and de
    keys = set(re.findall(r'getText\("([A-Za-z0-9_]+)"', src))
    for lang in ("en", "de"):
        t = open(os.path.join(ROOT, "translations", "translation_%s.xml" % lang), encoding="utf-8").read()
        for k in keys:
            check('name="%s"' % k in t, "%s missing in %s" % (k, lang))
    # every shop text exists
    for f in os.listdir(os.path.join(ROOT, "placeables")):
        x = open(os.path.join(ROOT, "placeables", f), encoding="utf-8").read()
        for k in re.findall(r"\$l10n_([A-Za-z0-9_]+)", x):
            for lang in ("en", "de"):
                t = open(os.path.join(ROOT, "translations", "translation_%s.xml" % lang), encoding="utf-8").read()
                check('name="%s"' % k in t, "%s (%s) missing in %s" % (k, f, lang))


def main():
    test_helpers(new_runtime())
    test_snapshot(new_runtime())
    test_candidates_and_draw(new_runtime())
    test_layout_matches_texture(new_runtime())
    test_static()
    if failures:
        print("%d FAILED" % len(failures))
        sys.exit(1)
    print("all tests passed")


if __name__ == "__main__":
    main()
