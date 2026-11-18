# Blank sea level design

The playable sea is `res://scenes/sea_area.tscn`, instanced inside the
original World. Play from `res://scenes/main.tscn`. There is one Player,
one camera, and no extra gameplay scene. The existing island, Fish Co
introduction, dock and water shaders remain intact.

```text
Sea
├── EditorGuide         editor-only outline/grid and Map Size
├── BackgroundSprites   empty container for individual PNG sprites
├── Solids              the ONLY TileMapLayer; completely empty
├── Details             empty container for individual PNG sprites
├── ForegroundSprites   empty container for individual PNG sprites
└── Points
    ├── Entry           start of the dive
    └── SurfaceExit     swim near here, press E or Space to return
```

There are no fish, NPCs, nets, combat managers, placeholder rocks or
seafloor decorations in the sea. Their standalone scripts/resources remain
in the repo for future work but are not instantiated.

## Paint walls

1. Open `scenes/sea_area.tscn`. Select **Sea → Solids**.
2. Paint wall tiles from `resources/tilesets/sea_solids.tres`.
3. These 16×16 tiles all have solid collision polygons on **physics layer 2**.
   The original `Player` CharacterBody2D uses that layer while swimming,
   so painted walls should stop Penni via `move_and_slide()`.
4. The sea-only TileSet shares visual tiles with the island but **not**
   collision resources: editing wall collisions won't affect land.
5. Keep the entry and surface markers clear of walls.

Use separate PNG Sprite2D children in BackgroundSprites, Details and
ForegroundSprites for decorations. The existing World water shader and
underwater tint handle the water; no water tiles are needed. The editor-only
guide has **Map Size**, **Grid Size**, and **Show Grid** properties. Default
sea footprint is 920×530.

To playtest: run `scenes/main.tscn`, finish the Fish Co intro, use the
dock, swim with WASD/arrows, paint a wall to test collision, and return
near SurfaceExit with E/Space.
