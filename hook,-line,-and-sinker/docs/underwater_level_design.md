# Designing the underwater level in Godot

The entry point for the game is still `res://scenes/main.tscn`. The dock calls
`DiveEntry.request_dive()` and reveals the underwater level inside
`res://scenes/diving_prototype.tscn`. To work on the ocean, **open
`diving_prototype.tscn` in the editor**, not `main.tscn`.

## Current scene hierarchy

```text
DivingPrototype                 (full-screen host UI)
├─ SubViewportContainer         (stretches pixel art 6×)
│  └─ SubViewport               (320×180 pixels)
│     └─ Lagoon                 (920×530 world, diving_world.gd)
│        ├─ EditorGuide         (editor-only footprint + grid)
│        ├─ LevelArt            (your background decoration)
│        │  └─ Terrain          (empty TileMapLayer; assign a TileSet)
│        ├─ Points              (move these to place story locations)
│        │  ├─ Entry            (where Penni enters the lagoon)
│        │  ├─ SurfaceExit      (where pressing E returns to shore)
│        │  ├─ SilasBurrow      (Silas's home / initial talk position)
│        │  ├─ TangledNet       (decorative snag in Silas's rescue scene)
│        │  └─ ShellGarden      (Silas's companion discovery)
│        ├─ FishSpawns          (editable wild-fish placement)
│        │  ├─ MulletNearSurface
│        │  ├─ PorgyByReef
│        │  ├─ GobySeafloor
│        │  ├─ MulletMiddle
│        │  ├─ FlounderDeep
│        │  ├─ NeedlefishOpenWater
│        │  ├─ PorgyFarReef
│        │  └─ TunaDeepEast
│        ├─ ForegroundArt       (coral / scenery in front of actors)
│        ├─ Combat             (reel and parry rules)
│        ├─ NetProjectile      (directional net cast and collisions)
│        ├─ Camera2D           (follows Penni)
│        ├─ Player             (underwater Penni)
│        └─ Silas              (fish sprite, follows after quest)
├─ Music
└─ HUD                        (crisp screen-space labels & combat UI)
```

## How to lay out a level

1. In the Scene dock, open `scenes/diving_prototype.tscn` and expand
   `SubViewportContainer → SubViewport → Lagoon`.
2. **Move the points** under `Points`. All story interaction distances, Silas's
   idle location, and the glowing-garden reaction follow those markers now.
   Keep `Entry` near `SurfaceExit` so diving in and leaving feel connected.
3. **Move the fish spawn markers** under `FishSpawns`. Each marker previews a
   fish in the editor. Duplicate a marker to add another fish, delete it to
   remove that spawn, or choose a different `FishData` in the Inspector's
   `Species` property. Set its `Random Seed` for repeatable initial behavior.
   The live fish actor is spawned at that location at runtime and then
   wanders near its home. Caught fish disappear for the current play session.
4. Put art behind actors in `LevelArt`. You can add `Sprite2D` children and
   position them directly, or select `LevelArt/Terrain`, create/assign a
   `TileSet` in the Inspector, and paint a `TileMapLayer`.
5. Put large coral, seaweed or cave overlays **in front** of the characters under
   `ForegroundArt`. This layer draws above the player.
6. In `Lagoon`'s Inspector, disable `Show Prototype Environment` after you
   start painting. This hides the original procedural sand, rays, reefs and
   grass, but keeps the basic ocean color and temporary story-location
   indicators.
7. Run `main.tscn` for the full jump/iris/world flow, or launch
   `diving_prototype.tscn` directly for quick underwater-only iteration.

## Size, camera and movement

- **World canvas**: 920×530 Godot world pixels. In the editor, the
  `EditorGuide` outlines this space with a 32-pixel grid (editor-only).
- **Visible camera**: 320×180 game pixels, shown 6× larger on a standard
  1920×1080 display. Penni's camera follows her through the world.
- **Current swimming bounds** are a rectangular clamp defined by `SEA_BOUNDS`
  in `diving_world.gd` (`Rect2(16, 30, 888, 460)`). The camera limits
  are in `_set_camera_bounds()` and `Camera2D` in the scene.
- **Important limitation:** The character is currently a `Sprite2D` moved
  directly by code, **not** a `CharacterBody2D`. Painting solid-looking
  rocks does not block swimming yet. Wild fish also wander inside a
  rectangular zone, not along a pathfinding grid. Before making maze-like
  caves or narrow tunnels, we should add collision shapes and collision-aware
  movement.

## Design suggestions for the first playable underwater area

This is a recommendation, not an existing game requirement.

Start with a small guided loop inside the larger lagoon:
- **Safe entrance near the left**, where players practice movement and casting
  on a slow fish.
- **Silas's burrow in the middle**, visible from the main path; he calls for help and becomes an immobile net target after you speak to him. Players must get within net casting range, land the projectile, and win the reel-and-parry fight to pull him free. Only then does he start following. Keep space clear on one side of his burrow for casting.
- **A more open fishing space to the right**, with faster species for parry
  practice, plus a reason for Silas to use his concealment ability.
- **The shell garden just beyond that**, so following Silas naturally rewards
  exploration.
- **A clear route back to the entry**, where the story offers the surface
  invitation.

When you start actual level art, plan negative space around fish so the
110-world-pixel directional net can travel and the parry circle remains visible.
Keep the important story markers away from crowded fish spawn locations.

## What has been removed

On the `diving` branch, the original island's bait box and bobber shelf, their
menus, and the bait/extra-casts trades are no longer part of playable diving.
Original bait and bobber scripts/resources are retained as **inactive legacy
content** because the old fishing controller and debug scripts still reference
them. The current net/projectile combat does not read equipped bait or bobbers;
upgrades like reel strength and reinforced line still apply.

## Tests

```bash
godot --headless --path . -s res://tests/diving_prototype_test.gd
godot --headless --path . -s res://tests/diving_island_transition_test.gd
```

These scripts are included but were not executed here (Godot is unavailable).
