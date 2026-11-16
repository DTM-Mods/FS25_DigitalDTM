"""Draws what the monitor shows by running the real scripts/StorageMonitor.lua (under lupa) and painting
every renderText3D / drawDebugTriangle call onto the screen texture. Checks the layout without the game.

    python tools/render_screen.py            writes src/screens/screen_<n>.png for several product counts
"""
import os
import sys

import lupa
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import make_textures as mt  # noqa: E402

PX = 1000
FONT = mt.FONT
_fonts = {}


def font(size_px, bold):
    key = (size_px, bold)
    if key not in _fonts:
        f = ImageFont.truetype(FONT, max(6, size_px))
        try:
            f.set_variation_by_axes([700 if bold else 400])
        except Exception:
            pass
        _fonts[key] = f
    return _fonts[key]


NAMES = ["Wheat", "Barley", "Canola", "Oat", "Sorghum", "Sunflowers", "Soybeans", "Corn", "Potatoes", "Sugar Beet",
         "Cotton", "Rice", "Long Grain Rice", "Peas", "Spinach", "Green Beans", "Carrots", "Parsnips", "Red Beet",
         "Grass", "Hay", "Straw", "Silage", "Chaff", "Wood Chips", "Alfalfa", "Clover", "Forage", "Mineral Feed",
         "Pig Food", "Seeds", "Fertilizer", "Liquid Fertilizer", "Herbicide", "Lime", "Water", "Milk", "Diesel",
         "Liquid Manure", "Manure", "Digestate", "Honey", "Flour", "Sugar", "Sunflower Oil", "Canola Oil", "Butter",
         "Cheese", "Eggs", "Wool", "Grapes", "Olives", "Onions", "Poplar", "Sugarcane", "Mixed Ration", "Grass Silage",
         "Corn Cob Mix", "Oat Straw", "Barley Straw"]
INTERNAL = ["WHEAT", "BARLEY", "CANOLA", "OAT", "SORGHUM", "SUNFLOWER", "SOYBEAN", "MAIZE", "POTATO", "SUGARBEET"]


def render(count, out, theme=1, scene=None):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    ops = []
    state = {"color": (1, 1, 1, 1), "align": 0, "bold": False}

    def set_color(r, g, b, a):
        state["color"] = (r, g, b, a)

    def set_align(a):
        state["align"] = a

    def set_bold(b):
        state["bold"] = bool(b)

    def text3d(x, y, z, rx, ry, rz, size, s):
        ops.append(("text", x, y, size, s, state["color"], state["align"], state["bold"]))

    shapes = {}

    def clone(*a):
        node = len(shapes) + 100
        shapes[node] = {"visible": False}
        return node

    def set_translation(n, x, y, z):
        if n in shapes:
            shapes[n]["x"], shapes[n]["y"] = x, y

    def set_scale(n, x, y, z):
        shapes[n]["w"], shapes[n]["h"] = x, y

    def set_visibility(n, v):
        shapes[n]["visible"] = bool(v)

    def set_shader(n, name, r, g, b, a, shared):
        shapes[n]["color"] = (r, g, b)

    def width(size, s):
        f = font(int(round(size * PX / SCALE)), state["bold"])
        return f.getlength(s) / PX * SCALE

    g = lua.globals()
    g.py_color, g.py_align, g.py_bold, g.py_text, g.py_width = set_color, set_align, set_bold, text3d, width
    g.py_clone, g.py_translation, g.py_scale, g.py_visibility, g.py_shader = clone, set_translation, set_scale, set_visibility, set_shader
    lua.execute("""
        logs = {}
        function print(s) table.insert(logs, tostring(s)) end
        g_currentModName = "FS25_DigitalDTM"
        function addModEventListener(l) listener = l end
        function Class(base) return {__index = base} end
        function InitEventClass() end
        Event = {new = function(mt) return setmetatable({}, mt) end}
        RenderText = {ALIGN_LEFT = 0, ALIGN_CENTER = 1, ALIGN_RIGHT = 2, VERTICAL_ALIGN_BASELINE = 3}
        setTextColor = function(r, g, b, a) py_color(r, g, b, a) end
        setTextAlignment = function(a) py_align(a) end
        setTextBold = function(b) py_bold(b) end
        setTextVerticalAlignment = function() end
        setTextDepthTestEnabled = function() end
        renderText3D = function(...) py_text(...) end
        clone = function(...) return py_clone(...) end
        link = function() end
        getParent = function() return 1 end
        setTranslation = function(n, x, y, z) py_translation(n, x, y, z) end
        setScale = function(n, x, y, z) py_scale(n, x, y, z) end
        setVisibility = function(n, v) py_visibility(n, v) end
        setShaderParameter = function(n, name, r, g, b, a, shared) py_shader(n, name, r, g, b, a, shared) end
        getText3DWidth = function(size, s) return py_width(size, s) end
        utf8Strlen = function(s) return #s end
        utf8Substr = function(s, i, n) return string.sub(s, i + 1, i + n) end
        g_time = 1000
        g_currentMission = {environment = {currentHour = 14, currentMinute = 35}, getIsClient = function() return true end}
        g_i18n = {formatVolume = function(self, v) local s = tostring(math.floor(v)) local out = s
            while true do local r, c = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2") out = r if c == 0 then break end end
            return out .. " l" end, hasText = function() return false end}
    """)
    lua.execute(open(os.path.join(ROOT, "scripts", "StorageMonitor.lua"), encoding="utf-8").read())
    g.count = count
    g.theme = theme
    g.scene = scene
    g.names = lua.table_from(NAMES)
    g.internal = lua.table_from(INTERNAL)
    lua.execute("""
        local frame = {o = {0, 0, 0}, ex = {1, 0, 0}, ey = {0, 1, 0}, ez = {0, 0, 1}, rot = {0, 0, 0}, scale = 1.5}
        local m = setmetatable({}, {__index = StorageMonitor})
        local face = {frame = frame, barTemplate = 1, bars = {}, icons = {}}
        m.spec_storageMonitor = {faces = {face}, rowCache = {}, page = 1, pageTime = 3000, manualTime = 0, mode = 1,
                                 alerts = 2, alertList = {}, brightness = 3}
        local levels, info = {}, {}
        for i = 1, count do
            levels[i] = math.floor(400000 / (i ^ 1.15))
            info[i] = {name = internal[i] or ("MOD_TYPE_" .. i), title = names[i] or ("Product " .. i)}
        end
        local storage = {capacity = 2000000, getFillLevels = function() return levels end}
        local snap = StorageMonitor.buildSnapshot({{storage = storage}}, nil, function(i) return info[i] end)
        local spec = m.spec_storageMonitor
        spec.theme = theme
        spec.target = {name = "Multifruit Silo", title = "Multifruit Silo"}
        if scene ~= nil then           -- another kind of storage: the scene sets sceneTarget and sceneInfo
            assert(load(scene))()
            snap = StorageMonitor.buildSnapshot(sceneTarget.sources, sceneTarget.roles, function(i) return sceneInfo[i] end)
            snap.panel = StorageMonitor.buildPanel(sceneTarget)
            snap.countMode = sceneTarget.kind == "objects"
            snap.noPercent = sceneTarget.kind == "bunker"
            spec.target = sceneTarget
            if scenePost ~= nil then        -- prices, rates, alerts, money
                scenePost(snap, spec)
            end
        end
        spec.snapshot = snap
        spec.layout = StorageMonitor.computeListLayout(snap.count)
        StorageMonitor.beginBars(spec, face)
        StorageMonitor.drawStorageMonitor(m, face)
        StorageMonitor.endBars(spec, face)
    """)

    img = Image.open(os.path.join(mt.SRC, "screen_%s_full.png" % mt.THEME_ORDER[theme - 1])).convert("RGBA")
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)

    def uv(x, y):
        return (x / SCALE + 0.8) * PX, (0.5 - y / SCALE) * PX
    for sh in shapes.values():
        if sh["visible"]:
            x0, y0 = uv(sh["x"], sh["y"])
            x1, y1 = uv(sh["x"] + sh["w"], sh["y"] - sh["h"])
            glow = g.StorageMonitor.BAR_GLOW       # the game gets colour x glow; show the colour itself
            d.rectangle([x0, y0, x1, y1], fill=tuple(int(min(1, v / glow) * 255) for v in sh["color"]) + (255,))
    for op in ops:
        if op[0] == "text":
            _, x, y, size, s, c, align, bold = op
            u, v = uv(x, y)
            col = tuple(int(k * 255) for k in c[:3]) + (int(c[3] * 255),)
            anchor = {0: "ls", 1: "ms", 2: "rs"}[align]
            d.text((u, v), s, font=font(int(round(size * PX / SCALE)), bold), fill=col, anchor=anchor)
    img.alpha_composite(over)
    img.convert("RGB").save(out)
    print("wrote", out, "(%d texts, %d bars)" % (sum(1 for o in ops if o[0] == "text"), sum(1 for sh in shapes.values() if sh["visible"])))


SCALE = 1.5     # screen height in metres for the frame above (any value works)
NEW_KINDS = ("prices", "alert", "finance", "beehive")

KIND_SCENES = {
    "production": """
        ProductionPoint = {PROD_STATUS = {INACTIVE = 0, RUNNING = 1, MISSING_INPUTS = 2, NO_OUTPUT_SPACE = 3}}
        local lines = {{name = "Bread", status = 1}, {name = "Cake", status = 2}, {name = "Rolls", status = 3},
                       {name = "Baguettes", status = 1}, {name = "Pretzels", status = 0}}
        sceneInfo = {{name = "FLOUR", title = "Flour"}, {name = "SUGAR", title = "Sugar"}, {name = "EGG", title = "Eggs"},
                     {name = "BUTTER", title = "Butter"}, {name = "BREAD", title = "Bread"}, {name = "CAKE", title = "Cake"}}
        local storage = {capacity = 100000, capacities = {50000, 50000, 50000, 50000, 80000, 80000},
            getFillLevels = function() return {12500, 0, 3200, 800, 46000, 9100} end}
        sceneTarget = {name = "Bakery", title = "Bakery", kind = "production", sources = {{storage = storage}},
            roles = {"in", "in", "in", "in", "out", "out"},
            pp = {productions = lines, activeProductions = {lines[1], lines[2], lines[3], lines[4]}}}
    """,
    "husbandry": """
        sceneInfo = {{name = "MILK", title = "Milk"}, {name = "LIQUIDMANURE", title = "Slurry"}, {name = "STRAW", title = "Straw"},
                     {name = "TOTALMIXEDRATION", title = "Total Mixed Ration"}}
        local storage = {capacity = 100000, capacities = {400000, 2000000, 400000},
            getFillLevels = function() return {25000, 1670665, 195358} end}
        local barn = {}
        function barn:getNumOfAnimals() return 112 end
        function barn:getMaxNumOfAnimals() return 150 end
        function barn:getTotalFood() return 1186773 end
        function barn:getFoodCapacity() return 1200000 end
        function barn:getConditionInfos()
            return {{title = "Productivity", ratio = 0.86}, {title = "Water", ratio = 0.42}, {title = "Straw", ratio = 0.49},
                    {title = "Manure", ratio = 0.2, invertedBar = true}, {title = "Liquid manure", ratio = 0.84, invertedBar = true}}
        end
        sceneTarget = {name = "Cowshed", title = "Cowshed with feeding robot", kind = "husbandry", placeable = barn,
            sources = {{storage = storage}, {levels = {[4] = 1186773}, capacity = 1200000}}}
    """,
    "bunker": """
        BunkerSilo = {STATE_FILL = 0, STATE_CLOSED = 1, STATE_FERMENTED = 2, STATE_DRAIN = 3}
        sceneInfo = {[1] = {name = "CHAFF", title = "Chaff"}, [2] = {name = "SILAGE", title = "Silage"}}
        local b = {state = 1, fillLevel = 412000, fermentingPercent = 0.62, inputFillType = 1, outputFillType = 2}
        sceneTarget = {name = "Bunker Silo", title = "Bunker Silo North", kind = "bunker", bunkers = {b}, sources = {{bunker = b}}}
    """,
    "prices": """
        sceneInfo = {}
        local names = {{"WHEAT", "Wheat", 412000, 0.42, "Grain Elevator", 1.08}, {"CANOLA", "Canola", 168500, 0.81, "Oil Mill", 0.95},
                       {"BARLEY", "Barley", 96200, 0.37, "Grain Elevator", 1.02}, {"SOYBEAN", "Soybeans", 61800, 0.78, "Harbour", 1.12},
                       {"MAIZE", "Corn", 40250, 0.36, "Biogas Plant", 0.97}, {"SORGHUM", "Sorghum", 18400, 0.40, "Harbour", 1.0},
                       {"CHAFF", "Chaff", 2100, nil, nil, 1.0}}
        local levels, stations = {}, {}
        for i, n in ipairs(names) do
            levels[i] = n[3]
            sceneInfo[i] = {name = n[1], title = n[2]}
            if n[4] ~= nil then
                local st = stations[n[5]]
                if st == nil then
                    st = {owningPlaceable = {getName = function() return n[5] end}, isSellingPoint = true, acceptedFillTypes = {}, prices = {}}
                    st.getName = function() return n[5] end
                    function st:getEffectiveFillTypePrice(ft) return self.prices[ft] end
                    stations[n[5]] = st
                end
                st.acceptedFillTypes[i], st.prices[i] = true, n[4]
            end
        end
        local list = {}
        for _, st in pairs(stations) do table.insert(list, st) end
        g_currentMission.storageSystem = {getUnloadingStations = function() return list end}
        g_currentMission.environment.currentPeriod = 3
        g_fillTypeManager = {getFillTypeByIndex = function(self, i)
            return {economy = {factors = {1, 1, 1, names[i][6], 1, 1, 1, 1, 1, 1, 1, 1}}} end}
        local storage = {capacity = 1000000, getFillLevels = function() return levels end}
        sceneTarget = {name = "Multifruit Silo", title = "Multifruit Silo", kind = "silo", sources = {{storage = storage}}}
        function scenePost(snap)
            StorageMonitor.addPrices(snap)
            snap.prices = true
        end
    """,
    "finance": """
        sceneInfo = {}
        FinanceStats = {statNames = {"harvestIncome", "soldAnimals", "newVehiclesCost", "fuelCost", "wagePayment",
                                     "loanInterest", "productionCosts", "purchaseSeeds"}}
        local farm = {money = 1846250, loan = 300000, loanMax = 2000000, stats = {finances = {harvestIncome = 184200,
            soldAnimals = 36400, newVehiclesCost = -248000, fuelCost = -3120, wagePayment = -8650, loanInterest = -410,
            productionCosts = -1240, purchaseSeeds = -12800}}}
        g_farmManager = {getFarmById = function() return farm end}
        local titles = {harvestIncome = "Harvest income", soldAnimals = "Animal sales", newVehiclesCost = "New vehicles",
            fuelCost = "Fuel", wagePayment = "Wages", loanInterest = "Loan interest", productionCosts = "Production costs",
            purchaseSeeds = "Seeds"}
        g_i18n.hasText = function(self, k) return string.sub(k, 1, 8) == "finance_" and titles[string.sub(k, 9)] ~= nil end
        g_i18n.getText = function(self, k) return titles[string.sub(k, 9)] end
        sceneTarget = {name = "My farm's money", title = "My farm's money", kind = "finance", sources = {}}
        function scenePost(snap)
            snap.finance = true
            snap.count = #snap.panel.lines
        end
    """,
    "beehive": """
        sceneInfo = {}
        g_currentMission.beehiveSystem = {isProductionActive = true, isFxActive = true}
        local hives = {}
        for i = 1, 12 do hives[i] = {spec_beehive = {honeyPerHour = 10 / 24}} end
        sceneTarget = {name = "Beehives", title = "Beehives", kind = "beehive", sources = {}, hives = hives,
            spawners = {{spec_beehivePalletSpawner = {palletLimitReached = true}}}}
        function scenePost(snap, spec)
            spec.alertList = StorageMonitor.computeAlerts(sceneTarget, snap)
        end
    """,
    "alert": """
        sceneInfo = {}
        local names = {{"WHEAT", "Wheat", 512000, 48000}, {"CANOLA", "Canola", 238500, 6000}, {"BARLEY", "Barley", 126200, 0},
                       {"SOYBEAN", "Soybeans", 61800, -2500}, {"MAIZE", "Corn", 3250, 0}}
        local levels = {}
        for i, n in ipairs(names) do levels[i] = n[3] sceneInfo[i] = {name = n[1], title = n[2]} end
        local storage = {capacity = 1000000, getFillLevels = function() return levels end}
        sceneTarget = {name = "Multifruit Silo", title = "Multifruit Silo", kind = "silo", sources = {{storage = storage}}}
        function scenePost(snap, spec)
            snap.rate = 0
            for _, item in ipairs(snap.items) do
                for _, n in ipairs(names) do if n[2] == item.title then item.rate = n[4] snap.rate = snap.rate + n[4] end end
            end
            StorageMonitor.clock = 0
            spec.alertList = StorageMonitor.computeAlerts(sceneTarget, snap)
        end
    """,
    "objects": """
        sceneInfo = {{name = "DRYGRASS_WINDROW", title = "Hay"}, {name = "SILAGE", title = "Silage"}, {name = "STRAW", title = "Straw"},
                     {name = "COTTON", title = "Cotton"}}
        local o = {numStoredObjects = 86, capacity = 120, objectInfos = {
            {numObjects = 40, objects = {{baleAttributes = {fillType = 1, fillLevel = 4000}}}},
            {numObjects = 24, objects = {{baleAttributes = {fillType = 2, fillLevel = 4000}}}},
            {numObjects = 16, objects = {{baleAttributes = {fillType = 3, fillLevel = 4000}}}},
            {numObjects = 6, objects = {{baleAttributes = {fillType = 4, fillLevel = 22000}}}}}}
        sceneTarget = {name = "Bale Shed", title = "Bale Shed", kind = "objects", objectStorage = o, sources = {{objects = o}}}
    """,
}


def main():
    out_dir = os.path.join(ROOT, "src", "screens")
    os.makedirs(out_dir, exist_ok=True)
    if "--kinds" in sys.argv:           # production, animal pen, bunker silo, bale shed
        tiles = []
        for name, scene in KIND_SCENES.items():
            if name in NEW_KINDS:
                continue
            path = os.path.join(out_dir, "kind_%s.png" % name)
            render(0, path, 1, scene)
            tiles.append(Image.open(path))
        sheet = Image.new("RGB", (1600, 1000))
        for i, tile in enumerate(tiles):
            sheet.paste(tile.resize((800, 500), Image.LANCZOS), ((i % 2) * 800, (i // 2) * 500))
        sheet.save(os.path.join(out_dir, "kinds.png"))
        print("wrote", os.path.join(out_dir, "kinds.png"))
        return
    if "--new" in sys.argv:             # 1.2: price board, money, beehives, rates and an alert
        tiles = []
        for name in NEW_KINDS:
            path = os.path.join(out_dir, "kind_%s.png" % name)
            render(0, path, 1, KIND_SCENES[name])
            tiles.append(Image.open(path))
        sheet = Image.new("RGB", (1600, 1000))
        for i, tile in enumerate(tiles):
            sheet.paste(tile.resize((800, 500), Image.LANCZOS), ((i % 2) * 800, (i // 2) * 500))
        sheet.save(os.path.join(out_dir, "new.png"))
        print("wrote", os.path.join(out_dir, "new.png"))
        return
    if "--themes" in sys.argv:          # the same 12 products in every theme, side by side
        tiles = []
        for i, theme in enumerate(mt.THEME_ORDER, 1):
            path = os.path.join(out_dir, "theme_%s.png" % theme)
            render(12, path, i)
            tiles.append(Image.open(path))
        sheet = Image.new("RGB", (1600, 1000))
        for i, tile in enumerate(tiles):
            sheet.paste(tile.resize((800, 500), Image.LANCZOS), ((i % 2) * 800, (i // 2) * 500))
        sheet.save(os.path.join(out_dir, "themes.png"))
        print("wrote", os.path.join(out_dir, "themes.png"))
        return
    for n in (int(a) for a in sys.argv[1:]) if len(sys.argv) > 1 else (7, 16, 30, 42, 60):
        render(n, os.path.join(out_dir, "screen_%d.png" % n))


if __name__ == "__main__":
    main()
