# Diving prototype — playtest guide

This is an **experimental alternate game direction** on the `diving` branch, created from `main` (not the revised-fishing branch). It launches into `scenes/diving_prototype.tscn` by default. The original fishing scene and assets still exist in the project; nothing was merged into `main`.

## What to try

1. **Move in four directions** with **WASD** or arrow keys. You begin underwater in a larger scrolling lagoon, not at the original fishing dock.
2. Look for ordinary fish. They wander around and flee if you rush toward them. **Left-click on a fish when you're close** (roughly 45 world pixels) to throw a quick net and catch it. Clicking a distant fish will not catch it.
3. Swim **east** toward the small garden eel by a sandy burrow. Press **E** (or Space) when you are close. The fact that he speaks is your first clue that he's unlike ordinary fish.
4. Swim near the **tangled net** beside his burrow and **left-click** to clear it. He introduces himself as **Silas**, then asks to tag along.
5. Explore with Silas physically following you. Press **Q** to have him hide you in a veil of sand for five seconds; nearby fish become less skittish. This has a brief cooldown. You can keep catching ordinary fish together.
6. Stop and talk to Silas a couple more times. Optionally explore the **glowing shell garden** farther east to trigger a shared discovery.
7. Swim back to the **surface marker** near where you started (left side of the underwater map). Press **E**. After you've talked enough, Silas asks if he can come with you. Use **1** to invite him or **2** to stay underwater with him.
8. If invited, you surface together. Silas uses his existing **humanoid idle sprite** on shore; in the water, he remains his **garden eel fish sprite**. Walk to the dock on the right and press **E** to dive again.

This is intentionally *not* the old parry/reeling system. It tests whether spatial movement, approaching fish, and having Silas alongside you feel better before committing to a full new capture/combat mechanic.

## Controls

| Control | Action |
| --- | --- |
| WASD / Arrow keys | Move in four directions |
| Left click | Throw net at a nearby ordinary fish, or untangle Silas's net |
| E / Space | Talk to Silas; ascend or dive at the appropriate marker; advance dialogue |
| Q | Silas's temporary concealment while he's following you underwater |
| 1 / 2 | Accept or postpone Silas's invitation to come onto land |

## Scope and limitations

- The fishing game's normal `scenes/main.tscn` remains untouched. Only the `project.godot` entrypoint changes **on this branch**.
- This is a **new 2D prototype**, not an overhaul of the full existing fishing and romance systems. The underwater friendship and shore reveal are implemented locally in the new scene, rather than saved or integrated into the existing town NPC manager.
- Wild fish have simple wandering/fleeing behaviors and disappear when caught. There's no resource economy, complex net physics, or boss combat yet.
- Silas follows, reacts to exploring, can conceal you, and has a small dialogue/trust progression. His actual underwater sprite is the garden eel; his above-water sprite is his existing humanoid idle art.
- Visual backgrounds are deliberately rough built-in shapes, with existing sprites for characters and fish. This is a test of *feel*, not final art.
- The full Godot engine was **not available** in the editing environment, so the scene and test have **not been runtime-verified**. Playtest locally before deciding whether to merge.

## Technical test

From the `hook,-line,-and-sinker` project folder:

```bash
godot --headless --path . -s res://tests/diving_prototype_test.gd
```

The test instantiates the alternate scene, checks nearby capture, conversation, net clearing, following, concealment, and the surface transformation.

If you prefer to open the original game on this branch, run `res://scenes/main.tscn` manually in the editor; the normal game scenes/assets are preserved.
