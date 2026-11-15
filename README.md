<p align="center">
  <a href="https://github.com/DTM-Mods"><img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/dtm-header.jpg" alt="DTM Mods by PropaineX & Fennell" width="100%"></a>
</p>

<p align="center">
  <img src="src/icon_storageMonitor.png" alt="Storage Monitor icon" width="128">
</p>

<h1 align="center">Digital DTM</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Farming%20Simulator-25-2E6B4F" alt="Farming Simulator 25">
  <img src="https://img.shields.io/badge/multiplayer-supported-2E6B4F" alt="Multiplayer supported">
  <a href="https://github.com/DTM-Mods"><img src="https://img.shields.io/badge/DTM-Mods-143326" alt="DTM Mods"></a>
</p>

<p align="center">
  <b>A live colour screen next to your silo: how full it is, what's in it and how much room is left, at a glance.</b>
</p>

<p align="center">
  <img src="src/textures/monitor_preview.png" alt="The screen of a multifruit silo: 81 % full, used, free and total capacity, and every product with its amount" width="100%">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/features.jpg" alt="Features" width="100%">
</p>

Put a monitor at a silo, production, animal pen, bunker silo or bale / pallet shed and it shows what is in it, live:

- **How full:** the percent in big numbers, green, then amber from 75 % and red from 90 %.
- **Used, free and total capacity**, and one bar across the screen with every product in its own colour.
- **Every product at once** with its amount, a fill bar and its percent. The list adds columns (up to 3) and shrinks
  its text until everything fits, up to 42 products. Only beyond that it pages: by itself, or with Page Up / Page Down in
  front of the screen.
- **Real product icons:** every product with the game's own icon, in its colour.
- **Productions:** which lines run, which miss inputs or have a full output store; inputs (IN) and outputs (OUT),
  empty inputs in red.
- **Animal pens:** animals (e.g. 112/150), food, water, straw, productivity and the tanks, as the game's animal page.
- **Bunker silos:** filling, fermenting in percent, or ready; several bunkers side by side.
- **Bale and pallet sheds:** stored of capacity, and every product with its number of bales or pallets.
- **All silos of my farm:** one screen with the whole farm's silo stock (pick it in the settings).
- **Shared capacity done right:** silos that share one capacity across all products count it once, not once per
  product.
- **The in-game time** in the corner.
- **Pick the silo** from a list of everything nearby, or let it show the nearest.
- **Any size:** 0.8 to 6 m wide, on every model.
- **Readable at night:** the screen glows; five brightness levels.
- **Four colour themes:** night blue, DTM green, amber terminal and daylight.
- **Your own title** on the screen.
- **Four models** in the shop under Buildings > Tools, free-standing or mounted on a silo:

| Model | Screen | Price | Read from |
|---|---|---|---|
| Kiosk | 1.2 m on a pedestal | 3,500 | 30 m |
| Wall | 2.4 m on two posts | 6,500 | 50 m |
| Billboard | 4 m on tall posts | 12,000 | 90 m, from the tractor |
| Silo Mount | 2.4 m on a bracket against the silo | 6,000 | 50 m |

The sizes are what you buy; every model can then be set from 0.8 to 6 m wide, and it is read from further away when
bigger.

<p align="center">
  <img src="src/store/store_kiosk.png" alt="Kiosk" width="32%">
  <img src="src/store/store_wall.png" alt="Wall" width="32%">
  <img src="src/store/store_billboard.png" alt="Billboard" width="32%">
</p>

<p align="center">
  <img src="src/screens/themes.png" alt="The four colour themes" width="100%">
</p>

<p align="center">
  <img src="src/screens/kinds.png" alt="A production, an animal pen, a bunker silo and a bale shed" width="100%">
</p>

<p align="center">
  <img src="src/screens/screen_30.png" alt="30 products on one screen, in three columns" width="100%">
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/how-to-use.jpg" alt="How to use" width="100%">
</p>

1. Buy a monitor (Buildings > Tools) and place it at the storage you want to watch. Silo mounts go right against the
   silo wall: the back of the bracket touches it.
2. It shows the nearest storage within 40 m by itself, each building on its own: a silo, each silo extension, your
   farm's productions, animal pens, bunker silos and bale / pallet sheds.
3. Stand in front of the screen and press the activate key (**Monitor settings**):
   - **Pick the storage**: a list of every storage nearby, nearest first, or "Always the nearest". A picked silo stays
     picked when something nearer is built.
   - **Also show the silos connected to it**: a silo together with its extensions, as the game counts them when you
     load or unload.
   - **Screen size**: 0.8 to 6 m wide. A Silo Mount keeps its bottom edge 2 m above the ground and grows upwards;
     the others grow from the ground, posts and all.
   - **Brightness**: very dim to very bright (screen glow, bars and text).
   - **Colours**: night blue, DTM green, amber terminal, daylight.
   - **Title**: type your own, or leave it empty for the storage's name.
4. More than 42 products: **Page Up / Page Down** in front of the screen (rebindable under Controls). The pages stay
   where you put them for 30 seconds.

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/multiplayer.jpg" alt="Multiplayer" width="100%">
</p>

- The settings (storage, connected silos, size, brightness, colours, title) are synced: everyone on the server sees the same, and they are saved
  with the game. Paging is each player's own.
- In silos that keep one stock per farm, every player sees their own farm's stock.
- The screen is drawn by each player's game. A dedicated server draws nothing, so it costs the server nothing.

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/installation.jpg" alt="Installation" width="100%">
</p>

Put `FS25_DigitalDTM.zip` in `Documents/My Games/FarmingSimulator2025/mods`. In multiplayer, install it on the server and
on every player's game.

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/known-issues.jpg" alt="Known issues" width="100%">
</p>

- The screen only shows while you look at its front and are within its reading distance (see the table above).
- No storage within 40 m: the screen says "No storage nearby".
- Every model has a collision for each screen size; the game switches on the one that fits, so a monitor can be
  selected (to sell it) at any size.

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/for-developers.jpg" alt="For developers" width="100%">
</p>

How it works:

- **The screen:** the glass uses the game's `glowShader` (`staticLight`) with a baked panel texture per theme
  (`textures/screen_<theme>.dds`, swapped with `setMaterialDiffuseMapFromFile`); `lightControl` is the brightness.
  Text is drawn each frame with `renderText3D`. Bars are copies of a hidden 1 x 1 m glowing rectangle (`barTemplate`)
  placed, sized and coloured (`emitColor`) by the script; product icons are copies of `iconTemplate` with the fill type's
  HUD image as texture. The game does not draw `drawDebugTriangle` in normal play, and two bars at the same depth
  flicker, so bars never overlap.
- **The storage:** one entry per building (`spec_silo.storages`, `spec_siloExtension.storage`,
  `spec_husbandry.storage`, production storages, other mods' storages through their stations), the nearest within
  40 m or the picked one (remembered by the building's position). "Connected" adds every storage sharing a loading or
  unloading station. Silos with a shared capacity (`Storage.capacity`) count it once; other storages add up their
  per-product capacities.
- **The list:** `StorageMonitor.computeListLayout` picks 1 to 3 columns and the text size so everything fits.
  `python tools/render_screen.py` runs the real Lua and paints what it draws into `src/screens/`.
- **Settings:** the game's `OptionDialog`; `StorageMonitorSettingsEvent` syncs them; they are saved in the savegame.

Everything is made from scripts:

```
python tools/make_textures.py                       screen texture (+ preview with sample data)
blender --background --factory-startup --python tools/build_model.py      models, i3d export, shop renders
python tools/make_icon.py                           mod icon (with the DTM pin) and modhub/icon_512.png
python tools/gen_placeables.py                      placeable XMLs from the i3d, shop images and icon to .dds
python tools/build_mod.py                           checks, tests, build/FS25_DigitalDTM.zip
```

Needs Blender 5.2 with the GIANTS I3D exporter, GIANTS Editor 10.0.14 (`textureTool.exe`), Python with Pillow and
[lupa](https://pypi.org/project/lupa/). `python tests/run_tests.py` runs the Lua offline on Lua 5.1 stubs of the engine.
The PNG masters in `src/` stay out of the zip (`.modignore`).

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/patch-notes.jpg" alt="Patch notes" width="100%">
</p>

### 1.1.0.0

- Real product icons, four colour themes, five brightness levels, a glowing screen readable at night, your own title.
- Every model can be resized (0.8 to 6 m wide); a collision for every size, so monitors can be selected and sold at
  any size (the Silo Mount could not be selected before).
- New kinds of storage: productions (lines running, missing inputs, output full), animal pens (animals, food, water,
  straw, productivity), bunker silos (filling, fermenting, ready), bale and pallet sheds, and all silos of the farm.
- Shop picture of the Silo Mount on a silo wall.

### 1.0.0.1

- Fixed: productions and animal pens with a capacity per product (fermenting silos, cow barns) showed far over 100 %.

### 1.0.0.0

- First version: live storage screen in four models (Kiosk, Wall, Billboard, Silo Mount with a size setting), every product on one screen (up to 42, then pages with Page Up / Page Down), nearest storage within 40 m or a picked one, connected silos on request, adjustable screen size for the Silo Mount, settings synced in multiplayer and saved, English, German and French.

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/license.jpg" alt="License" width="100%">
</p>

MIT, see [LICENSE.txt](LICENSE.txt).

---

<p align="center">
  <a href="https://github.com/DTM-Mods"><img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/dtm-intro.gif" alt="DTM Mods by PropaineX & Fennell" width="420"></a><br>
  <sub>Part of <a href="https://github.com/DTM-Mods">DTM Mods</a> (Designed To Manage) by PropaineX & Fennell</sub>
</p>
