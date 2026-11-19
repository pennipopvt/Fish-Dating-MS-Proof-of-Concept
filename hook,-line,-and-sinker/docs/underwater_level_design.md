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


## Silas encounter diagnostics (F7/F8)

The *trigger is code*, not an Area2D: `DivingWorld._process()`
calls `_check_escape_followup()` every swimming frame. It requests
`SeaStoryDirector.on_followed_escape()` when the initial fish has escaped
and Penni crossed the follow threshold; it also calls the same event
when she comes within **108 world pixels** of `Sea/NPCs/Silas`, even
if the first fish was skipped. The story should mark `help_called`
only after the UI accepts the call.

**F7** toggles a temporary debug panel on Main's outer UI CanvasLayer
(layer 120), showing Silas distance, escape/follow flags, whether the
story has consumed the event, whether Main bound the real bubble,
its visibility and screen rect. **F8** bypasses the story completely
and draws a persistent `UI TEST: Help me!` bubble at a fixed onscreen
position. Pressing F8 also displays the panel. The Output console logs
`[SEA DEBUG]` only on trigger-state transitions, `[SEA STORY]`
when the story trigger is actually entered or delivered, and
`[SEA BUBBLE]` if its speaker/display reference is lost.

Interpretation: F8 invisible = renderer/layer/scene issue; F8 visible
but `proximity trigger: false` = player/trigger issue; proximity true
but `help_called: false` = story/UI delivery issue; help true but
call invisible = bubble was hidden after delivery.
No story conditions or normal artwork are changed by diagnostics.


## Encounter debug fix: editor Stop conflict and story/render separation

Godot F8 is Stop. F7 still toggles the debug panel; **B** while
the panel is open forces a standalone `UI TEST: Help me!` bubble.

The game sets `help_called` when the encounter trigger fires, even
when `SeaSpeechBubble` cannot be drawn. The independent
`_help_ui_pending` state retries the popup every 0.6 seconds if it is
missing until Penni talks to Silas. The F7 panel shows both states,
distinguishing a failed proximity trigger from a failed renderer.


## Missing SeaSpeechBubble node recovery

An actual F7 screenshot showed `help_called=true`, proximity=true,
but `UI bound=false`, `UI ready=false`, and an empty Call rect. That
proves the issue is a missing/unusable `Main/SeaSpeechBubble` instance,
not the story trigger or tail geometry.

`Main._ready()` now calls `_ensure_sea_speech_bubble()` before
binding the director. It uses the authored scene if valid, otherwise
instantiates `scenes/sea_speech_bubble.tscn` under Main at runtime.
If loading that scene also fails, it creates the same `SeaSpeechBubble`
class and the minimum required child nodes directly, with a visible
white fallback Panel and optional original 9-slice/tail textures.
No new scene is referenced from `main.tscn`; art and layout remain
unchanged for healthy projects.

F7 now reports `UI node` and `source` so we can see which recovery
path was used. The B test (with F7 open) can also restore the missing
node and rebind the director if necessary.


## Native voice bubble + companion combat smoke tests

`res://tests/sea_storyboard_test.gd` checks that the new native-scale
Pixel Operator text reveals over time, the nine-slice expands, the cry
fades, and it repeats after a pause without consuming the story event.
`res://tests/sea_companion_actor_test.gd` checks right-click target
selection, physical chase, no damage before reaching the fish, the
unchanged CompanionBattle damage after arrival, hit lunge, and recall.
The existing `tests/diving_companion_battle_test.gd` remains useful
for unit-level species damage and exhaustion (its old prototype-scene
integration section references an obsolete scene tree).
F7 reveals the active bubble phase, gameplay-pixel scale, the target,
companion attack range and last click-command result.

These tests have not yet been executed in an installed Godot runtime.
In particular, scene load/typing and animation rendering still need
an actual playtest before treating the changes as stable.


## November scripted net sequence, solo reaction and circle marker

The first fish now has a **small scripted reel state** in `DivingWorld`:
the existing latched `NetProjectile` remains visible, each scroll physically
retrieves 12 world pixels, and after at least three scrolls near Penni
(or a conservative maximum of eight) tension ramps from 0.55 to 1.0
over 0.7 seconds. Only then does `line_broken` fire and the fish escape
left; `SeaStoryDirector.on_first_fish_escaped()` requests a Penni-only
dialogue line: **“Damn, it got away.”** It uses `DialogueManager`'s
new `request_player_monologue` and the normal `DialogueUI`, with
a temporary player context so Silas's dialogue flags are unaffected.
The help call cannot interrupt an active conversation.

After Silas's introduction, netting the trapped eel uses a separate
`silas_rescue` state. It retrieves Silas by 13 pixels per scroll with
**zero tension, no attack phases, and no outward fish pull**. At 17 pixels
the original `SeaStoryDirector.on_silas_rescued()` is called. F/Escape
cancels a scripted reel and safely resets the net/state.

The user's new 12x12 white/black `speech_marker.png` is used as a
small independent circle at Silas's projected on-screen position (or
clamped to the game viewport boundary). It no longer rotates or joins
the speech box, but fades with the call. The nine-slice retains its
typewriter growth; text is Pixel Operator 14 native pixels with more
padding and nearest-neighbor filtering.

`SeaTutorialCue` now accepts `command` with a replaceable
`right_click_sprite`; `DivingWorld` exposes a matching Inspector
texture. The cue appears when companion help is offered and hides
on the first valid target selection. F7 now includes scripted reel
phase, number of scrolls, line tension, Penni's reaction flag and
Silas's rescue flags.


## Marker pixel density and Silas visual scale

The authored speech frame is a **32x32** PNG with a 1-pixel outline;
the independent circle marker is **12x12**, also with a 1-pixel outline.
The runtime fallback in `Main._ensure_sea_speech_bubble()` previously
created a **24x24 TextureRect** for that 12x12 marker, doubling its
source pixels relative to the nine-slice. Both the authored and fallback
paths now use the source texture's exact pixel dimensions, nearest
filtering, and no additional local scale. All of the speech UI still
shares the same 320x180 game canvas, and the circle remains separate
from the frame.

`SeaNPC.fish_sprite_width` is a per-instance visual export, default
20 pixels as before; Silas overrides it to **30 pixels** in
`scenes/sea_area.tscn`. Only `NPCs/Silas/Sprite.scale` changes:
the actor position/scale, existing invisible rescue hit target,
interaction radius, and companion battle distances are unchanged.


## Compact sea dialogue and persistent facing

The 11px Pixel Operator voice bubble now uses 30px height with 7px/4px
padding, sits a little **higher/right** of Silas, and continues expanding
as its letters type in. The circle marker is also shifted to the
upper/right of Silas rather than below-left. The separate companion
guidance is an **8px font in a 132x30 native-pixel label** with a small
9-slice frame at the upper right. It wraps rather than overflowing
across the entire bottom of the game.

`SeaNPC._process` now changes `Sprite.flip_h` only after meaningful
horizontal movement, preserving Silas's most recent facing when idle
or swimming vertically.

The sharp vertical change in water color near the sea boundary was
caused by `Player/Camera2D/UnderwaterTint` following the Camera2D
node rather than its *rendered* screen center when camera limits clamp
the view. `world_day_night.gd` repositions the 320x180 tint rect
relative to `Camera2D.get_screen_center_position()` each frame, so
the same shader remains aligned across the full screen near the
sea boundaries without changing map geometry.


## F7 debug Skip Dialogue button

The F7 panel now has a real mouse-clickable **Skip Dialogue** button
(bottom right of the panel). It calls `DialogueManager.end_conversation()`,
which emits the normal `conversation_finished` signal and allows
existing Fish Co, Silas and dive-transition listeners to react.
This is a developer shortcut: it bypasses any dialogue choice effects
that were not selected, so it must not be used as evidence that all
branching dialogue progression is working. If there is no active
conversation, it prints a harmless diagnostic message instead.
The debug panel intercepts its own clicks so pressing Skip cannot
simultaneously cast a net under the UI. F8 remains untouched.


## Adjustable sea UI (Inspector) — Nov 19

Use `Main/SeaSpeechBubble` in `scenes/main.tscn`. Its grouped
export values are authored in *native 320x180 pixels*: **Call: Text
and Size** (`font_pixels`, `call_max_width`, `call_height`,
`call_wrapped_height`, `call_text_inset`), **Call: Position
and Timing** (`bubble_offset`, `marker_offset`, speed/holds,
`screen_margin`), and **Hint: Position and Size**
(`hint_top_right_offset`, `hint_width`, `hint_height`,
`hint_font_pixels`, `hint_padding`). Change these in the Inspector,
run the scene, then iterate without editing GDScript.

The tutorial hint no longer owns a separately stretched
`NinePatchRect`; it is a bounded `Panel` with a pixel-width black
border and white fill, in the existing UI. This prevents the
intermittent full-screen white rectangle seen when the old frame
stretched. The repeating Silas help call still uses its original
nine-slice sprite and the independent circle marker. Both authored
and recovery paths use the same small hint panel.


## Editable fish avoidance — small first fishing pass

For normal fish, select `Sea/FishSpawns/<fish>` in
`scenes/sea_area.tscn` and use the **Fish Approach and Flee**
Inspector group:

- `preferred_player_distance` (game pixels): minimum comfortable
  distance before a wary fish retreats at full speed; **0** disables
  the stronger distancing and allows close fish
- `alert_distance`: begins retreat before that preferred distance
- `flee_speed` (game pixels/sec): preferably above Penni's
  **78 px/sec** swim speed for cautious species

The ordinary `MulletAfterSilas` starts at **52px preferred,
76px alert, 112px/sec**. `FirstFish` uses **0px** and remains trapped
by the one-time tutorial until scripted capture. The NPC rescue
target remains trapped and unaffected. `DivingWorld` copies
these exports into `DivingWildFish`, whose existing `swim` loop
retains all existing wander, cooldown, companion concealment,
and region bounds behavior. A wary fish backs away physically when
Penni gets close; it does not teleport and it can still be netted
from a distance. Near walls or the sea boundary, a trapped fish
can still be approached; consider avoidance around tile collisions
as a separate iteration.

The normal fishing state authority stays in `DivingCombat`
(phase timings, reel distance, tension, parry and feedback state).
Its existing Inspector exports at `Sea/Combat` are the source for
combat pacing changes; avoid adding duplicates to `DivingWorld`.
Restoring audio, impact, line vibration and more legible parry
effects should be a **separate gameplay feedback pass** after
testing the distancing numbers. Do not couple lighting or a new
combat controller to this small behavior change.


## Editing the sea speech bubble (and no extra instruction popup)

Open `res://scenes/sea_speech_bubble.tscn` directly in Godot,
select its **SeaSpeechBubble** root, then edit **Call: Text and Size**
and **Call: Position and Timing** in the Inspector. This is the
existing PackedScene instanced at `Main/SeaSpeechBubble` in
`res://scenes/main.tscn`; the UI is deliberately **not** inside
`sea_area.tscn`, which is a SubViewport world scene. Bubble and
marker offsets are measured from Silas in the 320x180 game pixel grid
at runtime, so the static editor placement won't match the in-game
camera-projected position.

The unrelated tutorial **HintFrame + Hint** panel has been removed
from the authored scene, runtime fallback and story calls, not just
hidden. Silas's speech call, the standalone circle marker, the normal
NPC dialogue UI and the camera's graphical tutorial sprites
(WASD, cast/reel, right-click) still function separately.
