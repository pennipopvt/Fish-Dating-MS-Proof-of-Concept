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

The boat's editable source is **prefabs/intro_boat.tscn**, with its root at
`(2250, 124)`, east of the currently playable beach. On the opening,
`FishCoOpeningSequence` instances that exact scene under **World/IntroBoat**.
Godot 4.7 silently discarded the instance when it was nested directly in
`world.tscn`, so authoring the boat in its own PackedScene and placing it
through the existing opening owner avoids that engine serialization issue.
The boat is still part of the same persistent World at runtime, inside its
original Water rectangle. No other sky/water clock or renderer is created.

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
godot --headless --path . res://tests/world_camera_intro_test.tscn
godot --headless --path . -s res://tests/diving_island_transition_test.gd
godot --headless --path . res://tests/diving_party_test.tscn
godot --headless --path . res://tests/sea_motion_path_test.tscn
```

Inspect the opening boat animation in the actual game before adjusting the
frame grid, and check the first dive/splash, shore return, and both townhouse
arrival scenes. All camera changes are isolated to `penni-diving`.


## Stable sky and first-fish reveal

The original **World → Sky** contains the actual gradient, stars, sun, moon
and cloud templates, so you can still edit them in the world scene. At runtime
`WorldDayNight` moves that same Sky node into `World/SkyLayer`, a
viewport-fixed background canvas. The sky no longer follows fractional camera
positions, avoiding camera-smoothing jitter. Its visible height is clipped
against the **real World/Water** surface, so underwater views do not invent a
second horizon. The cloud sprites retain their existing slow drift and use
the same day/night tint as the original world.

The existing first-fish discovery is still one-time and still owns the player
input lock. Its `SeaEncounterSequence` now uses the shared
`WorldCameraController` to pan to the actual tutorial fish, hold, and pan
back before the lock ends. In **Sea → EncounterSequence**, adjust the three
Inspector values:

- **Fish Focus Pan Seconds** (default 0.4)
- **Fish Focus Hold Seconds** (default 0.55)
- **Fish Focus Return Seconds** (default 0.4)

No new dialogue, popup, scene or duplicate camera is involved. If the encounter
is interrupted by leaving the sea, normal camera follow is restored.

Regression coverage: `world_camera_intro_test.tscn` verifies viewport sky,
waterline clip, cloud tint and normal camera following;
`first_fish_camera_focus_test.tscn` verifies the one-time focus, input lock,
return and interruption handling.

## Water color palette

For the visible sea colors, open **prefabs/world.tscn**, select the root
**World** node, and expand **Water Colors** in the Inspector. Six swatches
correspond to sunrise, morning, afternoon, late afternoon, sunset and night.
They are the **runtime** colors, unlike the `Water` ShaderMaterial's initial
water-color value, which the clock overrides. The default daytime colors are
now a little lighter.

Underwater, `Water` remains translucent (the original 0.14 deep-water
alpha), so fish and terrain stay visible. To prevent that transparency
showing the viewport's nearly black clear color, `WorldDayNight` creates
one flat `UnderwaterBackgroundLayer` behind the sea and the sky. It uses
exactly the **same** exported water palette and time-of-day transitions.
The existing water reflections, sky, separate underwater tint and sea
collision are unchanged. No duplicate world or second clock is introduced.

To brighten the sea further, edit the **Water Colors** swatches on **World**,
particularly *Afternoon* and *Morning*. The existing underwater blue haze is
still separately editable under
`World/CameraController/Camera2D/UnderwaterTint`.
