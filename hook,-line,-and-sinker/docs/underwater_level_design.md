# Underwater level design — Godot editing workflow

Open **`res://prefabs/world.tscn`** to see all of Penni's explorable world, including the island, dock, and ocean. The lagoon is an instanced **`res://scenes/lagoon_area.tscn`** so you can edit underwater scenery separately while it remains in exactly the same World scene during gameplay. The game starts from `scenes/main.tscn`, with one viewport, one Penni, and one camera.

**One tilemap for collidable walls. All other scenery is independent PNG sprites.** The existing procedural water background stays in `DivingWorld` for now and can be replaced by a shader; there's no water-tile painting layer.

## World and lagoon hierarchy

```text
Main (UI, dialogue, Fish Co opening)
├─ SubViewportContainer / SubViewport
│  └─ World
│     ├─ Player / Camera2D            the original Penni and one camera
│     ├─ Ground / GroundFront         existing beach TileMapLayers
│     ├─ Dock / Shop / Housing        unchanged land systems
│     ├─ Water                        existing reflection shader (surface Y=140)
│     └─ Lagoon                       instanced lagoon_area.tscn, always in World
│        ├─ EditorGuide               underwater map size + editor grid
│        ├─ LevelArt
│        │  ├─ BackgroundSprites      standalone PNGs behind actors
│        │  ├─ Solids                 one wall TileMapLayer
│        │  └─ Details                standalone decorative PNGs
│        ├─ Points                    entry, surface, Silas burrow, garden
│        ├─ FishSpawns                editable species spawn markers
│        ├─ ForegroundArt             standalone sprites in front of Penni
│        ├─ Combat / CompanionBattle  Jerry's fishing systems
│        ├─ NetProjectile
│        └─ Silas
└─ DivingHUD                           shown while underwater, not a new viewport
```

The lagoon remains loaded between dives. Penni jumps off the dock and swims downward through the real waterline; no black iris or second player is used for ordinary diving. Near Y=140 the camera can show sky above and water below. The existing reflection fades as Penni moves deeper while a blue underwater tint strengthens. The radial iris remains for the initial Fish Co call.

## Using PNGs for background and details

1. Add your individual **PNG** files to `res://sprites/environment/` in Godot.
2. Open `scenes/lagoon_area.tscn` directly, or expand the Lagoon instance in `prefabs/world.tscn`, and select `LevelArt`.
3. Drag a PNG from the **FileSystem** panel into the 2D viewport while **BackgroundSprites** or **Details** is selected, so Godot creates a Sprite2D there. You can also add a Sprite2D manually and assign its **Texture**.
4. Move, duplicate, resize or rotate each sprite directly in the scene editor. There's **no tileset requirement** or fixed grid for these decorations.
5. Put anything that needs to draw **in front of Penni and the fish** under `Lagoon/ForegroundArt`. It is already configured at a higher Z index.

Use **BackgroundSprites** for distant reef art, silhouettes and large environmental PNGs; **Details** for coral, plants, sand patches, props and shells; **ForegroundArt** for overhangs and other objects the player passes behind. Small reusable props can be saved as `PackedScene`s if that becomes useful, but plain Sprite2D instances are enough to begin.

The World now already uses the existing **water reflection shader** and an **underwater blue tint shader**. The lagoon's old procedural prototype scenery is disabled in its new World instance. No water TileMapLayer is needed.

## Using the wall tileset

The only underwater TileMapLayer is `World/Lagoon/LevelArt/Solids`; its resource is **`res://resources/tilesets/world_tiles.tres`**, which reuses the island's existing beach tile graphics on a different layer, set to **16 × 16-pixel tiles**. The grid applies only to solid walls, not your background PNGs.

1. Export a PNG atlas containing the stone/reef/cave-wall **tiles** and import it under `res://sprites/environment/`.
2. Select `Lagoon → LevelArt → Solids` and open its **Tile Set** resource in the Inspector. In the bottom TileSet editor, add an **Atlas Source** referencing the PNG and generate its 16×16 atlas cells.
3. In the TileSet editor, use **Paint → Physics Layer 0** to draw the collision polygon on every tile that should block the player.
4. Switch to the TileMap painting tools and paint those wall tiles onto **Solids**.

The TileSet physics is configured on **2D physics layer 2**. Penni's original **CharacterBody2D** now has a swimming state that collides with solid wall polygons, and the existing net projectile raycasts against the same physics layer. **Because World and Lagoon share the TileSet resource, changing a tile's collision polygon also affects that tile wherever it is used on the island.** If the same art needs different collision on land and underwater, we'll separate just the physics resources rather than duplicating artwork. Fish and Silas still move directly and do **not** pathfind around the walls yet.

If you want a rock to look solid but **not** block Penni, use a standalone Sprite2D in **Details** or **BackgroundSprites**, rather than painting it in Solids.

## Editing the level layout

The existing `Points` markers control the story locations; move them in the editor without changing any dialogue code. `FishSpawns` uses `DivingFishSpawn` markers with **Species (FishData)** and **Random Seed** properties. Duplicate a marker for more fish, delete it for fewer, or move it to change their spawn points.

For the first-day playtest, put a relatively approachable fish near `Entry`, make Silas's `SilasBurrow` easy to discover, allow a clear line for the net rescue, and place more difficult fish farther into the level. Avoid enclosing any fish in narrow corridors until their pathfinding is addressed.

The native camera remains **320 × 180 world pixels** and belongs to **World/Player**. To expand the ocean, change **Lagoon → EditorGuide → Map Size** (currently **920 × 530**). That value controls underwater swimming bounds and the camera limits during a dive. The guide's grid is a **visual editor aid only**; changing it does not constrain where you place PNG sprites.

## Quick validation

- Open `world.tscn` to see the whole map and `lagoon_area.tscn` to edit the lagoon. Verify that **Solids is the only underwater TileMapLayer**.
- Place one standalone Sprite2D behind Penni, one under Details, and one in ForegroundArt; confirm their draw order.
- Paint one rock tile with a collision polygon onto Solids; Penni should stop or slide along it.
- Throw the net toward that solid tile; the net should stop before it hits a fish behind the rock.
- Move one fish spawn and one story marker, then check their new positions during play.
- Play `main.tscn` to verify the intro, quota, dock, continuous jump, the view of sky near the surface, reflection fade and the same Player returning to land.

Scene-layout regression checks are in `tests/lagoon_level_layout_test.gd`. Godot isn't installed in the GitHub editing environment, so runtime validation still needs an editor playtest.
