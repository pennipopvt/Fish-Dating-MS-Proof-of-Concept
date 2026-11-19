# First dive storyboard — rough playable sea

The entire island, dock, swimming player, camera, day/night system, water
reflection and underwater tint are still in the SAME World. Run
`res://scenes/main.tscn` as usual. The actual underwater level is
`res://scenes/sea_area.tscn` on the `penni-diving` branch.

This is deliberately a *blockout*, based on the 13-page first dive
storyboard. There are no new finished art assets.

## Editing the sea

```text
Sea
├── EditorGuide          map size and editor grid
├── BackgroundSprites    two editable DockLeg placeholder Sprite2Ds
├── Solids               one collision-enabled TileMapLayer, single block tile
├── Details              empty for your custom sprites
├── ForegroundSprites    three replaceable Seaweed Sprite2Ds
├── Points               Entry and SurfaceExit markers
├── FishSpawns           tutorial mullet and later companion mullet markers
├── FishActors           spawned dynamically; don't paint here
├── NPCs
│   └── Silas            reusable SeaNPC, references existing silas.tres
├── StoryDirector        first-dive-specific flags and one-time triggers
├── NetProjectile        existing directional net system
├── Combat               existing reel/parry system
└── CompanionBattle      existing Silas vs fish battle system
```

**Change any Sprite2D's Texture** under BackgroundSprites or
ForegroundSprites to swap in your own PNG. The existing placeholders use
an AtlasTexture from the project's original environment tiles. All
sea floor walls are painted with **one tile** from the existing graphics
on `Solids`, which collides on physics layer 2. Use the TileMap paint
tools to edit/delete/extend the rough floor. These are separate physics
settings from the island TileSet.

## Storyboard sequence (first-pass logic)

1. The existing Fish Co intro / dock prompt leads into the continuous
   jump and splash. Reflection/tint remain in World.
2. The editor-placeable **FirstFish** mullet is near the dock support
   sprites. Left click to throw the real directional net.
3. On the **first successful hook** of FirstFish, scroll down once.
   The one-time story event breaks the line, pushes the fish away, and
   shows **Help me!** at the right edge of the screen.
4. Swim left toward the eel near **SeaweedSilas**. The **E** indicator
   appears in range. Speak to him using the existing DialogueManager;
   the current dialogue text is a small placeholder.
5. Left click to net the trapped Silas and finish the normal parry/reel
   battle to pull him out. He is **not** stored or counted as a fish.
   The existing silas.tres, NPCManager flags and dialogue portrait
   switching are reused.
6. After the rescue dialogue he follows Penni as a fish. Near other
   fish, his **I can help with that fish** call introduces right-click
   targeting. Fish and companion health bars reuse companion combat.
7. Return to the SurfaceExit marker with E or Space.

The *first escape is scripted*, while later fish use the normal
mechanics. This avoids embedding the special story condition in the
reel/parry implementation.

## Speech bubble replacement

The HUD scene is `res://scenes/sea_speech_bubble.tscn` and script is
`res://scripts/diving/sea_speech_bubble.gd`. Set **Bubble Texture**
on the SeaSpeechBubble instance to your nine-slice PNG, then tune
**Patch Margin** for its border. Until then, a plain bordered fallback
renders with the same spacing. The text is Pixel Operator, sized for
the 1920x1080 UI instead of the tiny 320x180 world viewport.
The text, arrow, and hint labels can all be positioned visually in
the separate speech bubble scene.

## Intentional limitations

- This is a rough blockout of timing, interaction and layout, not final
  art, authored dialogue or a full NPC-route progression.
- Foreground placeholders are independent sprites, not a final foliage
  system. Fish currently wander within sea bounds, not around walls.
- Companion mechanics, the net and parry code are reused, not rewritten.
- State lives for the current game session; persistent save/load for the
  new storyboard events is not implemented.
- Runtime verification is still required in Godot.

Tests to run from the Godot project folder:

```sh
godot --headless --path . -s res://tests/sea_level_layout_test.gd
godot --headless --path . -s res://tests/sea_storyboard_test.gd
godot --headless --path . -s res://tests/diving_island_transition_test.gd
```

## Leftward level, visible collision tile, and anchored sky

The first fish (x=-59), Silas (x=-391) and the rest of the sea are to
the **left** of the dock (Entry x=55). The editor guide now exposes a
Map Origin of (-832, 0) and a Map Size of (1024, 530) so the World/Player
can swim left and the shared camera follows correctly.

The 331 existing rough seabed cells were **mirrored** across the dock
and **raised 80px** to become visible sooner after the dive. The Solids
TileMapLayer still has collision layer 2. Its previously chosen upper-left
atlas tile has been replaced by one unmistakably visible, collidable
16×16 placeholder block, `sprites/environment/sea_solid_block.svg`.
When your finished wall sprite is ready, replace that one texture.

The sky is now in World rather than under Player/Camera2D. It is
vertically anchored to the real y=140 waterline and clips its children
there, including the sun, moon, and clouds. It still tracks horizontal
camera panning and retains the original time-of-day animation. The water
shader extends left across the entire sea.


## First dive input sprites

The entire old tutorial panel hierarchy has been removed. The input cue is
now ONLY `SeaSpeechBubble/InputSprite`, a centered, transparent TextureRect
that fades its image in/out when the StoryDirector requests an action.
No panel, background, caption or full-screen overlay is created.

Set the **Movement Sprite**, **Cast Sprite** and **Reel Sprite** properties
on the `SeaSpeechBubble` instance in `scenes/main.tscn`, or on the root
of `scenes/sea_speech_bubble.tscn`. The SVGs in `sprites/ui/tutorial_*.svg`
are temporary transparent symbols. Replace them with your own textures.
The separate character call bubble still uses its replaceable nine-slice.


## Tutorial sprite visibility / softlock fix

The previous SVGs were replaced with transparent PNG placeholders
(`sprites/ui/tutorial_wasd.png`, `tutorial_cast.png`, `tutorial_reel.png`).
The **single** `InputSprite` TextureRect is hidden at scene startup,
given a non-null default PNG in the scene, and explicitly positioned
around 72% down the root viewport. It is a 120×80px image, not a panel
or full-screen graphic. Swap textures through the SeaSpeechBubble
Inspector's Movement / Cast / Reel Sprite exports later.

The fish-focus pause now lasts **at most 1.15 seconds** and always
releases movement. The icon remains available afterward until a
successful net cast. The story refuses to lock Penni if the input sprite
is missing, hidden with its parent, or has no texture. This also avoids
getting stuck at the first fish if its tutorial cue fails to render.

## Import-independent input cue (November hotfix)

Newly added PNG files were not available as imported Godot textures in
some project copies, causing `preload("res://sprites/ui/tutorial_wasd.png")`
to fail while parsing `sea_speech_bubble.gd`. The speech-bubble script
and scene now reference **no tutorial image files**. Three tiny transparent
key/mouse textures are made in memory when first requested. The
`SeaSpeechBubble` Inspector still exposes movement, cast, and reel
Texture2D slots: assigning your finished art replaces each placeholder.
There is no background panel or screen-wide overlay.

The existing 1.15-second first-fish focus safety timeout is preserved.

## Camera-native tutorial cues

The first-dive WASD/click/reel indicator is now `World/Player/Camera2D/SeaTutorialCue`
(`scripts/diving/sea_tutorial_cue.gd`), one sprite in the **same 320x180
SubViewport as Penni**. It renders above the underwater tint and fades only
its own alpha. No tutorial drawing, texture preload, or sprite import is
required in the separate Main CanvasLayer. Each action has a tiny transparent
pixel placeholder drawn by the sprite itself if its exported texture is unset.

Assign replacement images to **Movement Sprite**, **Cast Sprite** and
**Reel Sprite** on that camera child in `prefabs/world.tscn`.
`SeaStoryDirector` now addresses this scene node directly, with no group
lookup; the old input overlay node and code were removed from
`SeaSpeechBubble`, which remains solely for spoken dialogue.

The fish-focus check uses the full 110px net-casting reach and the sea
retries the initial WASD cue after the dive if the usual transition
notification occurred before its UI became available. The existing focus
safety timeout prevents a gameplay softlock.

## Sprite2D / Camera2D script type repair

The first camera-native cue was embedded as a scripted Sprite2D directly
within `prefabs/world.tscn`, which produced a script/native-type mismatch
while loading the parent camera on the user's Godot build. The cue is now
a separate `res://scenes/sea_tutorial_cue.tscn` with a Sprite2D **root**
and the `sea_tutorial_cue.gd` script attached to that root. The world
instances the scene below `Player/Camera2D`; the actual Camera2D remains
unscripted. The tutorial cue exports are on the instance's Sprite2D root.
No new tutorial manager or overlay was introduced. The smoke test asserts
the native type and verifies the camera script remains empty.


## Tutorial cue loader repair

To avoid a Godot missing-dependency error while opening `world.tscn`,
the separate `scenes/sea_tutorial_cue.tscn` is no longer referenced.
Instead, `DivingWorld._ready()` creates exactly one `SeaTutorialCue`
Sprite2D under the existing `Player/Camera2D`. The 9-slice speech
bubble remains independent. The sea inspector now exposes
**Movement Tutorial Sprite**, **Cast Tutorial Sprite**, and
**Reel Tutorial Sprite**. Leave them blank for the script-drawn symbols;
assign PNG art to replace them without editing the world scene.

`world_day_night.gd` now treats missing shader items safely instead of
dereferencing a null material when the editor has partially loaded a
broken scene. It continues the water reflection and sky cycle whenever
their shader resources are present; underwater tint is optional.


## Escaping first fish / deferred Silas call

On the scripted first scroll, the net releases, the tutorial cue disappears,
and the first fish accelerates **330px left in 0.85s** before being removed
once offscreen. The fish is removed from normal catchable/wandering actors
at the start of that animation, so it cannot swim back or be re-hooked.

**No bubble appears during the reel or dash.** Penni must follow the fish
another 75px and move a little past its former position. Once the escape
animation is finished, `SeaStoryDirector.on_followed_escape()` plays
Silas's one-time, left-directed “Help me!” bubble. This also gates his
initial interaction until the call has happened. No extra trigger scene,
new manager, or artwork dependency is introduced.

## Extra bottom fish removed

Removed the `GobyNearBottom` marker at (-236,315), which put an unrelated
fish under Penni during Silas's initial offscreen call. `FirstFish` and
`MulletAfterSilas` remain for their respective tutorial beats.


## Silas speech bubble: attached to speaker with one directional tail

The user's original 32x32 `speech_bubble.png` and 12x12
`speech_tail.png` are installed at `sprites/ui/`, and assigned to the
existing `SeaSpeechBubble` Inspector's Bubble Texture and Tail Texture.
The white bubble uses a 6px nine-slice margin with Pixel Operator black
text, and the tail is an independent, rotatable transparent TextureRect.
No separate arrow or second bubble UI exists.

`SeaStoryDirector` now calls `show_attached_call` with the existing
`NPCs/Silas` actor and Main's SubViewportContainer. Every frame the
speech UI maps Silas's world position through the game viewport to the
root UI coordinates. The bubble is clamped to the visible play area until
it can sit naturally above/right of Silas. Its single tail continuously
points toward his position. The first "Help me!" stays on screen without
a timer until Penni interacts with Silas; companion help uses the same
bubble with a 4.5s timeout. The regular dialogue UI, tutorial controls,
and fish code remain untouched.


## Speech bubble pixel scale and connected tail

The existing `SeaSpeechBubble` CanvasLayer is instanced **inside**
`Main/SubViewportContainer/SubViewport`, alongside `World`, so its
nine-slice frame, Pixel Operator letters, and tail are now rendered at
the same native **320x180** pixel resolution as Penni and the underwater
scene. It still appears over the game, and the ordinary dialogue UI
above the SubViewport remains unchanged.

The bubble is 88x32 native pixels with 10px Pixel Operator text and
7px horizontal/4px vertical padding. The offscreen clamp uses 12 native
pixels of margin. As Silas enters the camera view, the bubble follows
his position directly, without any rescaling through Main's UI.
The user's 12x12 tail sprite now draws *behind* the nine-slice and
connects via its flat top edge to the outside of the bubble, with a
1px hidden seam. The old center-of-tail-over-the-border placement is
gone. The bubble and tail art are still assigned in
`scenes/sea_speech_bubble.tscn`.
