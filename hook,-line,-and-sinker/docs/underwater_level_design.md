# Underwater level design — Godot editing workflow

The current authoring scene is **`res://scenes/diving_prototype.tscn`**. The actual game still opens `res://scenes/main.tscn` and enters that same lagoon through the existing dock and iris. The level is authored with built-in Godot `TileMapLayer`s and scene markers; **do not make a second level manager or hardcode fish locations in `diving_world.gd`**.

## Scene organization

```text
DivingPrototype
└─ SubViewportContainer / SubViewport (320 × 180 game pixels)
   └─ Lagoon (DivingWorld)
      ├─ EditorGuide                 editor outline; MAP SIZE goes here
      ├─ LevelArt
      │  ├─ Water                   backgrounds, water tones and patterns
      │  ├─ Terrain                 sand, seabed, cliffs and reefs (visual)
      │  ├─ Details                 coral, plants, shell decorations (visual)
      │  └─ Solids                  walls and rocks that stop Penni / net
      ├─ Points                     designer-placeable story locations
      │  ├─ Entry
      │  ├─ SurfaceExit
      │  ├─ SilasBurrow
      │  ├─ TangledNet
      │  └─ ShellGarden
      ├─ FishSpawns                 edit / duplicate / delete species spawns
      ├─ ForegroundArt
      │  └─ Overhangs               anything that renders IN FRONT of Penni
      ├─ Combat / CompanionBattle   Jerry's existing mechanics
      ├─ NetProjectile              line/net system
      ├─ Camera2D
      ├─ Player / WallCast          existing Penni sprite and wall collision
      └─ Silas                      existing story companion
```

No need to modify any of the combat or dialogue systems when painting the map.

## Set up your water tileset

1. Export your underwater tile art as a **PNG**, using a **16 × 16 pixel grid**. For example, 32 × 32 tiles can be used if we change the tile size in the shared resource first; tell us before making dozens of painted cells.
2. Put the image under `res://sprites/environment/` in the Godot FileSystem dock.
3. Open `diving_prototype.tscn`. Select `Lagoon/LevelArt/Water`. In the Inspector, open its **Tile Set** resource, which is already linked to `res://resources/tilesets/lagoon_tiles.tres`.
4. At the bottom TileSet editor, add an **Atlas Source**, choose your PNG, and let Godot generate the 16 × 16 tiles. Edit atlas separation/margins if your spritesheet has gutters.
5. Select one of the five paintable layers and paint tiles onto the **2D** canvas using the same TileSet palette. You can switch between Water, Terrain, Details, Solids and ForegroundArt/Overhangs without recreating the atlas.

Every layer uses the **same** TileSet resource. Do not duplicate it just to put a tile in the foreground. You can add several atlas PNGs to the same resource (water, reef, plants, walls).

| Paint layer | Purpose | Collides? |
| --- | --- | --- |
| `LevelArt/Water` | Base color, light patterns, deep-water motifs | No |
| `LevelArt/Terrain` | Seafloor and structural tiles | No |
| `LevelArt/Details` | Plants, coral, small objects | No |
| `LevelArt/Solids` | Impassable stones, cave walls, cliffs | **Yes**, once collision shapes are painted |
| `ForegroundArt/Overhangs` | Tall seaweed and rock arches in front of the diver | No |

### Making a tile solid

The shared TileSet already has a **Physics Layer** configured on 2D physics **layer 2**. Select the TileSet's **Paint → Physics Layer 0** tools, select the rock/wall tiles, and draw their collision polygons. Then paint those tiles on `LevelArt/Solids`.

Penni's existing sprite has a **7-pixel circular ShapeCast2D** attached. It uses Godot's physics to stop against the polygons, with sliding along the wall on diagonal movement. Net throws also stop at these walls, rather than catching fish through the rock. No new physics manager was created.

Only `Solids` has TileMapLayer collision enabled. Thus you can use the same rock art on `Terrain` as scenery without physically blocking the player. A tile has to be painted in `Solids` **and** have a collision polygon to block movement.

For now, **wild fish and Silas still use their preexisting direct movement**, so they do not automatically path around painted obstacles. Avoid sealing fish in narrow mazes until companion and fish navigation is updated. Net casts and the player already respect solid tiles.

## Arrange the story and fish

These are preexisting marker systems, not new scripts:

- **`Points/Entry`** — Penni's spawn; place this near **`Points/SurfaceExit`** so leaving is obvious.
- **`Points/SilasBurrow`** — where Silas calls for help; keep at least 100px of clear water to throw and reel the net.
- **`Points/TangledNet`** — visual net/knot location.
- **`Points/ShellGarden`** — reward for exploring with Silas.
- **`FishSpawns/*`** — each `DivingFishSpawn` has a `Species` (`FishData`) and `Random Seed` in the Inspector. Duplicate a marker for more fish or move it to change the initial fish position; its artwork is previewed in the editor. Fish wander around the marker at runtime.

**First-day layout idea:** Start in a safe left-hand entry area with a weak fish, travel east toward Silas's voice, create a clear pocket of water around the net rescue, then leave an open combat area to the right for stronger species. Keep the surface-return path readable and leave enough room for the net's 110-pixel reach.

## Map size and camera

- The editor reference is **`Lagoon/EditorGuide → Map Size`** (currently **920 × 530 world pixels**). This property now drives the playable rectangle, camera edges, fish spawning bounds and the outline grid. Changing it does not move any of the story markers or tiles for you.
- **Grid Size** defaults to **16 pixels**, matching the TileSet. Both properties can be edited in the Inspector.
- Visible native pixel camera remains **320 × 180**, scaled for the game window. Do not change the viewport size just to expand the level: change the editor guide's Map Size instead.
- Keep enough margins around the map edges so Penni's 7px collision circle does not start outside a wall.

## Replacing the temporary backdrop

At first, the original procedural underwater background, reefs, sand and light rays remain visible so the scene still looks like water before artwork exists. Once your tiles look right, select **Lagoon** and uncheck **Show Prototype Environment**. The safe-water background color, surface/Silas story cues and combat effects remain until we replace those separately.

## Quick playtest checklist

1. Open `diving_prototype.tscn` directly to check painted layers and the camera.
2. Run `main.tscn` to exercise the Fish Co introduction, quota, phone call and dock confirmation before diving.
3. Swim toward a solid tile with a collision polygon. Penni should stop or slide along it, while a tile on Terrain should not block her.
4. Throw the net into a wall. It should retract, not grab a fish behind the wall.
5. Move one fish spawn or story marker in the editor and confirm it changes the runtime placement without editing scripts.
6. Check that SurfaceExit and Silas's rescue remain reachable and that the new foreground tiles draw in front of Penni.

A static scene-structure regression is in `tests/lagoon_level_layout_test.gd`. Full swimming/collision playtesting still needs the Godot editor (not installed in the GitHub editing environment).
