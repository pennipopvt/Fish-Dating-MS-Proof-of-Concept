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
├── FishSpawns           three movable fish species markers
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


## Input tutorial polish (first dive)

After entering the sea, a small **WASD** diagram fades in near the lower
center of the screen and gently bobs. The tutorial fish starts at (-155, 240)
so Penni has room to actually swim before seeing it. Once Penni has moved at
least 50px and is within 104px of that fish, her swimming stops briefly
(the follow camera settles too) and a pulsing **LMB / CAST NET** cue appears.
A real left-click net cast immediately releases movement: there is no
time-based lock. When the first fish is hooked, **SCROLL / DOWN TO REEL**
replaces the icon. The original one-time line break and Silas's offscreen
"Help me!" then proceed unchanged.

The reusable screen-space cue is `SeaSpeechBubble/InputPrompt` (script:
`scripts/diving/sea_input_prompt.gd`). It exposes **Movement Sprite**,
**Cast Sprite**, and **Reel Sprite** textures in the Godot Inspector, so
you can replace the simple Pixel Operator placeholders later without
changing any story code. The old persistent instruction label is now
centered near the bottom of the screen instead of the upper-left corner.
