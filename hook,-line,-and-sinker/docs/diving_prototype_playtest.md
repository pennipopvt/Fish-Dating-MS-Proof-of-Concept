# Diving prototype — integrated island playtest

This experimental work is on the **`diving` branch**, based on `main`. **Nothing was merged into main or revised-fishing.**

## Start from the normal island

Run the Godot project normally (`res://scenes/main.tscn`). The original island, dock, houses, shop, day/night cycle and terminal are still present. Walk to the **fishing dock on the left** and interact exactly as you used to start fishing.

Instead of casting, **Penni jumps from the dock into the water**. A black circular iris closes around the splash, changes scenes once the screen goes black, then opens around Penni underwater. When you return to the surface marker, a matching iris closes on Penni and reopens back on the actual island. Both scenes use the same **320×180 native pixel viewport, scaled 6×**.

The lagoon is kept alive between dives so the fish you've caught and Silas's conversations/following progress don't reset each time. A dive costs one world time action when you return, rather than one action per fish caught.

## What to do underwater

1. **Move in four directions** with WASD / arrows. The lagoon is larger than the viewport and the camera follows you.
2. **Left-click anywhere in the lagoon to throw your net in that direction.** The projectile travels visibly, up to **110 world pixels** (adjustable in `NetProjectile.max_range`), then retracts if it hits nothing. Clicking a fish no longer selects or teleports the net to it. You can miss, lead a moving fish, or catch a fish that crosses the net's path.
3. **When the thrown net physically hits a fish**, it latches onto that fish, freezes normal movement, and starts the familiar scroll/parry encounter. The same net remains visibly attached as you reel it closer or it dashes away.
4. **Scroll down three times quickly during the fish's attack** to parry (the same strong-scroll timing as fishing). Perfect timing stuns the fish and clears tension. A close parry gives a contested reeling opening. **Scroll during the opening to pull the fish closer**; don't overfill the tension bar. Missing a parry makes the fish dash backward, increasing tension. Fill the capture-progress bar to win. Escape or press Esc to release; the fish swims away and can be pursued again.
5. Successful captures go into the normal FishingManager's storage, collection and challenges, exactly as before. **No fish is stored when merely clicked or hooked.**
6. Swim **east** to the garden eel near his burrow; press **E** to discover that he can talk.
7. Swim beside the **tangled net** near the burrow and **left-click** to untangle it. Silas introduces himself and starts following you.
8. Swim with Silas, talk to him, catch more fish, and explore the **glowing shell garden** farther east. Press **Q** to ask him to conceal you for five seconds so wild fish don't flee as easily.
9. When you're ready, return to the illuminated **surface marker** near the start and press **E**. Silas only asks to join you on land once you've gotten to know him. Use the **normal dialogue choice buttons** to invite him or stay together underwater.
10. If you invite him, the iris brings you back to the **original island dock**, where Silas appears as a human in a little poof animation. His portrait switches from the **fish sprite underwater** to the **human portrait on land**; the existing dialogue interface and NPC recruitment / housing systems handle his life on land.

### Controls

| Input | Meaning |
| --- | --- |
| Overworld movement | A / D as before |
| Dock interact | Space / left-click in the original world |
| Underwater WASD / arrow keys | Swim freely in four directions |
| Underwater left-click | Fire a directional net projectile (110-pixel max cast distance); clear Silas's net when next to the knot |
| Scroll down in combat | Three rapid ticks to parry the attack, then reel during the opening |
| Escape in combat | Release the fish (it swims away) |
| Underwater E / Space | Talk, advance the standard dialogue UI or interact with the surface marker |
| Q | Silas conceals you once he joins you |
| Dialogue choice buttons | Invite Silas to land or postpone, using the same UI as land conversations |

## Implementation notes

- Existing `scenes/main.tscn` is the entry scene again. `scenes/diving_prototype.tscn` now lives inside its own canvas layer and can still be opened separately for isolated underwater testing.
- The transition is a reusable aspect-correct circular iris shader, not a generic crossfade.
- The underwater **world** stays at the original game's `320×180` pixels with `stretch_shrink = 6` and nearest-neighbor sprite rendering. The location/story/catch/prompt **HUD is now a separate full-resolution screen-space overlay**, not text painted into the 320×180 viewport. It uses clear default UI typography and solid contrast backplates, and contextual prompts are hidden while dialogue is open.
- Penni's world sprite is displayed at the original **1× scale**, matching the normal island character rather than being shrunk to 78%.
- **All underwater conversations use the existing `DialogueManager` and `DialogueUI`**. The temporary local dialogue panel was deleted. Dialogue text, speaker-name formatting, narration, selection buttons, and advancement are the normal game’s systems.
- In the water, NPCs display their **fish sprites** (Silas as a garden eel; Kuda as a barracuda) rather than their human portraits. **Penni keeps her original character portrait** in the dialogue UI on land and underwater, with the same layout and positioning. The standard NPC portraits are restored on shore.
- The initial "???" identity clue and first-land transformation are preserved. Silas's invitation is a regular selectable dialogue choice, not a hardcoded number-key menu. Underwater chat uses free inline dialogue graphs so it does not spend an extra clock action.
- The overworld Player is busy during a dive so inputs do not trigger fishing or NPC interactions underneath the underwater view.
- The `NetProjectile` node uses a real outward-and-returning animation with a fixed range and a swept collision check to prevent fast casts from tunneling through small fish. Once it hits, the visual net stays attached and the existing parry encounter begins. Fish outside the maximum range cannot be hooked, and an empty cast never awards a catch.
- Ordinary fish have the **same fish-specific FishData/FishEscapeState attacks** they had in the original reel-and-parry system. Normal, perfect, and missed parries, tension recovery, miss dashes, stun duration, and upgrade bonuses are carried into a small underwater combat component. Catch progress affects the fish's actual distance from Penni in the ocean.
- A **completed combat victory** contributes to existing catch/storage/collection systems without spending another world action; entering combat or losing does not award a fish. The world clock advances when you leave the water.
- Silas's dive-specific friendship state persists in the lagoon instance while the game is running. On his first visit ashore, a custom first-land conversation runs in the original game's DialogueUI; afterward he joins the usual town NPC/housing flow.
- The original bait/bobber items and existing fishing controller still exist in the repository. They're not used by the **dock's new diving path**. This experiment does not yet rebalance the old upgrades for underwater net-catching.
- The net is a visual tether, rather than a physics-driven rope. The authored fishing attack timing now applies to underwater encounters. This prototype is focused on whether exploration companions plus concentrated reel/parry encounters feel better than instant clicking.

## Editing the underwater level in Godot

See [underwater level design](underwater_level_design.md) for the Godot scene hierarchy and hands-on editing guide. The lagoon's **920×530 world pixels** are visible through a **320×180 camera**. The fish spawn points and the story markers are now actual scene nodes; select and move them in `scenes/diving_prototype.tscn`. Add art under `Lagoon/LevelArt` or `Lagoon/ForegroundArt`, and assign a TileSet to `LevelArt/Terrain` when you're ready to paint tiles. Disable `Lagoon.show_prototype_environment` to hide most of the old script-drawn scenery once real art is placed.

**Warning:** obstacles are currently visual only. The diver moves with a rectangular position clamp and does not collide with cave walls or rocks yet; that needs a separate collision-aware movement pass.

## Removed bait and bobber content

The dive build no longer instantiates the old bait box, bobber shelf, or their menus. Bait upgrades and the obsolete extra-casts upgrade are removed from the shop. The `diving` net and combat use no equipped bait or bobber. Legacy scripts and data remain in the repo for compatibility with the original controller, but they are not part of the playable dive loop.

## Verification

Check the new integrated flow with:

```bash
godot --headless --path . -s res://tests/diving_island_transition_test.gd
godot --headless --path . -s res://tests/diving_prototype_test.gd
```

**The tests have been added but not executed in this editing environment, which has no Godot binary.** Please run the project in Godot and report any script/parser warnings or visual issues so they can be corrected before merging.
