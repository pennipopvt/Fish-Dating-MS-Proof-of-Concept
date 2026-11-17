# Revised fishing — prototype playtest guide

This experimental implementation lives on branch `revised-fishing`. It is not merged into `main`.

## Core loop

- The first **five casts** cannot hook Silas. **Cast six** is a guaranteed Silas encounter if he has not yet been caught. If he escapes, subsequent casts retry the guaranteed encounter until a successful catch.
- Landing Silas still produces the existing fish-to-human transformation and first-catch dialogue. **Accepting/recruiting** him adds his fish form to the party. (You do not automatically recruit merely by hooking him.)
- The existing terminal has a **TEAM** tab. The first listed party member is the active lure; select another fish's card and choose **SET AS LURE** to switch. Other companions appear near the dock while fishing.
- During a cast, the lure's **fish sprite replaces the bobber** at the line/water surface, then disappears when a fish bites. With no recruited party member, there is no artificial bait/bobber sprite.
- With Silas anywhere in the party, his **spyglass passive** reveals which fish you have hooked. He does not need to be the active lure.
- When Silas is the active lure, he uses the former orange-bait weight profile, favoring aggressive species. The solo early game uses unweighted random encounters. Non-Silas lure affinities are placeholders for later balancing.
- Bait boxes, bobber shelves, and their menus are removed from the playable world. The legacy bait/bobber resource files and manager remain in the repository for compatibility with existing quests and dev scripts, but they no longer alter playable fishing.

## Combat

The existing reel/parry scroll timing is retained.

| Response | Result |
| --- | --- |
| Normal / close parry | Avoids the fish's missed-parry dash, +24 stagger, normal reeling |
| Perfect parry | Avoids dash, +48 stagger, normal reeling (no immediate stun) |
| Miss | A short dash, including tension loss, then a brief ordinary reeling window |
| Full stagger bar | Stuns fish for its authored duration; tension clears, reeling is free and 2.8× as strong |
| Silas command on line | **Q or right-click** during windup / attack: Silas hides, avoiding dash and relieving 0.30 tension, but the player gives up parry stagger this attack |

Stagger naturally decays at **2 points/second** while a fish is fighting and resets when the stun ends. Fish resources have individual stagger resistance values. The new `short_dash_scale` makes a missed dash 55% of its original distance; species retain their relative dash differences.

Reel recovery defaults to at least **one second** after an attack or missed dash, before the next warning begins.

## Suggested first playtest

1. Cast five times. Verify no Silas; try cast six and verify the transform after catching him.
2. Recruit Silas and check the TEAM page; his sprite should appear on subsequent casts.
3. Hook a fish; confirm the identity bubble appears with Silas in the team, and the stagger meter increases on close/perfect parries.
4. Try a missed parry; verify the fish dashes a little but the player can reel afterward.
5. Fill the stagger meter; verify a distinct stun phase and substantially stronger, tension-free reeling.
6. With Silas on the line, compare **Q/right-click during a windup** to parrying: the command should relieve tension without adding stagger.
7. Recruit another NPC, set that NPC as lure, and verify Silas's identity passive still works while he waits near the dock.

## Automated regression script

From the Godot project directory:

```bash
godot --headless --path . -s res://tests/fishing_combat_states_test.gd
godot --headless --path . res://tests/terminal_shop_challenges_test.tscn
```

These checks were updated for the new combat and TEAM tab, but **were not executed in the repository editing environment**, which has no Godot runtime. Please perform an editor import and local playtest before merging this branch.

## Deliberately unfinished

- Other NPCs have slots and lure sprites, but their active commands and tuned lure affinities are not yet designed.
- Original gift/romance scripts still exist. Some legacy dialogue/reward references to bobbers may need a narrative pass after we decide on the new romance reward structure.
- This is a playable-system prototype, not a polished release; stagger UI layout, pacing, and visual placement require eyes-on testing.
