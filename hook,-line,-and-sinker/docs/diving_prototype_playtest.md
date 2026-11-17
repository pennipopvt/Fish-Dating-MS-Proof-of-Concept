# Diving prototype — integrated island playtest

This experimental work is on the **`diving` branch**, based on `main`. **Nothing was merged into main or revised-fishing.**

## Start from the normal island

Run the Godot project normally (`res://scenes/main.tscn`). The original island, dock, houses, shop, day/night cycle and terminal are still present. Walk to the **fishing dock on the left** and interact exactly as you used to start fishing.

Instead of casting, **Penni jumps from the dock into the water**. A black circular iris closes around the splash, changes scenes once the screen goes black, then opens around Penni underwater. When you return to the surface marker, a matching iris closes on Penni and reopens back on the actual island. Both scenes use the same **320×180 native pixel viewport, scaled 6×**.

The lagoon is kept alive between dives so the fish you've caught and Silas's conversations/following progress don't reset each time. A dive costs one world time action when you return, rather than one action per fish caught.

## What to do underwater

1. **Move in four directions** with WASD / arrows. The lagoon is larger than the viewport and the camera follows you.
2. Approach an ordinary fish and **left-click near it** to throw a net and catch it. Fish wander and flee from your approach. Captures are recorded in the normal FishingManager's storage, dex and challenge systems.
3. Swim **east** to the garden eel near his burrow; press **E** to discover that he can talk.
4. Swim beside the **tangled net** near the burrow and **left-click** to untangle it. Silas introduces himself and starts following you.
5. Swim with Silas, talk to him, catch more fish, and explore the **glowing shell garden** farther east. Press **Q** to ask him to conceal you for five seconds so wild fish don't flee as easily.
6. When you're ready, return to the illuminated **surface marker** near the start and press **E**. Silas only asks to join you on land once you've gotten to know him. Use the **normal dialogue choice buttons** to invite him or stay together underwater.
7. If you invite him, the iris brings you back to the **original island dock**, where Silas appears as a human in a little poof animation. His portrait switches from the **fish sprite underwater** to the **human portrait on land**; the existing dialogue interface and NPC recruitment / housing systems handle his life on land.

### Controls

| Input | Meaning |
| --- | --- |
| Overworld movement | A / D as before |
| Dock interact | Space / left-click in the original world |
| Underwater WASD / arrow keys | Swim freely in four directions |
| Underwater left-click | Catch a fish within reach, or clear Silas's net |
| Underwater E / Space | Talk, advance the standard dialogue UI or interact with the surface marker |
| Q | Silas conceals you once he joins you |
| Dialogue choice buttons | Invite Silas to land or postpone, using the same UI as land conversations |

## Implementation notes

- Existing `scenes/main.tscn` is the entry scene again. `scenes/diving_prototype.tscn` now lives inside its own canvas layer and can still be opened separately for isolated underwater testing.
- The transition is a reusable aspect-correct circular iris shader, not a generic crossfade.
- The underwater SubViewport now matches the overworld exactly: `320×180` pixels with `stretch_shrink = 6` and nearest-neighbor sprite rendering.
- **All underwater conversations use the existing `DialogueManager` and `DialogueUI`**. The temporary local dialogue panel was deleted. Dialogue text, speaker-name formatting, narration, selection buttons, and advancement are the normal game’s systems.
- In the water, NPCs display their **fish sprites** (Silas as a garden eel; Kuda as a barracuda) rather than the human portraits. Penni also uses her normal pixel-world idle sprite instead of portrait artwork. Sprite framing and high-resolution dialogue layout return to normal when surfacing.
- The initial "???" identity clue and first-land transformation are preserved. Silas's invitation is a regular selectable dialogue choice, not a hardcoded number-key menu. Underwater chat uses free inline dialogue graphs so it does not spend an extra clock action.
- The overworld Player is busy during a dive so inputs do not trigger fishing or NPC interactions underneath the underwater view.
- One net capture contributes to the existing catch/storage/collection systems without spending another action. The action clock advances when you leave the water.
- Silas's dive-specific friendship state persists in the lagoon instance while the game is running. On his first visit ashore, a custom first-land conversation runs in the original game's DialogueUI; afterward he joins the usual town NPC/housing flow.
- The original bait/bobber items and existing fishing controller still exist in the repository. They're not used by the **dock's new diving path**. This experiment does not yet rebalance the old upgrades for underwater net-catching.
- This is a feel-test of space, proximity and companionship. The net has no complex physics or combat timing yet.

## Verification

Check the new integrated flow with:

```bash
godot --headless --path . -s res://tests/diving_island_transition_test.gd
godot --headless --path . -s res://tests/diving_prototype_test.gd
```

**The tests have been added but not executed in this editing environment, which has no Godot binary.** Please run the project in Godot and report any script/parser warnings or visual issues so they can be corrected before merging.
