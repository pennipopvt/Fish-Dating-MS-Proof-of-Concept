# Diving prototype — integrated island playtest

This is the integrated diving/fishing implementation, combining Jerry's companion combat with Penni's first-day onboarding on `penni-diving` (and the main integration branch after merge).

## First-day story and controls

Start with the Fish Co contract call on the boat. The shared circular iris closes and reveals the dock. Open the marked terminal to see the three-day quota and grand prize. When the terminal closes for the first time, the second Fish Co call explains your first dive. The existing InteractPrompt appears above the dock. Interact there and confirm **Yes** in DialogueUI to dive; **No** keeps you ashore without spending an action. After the first dive is confirmed, the other terminal tabs become available.

## Start from the normal island

Run the Godot project normally (`res://scenes/main.tscn`). The original island, dock, houses, shop, day/night cycle and terminal are still present. Walk to the **fishing dock on the left** and interact exactly as you used to start fishing.

**Penni jumps off the dock and descends through the real water surface**, with one camera following her continuously. As she submerges, the existing water reflection fades into a blue tint. Sky remains visible above the waterline when the camera is close enough to the surface. Surfacing returns Penni to the dock in the same World, without a black iris or a second gameplay viewport.

The sea is kept alive between dives so the fish you've caught and Silas's conversations/following progress don't reset each time. A dive costs one world time action when you return, rather than one action per fish caught.

## What to do underwater

1. **Move in four directions** with WASD / arrows. The sea is larger than the viewport and the camera follows you.
2. **Left-click anywhere in the sea to throw your net in that direction.** The projectile travels visibly, up to **110 world pixels** (adjustable in `NetProjectile.max_range`), then retracts if it hits nothing. Clicking a fish no longer selects or teleports the net to it. You can miss, lead a moving fish, or catch a fish that crosses the net's path.
3. **When the thrown net physically hits a fish**, it latches onto that fish, freezes normal movement, and starts the familiar scroll/parry encounter. The same net remains visibly attached as you reel it closer or it dashes away.
4. **Scroll down three times quickly during the fish's attack** to parry. Both normal and perfect parries build the species-specific **stagger meter** from `revised-fishing`; a perfect parry builds more but **does not instantly stun or catch** a fish. **During prewindup, the fish keeps pulling away and scrolling does nothing. During windup, the fish pauses, but ANY scroll counts as an early parry miss and immediately triggers its dash. Wait for the actual attack to begin before scrolling three times.** Reel during an earned opening to shorten the net line while the fish resumes pulling against you. A perfect parry also immediately clears line tension. Only when stagger fills does the fish become stunned and allow a stronger free-reeling burst. A missed parry sends the fish dashing away and builds tension; afterward it briefly recovers, giving you another contested reeling opening. **You catch the fish only when it is physically pulled to within 14 world pixels of Penni**, not when an arbitrary progress bar fills. Esc releases it.
5. Successful captures go into the normal FishingManager's storage, collection and challenges, exactly as before. **No fish is stored when merely clicked or hooked.**
6. Swim **east** to the garden eel trapped in an old net by his burrow. Press **E** to discover that he can speak: he asks, **"Help pull me out!"**
7. After his plea, **aim and cast the same projectile net directly at Silas**. He stays near the burrow, and a hit begins the normal scrolling/parrying encounter. **Reel him all the way to Penni** to free him. If he escapes, he remains trapped at the burrow, so you can try again. The catch is a **companion rescue**, not an ordinary fish for inventory or collections.
8. Silas thanks you, introduces himself, and **begins following once the conversation ends**. Swim with Silas, talk to him, catch more fish, and explore the **glowing shell garden** farther east. Press **Q** to ask him to conceal you for five seconds so wild fish don't flee as easily.
9. When you're ready, return to the illuminated **surface marker** near the start and press **E**. Silas only asks to join you on land once you've gotten to know him. Use the **normal dialogue choice buttons** to invite him or stay together underwater.
10. If you invite him, the camera follows Penni back to the **original island dock**, where Silas appears as a human in a little poof animation. His portrait switches from the **fish sprite underwater** to the **human portrait on land**; the existing dialogue interface and NPC recruitment / housing systems handle his life on land.

### Controls

| Input | Meaning |
| --- | --- |
| Overworld movement | A / D as before |
| Dock interact | Space / left-click in the original world |
| Underwater WASD / arrow keys | Swim freely in four directions |
| Underwater left-click | Fire a directional net projectile (110-pixel max cast distance); catch and reel Silas out of his trapped net after he asks for help |
| Scroll down in combat | Three rapid ticks to parry the attack, then reel during the opening |
| Escape in combat | Release the fish (it swims away) |
| Underwater E / Space | Talk, advance the standard dialogue UI or interact with the surface marker |
| Q | Silas conceals you once he joins you |
| Right-click a fish | Send Silas to auto-battle it (within 120 px); right-click it again to call him back |
| F | Call Silas back from a battle |
| Dialogue choice buttons | Invite Silas to land or postpone, using the same UI as land conversations |

## Companion auto-battle and fish health

Once Silas follows you, **right-click a fish** to send him at it. The two trade hits on their own speed timers, and small health bars appear over both. **Call him back** (right-click the fish again, or F) before it's too late:

- A fish at **0 health is knocked out and lost** for the session (not stored).
- **Silas at 0 health is exhausted** and can't battle again until you **rest** (the next `GameManager.day_started`). Otherwise he slowly regains health (`regen_per_second`) while not fighting. Fish never regain health during a session, even if they escape the reel.
- Throwing the net and latching onto a fish ends the battle.

**Progression through strength, not a block:** every fish can be netted, but its reel-fight strength follows its remaining health on a **reverse-sigmoid curve** (FishData **Reel Strength** group): it stays near full strength while healthy, drops steeply around `curve_midpoint` (sharpness `curve_steepness`), then flattens near its lowest point `min_strength` at 0 health.

- **Pulling force** (passive and contested pull, reel and miss tension, and stagger resistance above 1×) runs from `min_strength` at 0 health to `min_strength × force_range` at full health. `force_range` is at most 2.5.
- **Miss-dash distance** runs from `min_strength` to `min_strength × dash_range`, with `dash_range` at most 1.5.
- A worn-down fish is never easier to stagger than its authored value.

Each hit deals `max(1, attack - defense / 2)`. Stats are placeholder tuning. Fish use the **Battle** group (`max_health`, `attack`, `defense`, `speed` = attacks per second) and **Reel Strength** group. Silas uses `resources/companions/silas_battle.tres` (`CompanionStats`: 60 HP, 6 atk, 3 def, 1.0 spd, 0.5 HP/s regen).

| Fish | Tier | HP | Atk | Def | Spd | Lowest | Pull × | Dash × | Mid / steep | Silas 1v1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Goby | easy | 20 | 2 | 1 | 1.4 | 0.5 | 1.6 | 1.2 | 0.5 / 8 | wins, −7% |
| Mullet | easy | 30 | 3 | 2 | 1.0 | 0.6 | 1.8 | 1.25 | 0.5 / 8 | wins, −13% |
| Porgy | hard | 45 | 4 | 4 | 1.0 | 3.0 | 2.5 | 1.4 | 0.5 / 10 | wins, −46% |
| Needlefish | hard | 30 | 5 | 1 | 1.6 | 2.2 | 2.2 | 1.5 | 0.55 / 14 | wins, −47% |
| Flounder | hard | 50 | 4 | 5 | 1.15 | 1.8 | 2.5 | 1.3 | 0.45 / 10 | wins, −67% |
| Tuna | hardest | 90 | 6 | 4 | 0.75 | 1.0 | 2.5 | 1.5 | 0.45 / 9 | **loses** at 18.7 s (tuna at 16%) |

Tuned with a simulated ideal player (perfect parry on every attack, reeling as fast as tension allows):

- **Easy fish** (goby, mullet) are catchable at any health.
- **At 12 scrolls/s**, the ideal player first wins at about 50% health for porgy and needlefish, and about 30% for flounder and tuna.
- **At 40 scrolls/s**, those become about 50% (porgy), 70% (needlefish) and 40% (flounder and tuna).
- **Nothing hard is ever caught at 80% health or more.**
- **Tuna:** call Silas back around 30–40% health. He still has about 10–15 HP there; left to fight to the end, he loses.

Code: `scripts/diving/companion_battle.gd` (`DivingCompanionBattle`, the `CompanionBattle` node under `Sea`), health on `DivingWildFish`, wiring in `DivingWorld`. Test: `tests/diving_companion_battle_test.gd` (uses autoloads, so run it from a temporary scene rather than `-s`).

## Implementation notes

- `scenes/main.tscn` remains the game entry point. `prefabs/world.tscn` contains the entire explorable world, including a reusable `scenes/sea_area.tscn` instance. `scenes/diving_prototype.tscn` is retained only as a legacy isolated combat test scene, not the live diving viewport.
- The circular iris remains for the Fish Co phone-call opening, but diving and surfacing now use a camera-followed movement through the shared surface.
- The underwater **world** stays at the original game's `320×180` pixels with `stretch_shrink = 6` and nearest-neighbor sprite rendering. The location/story/catch/prompt **HUD is now a separate full-resolution screen-space overlay**, not text painted into the 320×180 viewport. It uses clear default UI typography and solid contrast backplates, and contextual prompts are hidden while dialogue is open.
- Penni's world sprite is displayed at the original **1× scale**, matching the normal island character rather than being shrunk to 78%.
- **All underwater conversations use the existing `DialogueManager` and `DialogueUI`**. The temporary local dialogue panel was deleted. Dialogue text, speaker-name formatting, narration, selection buttons, and advancement are the normal game’s systems.
- In the water, NPCs display their **fish sprites** (Silas as a garden eel; Kuda as a barracuda) rather than their human portraits. Those underwater sprites are **flipped horizontally to face Penni** in the shared dialogue UI. **Penni keeps her original character portrait** on land and underwater; the human NPC portrait direction is unchanged on shore.
- Silas's first encounter still uses the "???" mystery speaker label, but his request is now to **net and reel him out of the abandoned snag**. He becomes a stationary catchable eel only after his dialogue, and can be rescued by winning the normal parry encounter. Losing never recruits him or records a fish inventory catch. The first-land transformation is preserved. Silas's invitation is a regular selectable dialogue choice, not a hardcoded number-key menu. Underwater chat uses free inline dialogue graphs so it does not spend an extra clock action.
- The original overworld Player becomes a swimmer underwater. Its land-only interact and fishing controller inputs are gated while the shared underwater net, dialogue and companion combat handle play.
- The `NetProjectile` node uses a real outward-and-returning animation with a fixed range and a swept collision check to prevent fast casts from tunneling through small fish. Once it hits, the visual net stays attached and the existing parry encounter begins. Fish outside the maximum range cannot be hooked, and an empty cast never awards a catch.
- **Between attacks** (prewindup and recovery), fish continually pull outward using their own `FishData.passive_escape_rate`, with the `Combat.passive_pull_multiplier` set to 1.5 by default. They stop pulling during windup and the unresolved attack, then resume contested pulling as soon as a parry succeeds. No reeling in prewindup, and scrolling in windup is an immediate miss/dash. Missed dashes still produce tension and are followed by a reeling recovery.
- Ordinary fish retain their authored **FishData/FishEscapeState attack timings, tension and miss-dash behavior**, plus the **species stagger resistance** tuned on `revised-fishing` (goby 65, mullet 70, porgy 78, needlefish 95, flounder 112, tuna 150). Normal parries add 24 stagger; perfect parries add 48. Full stagger grants the real stun, resets tension and gives enhanced free reeling. The large combat HUD and all three bars (distance, tension, stagger) have been removed. Distance is communicated by the actual fish's position; **tension is visible on the net line** (pale → amber → red, with yellow during a stagger stun). Stagger remains mechanically active but has no permanent visual meter yet, pending fish animation design. Combat's `catch_distance`, `reel_pixels_per_scroll` and `fight_slack` are configurable on the `Combat` node. **Base reeling is tuned to 2.5 world pixels per scroll** (previously 7), with the reel-strength upgrade scaled proportionally and a 1.5× stagger-stun bonus. Adjust `Combat.reel_pixels_per_scroll` in the Inspector for further playtesting.
- A **completed combat victory** contributes to existing catch/storage/collection systems without spending another world action; entering combat or losing does not award a fish. The world clock advances when you leave the water.
- Silas's dive-specific friendship state persists in the sea instance while the game is running. On his first visit ashore, a custom first-land conversation runs in the original game's DialogueUI; afterward he joins the usual town NPC/housing flow.
- The original bait/bobber items and existing fishing controller still exist in the repository. They're not used by the **dock's new diving path**. This experiment does not yet rebalance the old upgrades for underwater net-catching.
- The net is a visual tether, rather than a physics-driven rope. The authored fishing attack timing now applies to underwater encounters. This prototype is focused on whether exploration companions plus concentrated reel/parry encounters feel better than instant clicking.

## Editing the underwater level in Godot

See [underwater level design](underwater_level_design.md) for the current scene workflow. **Only `LevelArt/Solids` is a TileMapLayer.** Draw physical walls using its 16px wall atlas and collision polygons. All backgrounds, details, coral and foreground overlays are **individually placed PNG Sprite2D nodes**, under `LevelArt/BackgroundSprites`, `LevelArt/Details` or `ForegroundArt`.

The water already uses the original **World/Water reflection shader** plus a camera-relative blue underwater tint. Both effects share the actual waterline; there's no water TileMapLayer. Story locations and fish spawning remain editable markers. The sea starts at 920×530 world pixels, shown through the 320×180 native camera; change `EditorGuide → Map Size` to resize it.

Penni and the net are set up to stop against painted wall tiles, but companion/fish pathfinding around cave geometry hasn't been built yet. Test wall collisions in Godot before designing narrow spaces.

## Removed bait and bobber content

The dive build no longer instantiates the old bait box, bobber shelf, or their menus. Bait upgrades and the obsolete extra-casts upgrade are removed from the shop. The `diving` net and combat use no equipped bait or bobber. Legacy scripts and data remain in the repo for compatibility with the original controller, but they are not part of the playable dive loop.

## Verification

Check the new integrated flow with:

```bash
godot --headless --path . -s res://tests/diving_island_transition_test.gd
godot --headless --path . -s res://tests/diving_prototype_test.gd
```

**The tests have been added but not executed in this editing environment, which has no Godot binary.** Please run the project in Godot and report any script/parser warnings or visual issues so they can be corrected before merging.
