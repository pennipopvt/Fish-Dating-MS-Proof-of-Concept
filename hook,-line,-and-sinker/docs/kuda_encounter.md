# Kuda's first hunt (second diving companion)

## Editable placement
The `KudaEncounter` node is an instance of `res://scenes/sea_kuda_encounter.tscn`, placed in `sea_area.tscn` around the open water area. Its translucent orange rectangle is **editor-only**. Drag its origin and edit **Area Size** in the Inspector to keep the chase away from rocks.

The same Inspector exposes:
- **Kuda Species** (existing `resources/fish/kuda.tres`), **Prey Species** (initially mullet), and **Initial Health Ratio** (0.5 by default)
- Prey Speed, Kuda Speed, Burst Speed, Burst Interval, Burst Seconds, Bite Range, Bite Damage
- Shout Range, Shout Cooldown, and Shout Text

Kuda and prey use the standard `DivingWildFish` actor and registry, with the existing spline open-water collision test. No collision/terrain artwork is modified.

## Story and combat
- Only activates on dives **after** Silas's first shore transformation, and only if Kuda is not yet recruited.
- While within shout range, Kuda occasionally speaks using the existing attached `SeaSpeechBubble`.
- Right-clicking either Kuda **or his hunted prey** makes Silas refuse to interfere. The full dialogue occurs only once; further attempts show a short line.
- The first net hit on Kuda pauses for `res://dialogue/kuda_net_hook.json`, then starts ordinary `DivingCombat` using Kuda's actual Quick Strike/Feint states and 50% HP.
- Releasing/losing the catch resumes Kuda's chase. The second and later net hits **skip** the first-hook dialogue.
- Successful reeling **does not** award a fish item. Instead `res://dialogue/kuda_underwater_caught.json` plays, marking the NPC Recruited after the conversation ends.
- `SeaDiveTransition` adds Kuda to the existing `DivingParty` and immediately creates `NPCs/PartyFish_barracuda`. Kuda can swim back with Penni and Silas via the ordinary shared surface animation.
- Leaving the sea removes unrecruited encounter actors. The next dive may try again; a recruited Kuda never returns as a wild target.

The multiplayer / multi-target right-click **combat queue** and Kuda's lethal companion behavior are the *next* stage. This introduction does not replace the existing Silas combat actor.

## Ownership
- `SeaKudaEncounter`: authored hunting bounds, fish movement, dialogue handoff, and chasing state
- `SeaStoryDirector`: one-time flags, Silas's refusal, Kuda's dialogue states
- `DivingWorld`: existing wild fish, net, combat and party follower registration
- `SeaDiveTransition` + `DivingParty`: roster and swim-to-shore transition

## Chase/retry reliability
- Kuda replaces caught or killed prey after a short delay, even if he currently has no target. The World always updates the encounter while no ordinary fishing combat is active.
- Kuda and prey have their own sprite widths in the KudaEncounter Inspector (44 px and 26 px by default). Net collision automatically respects an enlarged fish's capture radius.
- Kuda's temporary catch cooldown advances during the special chase; after an escape, he can be netted again instead of becoming permanently immune.

## Chase steering
Kuda now has a committed **Attack Pass** (distance and duration in the encounter Inspector). When close to his prey, he continues through it before turning around instead of snapping direction whenever their positions overlap. Both fish use smooth turn-response values, and the prey steers back into the hunting rectangle at its edges. The scene's movement and combat layers are unchanged.
