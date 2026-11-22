# World camera and real intro boat

## Camera

The single camera now lives at **World → CameraController → Camera2D** in
`prefabs/world.tscn`, not under Penni. The same camera owns **UnderwaterTint**
and **SeaTutorialCue**. Its script is `scripts/world_camera_controller.gd`.

Select **CameraController** in the Inspector:

- **Follow Speed**: exponential easing toward Penni's world position.
- **Offset Speed**: easing between land and underwater camera offsets.
- **Teleport Snap Distance**: snap across long story/date teleports instead of drifting across the map.
- **Land Offset**: default `(0, -22)`.
- **Underwater Offset**: default `(0, 0)`.

Penni's sprite tilt changes only her `AnimatedSprite2D` rotation and never
rotates or directly moves the camera. Jump/path geometry remains under
`Sea → Points`, including the artist's updated `PenniDiveJump` path.

For cutscenes, the camera provides:

```gdscript
camera.pan_to(marker.global_position, 0.8)
camera.return_to_player(0.8)
camera.snap_to(marker.global_position)
camera.snap_to_player()
```

The camera **does not** control the player's input. The existing
`IslandStoryDirector` exposes:

```gdscript
await story_director.play_camera_pan(marker, 0.8, 0.5, 0.8)
```

The story director locks Penni's controls, pans to the marker, optionally
holds, pans back, and restores the previous control state. Story data or
future story scripts can invoke this at an authored event. Diving and
blackout transitions use the camera's snap and mode APIs, not camera
properties on Player.

## Intro boat

**World → IntroBoat** is east of the current playable beach at `(2250, 124)`,
still within the original World's existing Water rectangle. The existing
`WorldDayNight` sky and water shaders are used as-is; nothing is copied or
recreated for the opening.

- **IntroBoat → Sprite**: `AnimatedSprite2D`, driven by
  `scripts/intro/intro_boat_sprite.gd` and the artist's
  `sprites/environment/boat.png` strip.
- **IntroBoat → PlayerSpot**: where Penni stands during the opening phone call.
- **IntroBoat → CameraFocus**: screen center for the opening.
- To edit the boat animation, change **Columns**, **Rows**, **Frame Count**,
  and **Frames Per Second** on its Sprite Inspector. Defaults assume four
  frames across a horizontal strip; adjust to the imported art's actual grid.

`FishCoOpeningSequence` still starts the **same** Fish Co conversation through
`DialogueManager`. Its previous `FishCoIntro` painted backdrop remains a
dormant compatibility node, never displayed. `SeaDiveTransition` still uses
the existing iris to move Penni to the dock; it then restores world-camera
following and regular draw order. No new playable boat scene, level load,
or additional player was created.

## Checking

Run these regressions from the Godot project directory:

```sh
godot --headless --path . -s res://tests/world_camera_intro_test.gd
godot --headless --path . -s res://tests/diving_island_transition_test.gd
godot --headless --path . res://tests/diving_party_test.tscn
godot --headless --path . res://tests/sea_motion_path_test.tscn
```

Inspect the opening boat animation in the actual game before adjusting the
frame grid, and check the first dive/splash, shore return, and both townhouse
arrival scenes. All camera changes are isolated to `penni-diving`.
