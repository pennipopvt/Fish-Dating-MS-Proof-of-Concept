# Hook, Line, and Sinker — Architecture

This documents the established island prototype plus the newer underwater
first-dive prototype on **penni-diving**. The fishing dock architecture below
is largely legacy; the sea uses separate combat components while sharing the
same persistent World, Player, Camera, dialogue and managers.

Keep new features aligned
with these ownership rules to avoid changing the same gameplay state in several
scripts. For the current prototype, gameplay progression is **session-only**.

## Actual scene tree and viewport ownership

```text
Main (Control, scripts/main_controller.gd)
├── SubViewportContainer (stretch_shrink=6)
│   └── SubViewport (native 320×180)
│       ├── World (prefabs/world.tscn)
│       │   ├── Player (CharacterBody2D; owns Camera2D, underwater tint)
│       │   ├── Sky / Water / Dock / Shop / island systems
│       │   └── Sea (scenes/sea_area.tscn)
│       │       ├── Solids / FishSpawns / FishActors / NPCs/Silas
│       │       ├── StoryDirector (first-dive event flags)
│       │       ├── NetProjectile / Combat / CompanionBattle
│       │       └── editor guide / entry and exit markers
├── CanvasLayer (ShopMenu, DialogueUI which uses layer 10)
├── SeaSpeechBubble (CanvasLayer, layer 8; pixel-scaled to game)
├── IllustrationScene
├── IntroLayer (FishCoIntro backdrop, layer 9)
└── TransitionLayer (iris, layer 100)
```

**Important:** `SeaSpeechBubble` lives directly under `Main`, on the
screen UI layer that previously rendered reliably. Its `CanvasLayer.scale`
and `offset` are computed from the game's `SubViewportContainer` rect,
so its drawing coordinates remain **320×180 native game pixels**, despite
being hosted in the main viewport. Find it from the sea with
`get_viewport().get_parent().get_parent().get_node_or_null("SeaSpeechBubble")`
(or equivalent null-safe traversal). Map Silas using
`get_global_transform_with_canvas()` from his game SubViewport and clamp
against the 320×180 virtual game size. The one nine-slice + tail retains
the original user-supplied art. Do not add a duplicate bubble or attach
a scripted UI node directly to the camera.

`Main/dive_entry.gd` owns island ↔ sea transitions and forwards input
into `DivingWorld.handle_input`, because the SubViewportContainer may
consume mouse events. `World` and the same Player/Camera continue to exist
during dives; the sea is **not** a second loaded world. Player movement and
collision remain owned by `Player.set_swimming()` and `move_and_slide()`.

`DivingWorld` should coordinate sea encounters and projectiles but not own
narrative flags. `SeaStoryDirector` holds first-dive session beats, then
requests dialogue via `DialogueManager`; NPC flags are stored with
`NPCManager`. `SeaNPC` is the editor-placeable physical actor, with
the existing `NPCData` resource controlling its fish/human representation.
The temporary catch target is not a second visible NPC.

For the opening sequence, the initial mullet is intentionally scripted:
WASD cue → fish focus / click cue → net → forced line break → escaped fish
swims left → Penni follows → persistent attached "Help me!" call → Silas
dialogue → rescue → companion tutorial. A **story event must not be
considered delivered until its UI target is available**, or the bubble
may silently disappear for the rest of the session.

## Runtime flow (existing island fishing)


1. `Player` interacts with `Dock` and `FishingController` starts a cast.
2. `FishingManager` selects a fish using the equipped `BaitData`.
3. `FishingController` runs parry/tension/progress combat; `FishingLine`
   handles line, fish sprite, bobber, and ripple presentation.
4. Catch/loss events go through `FishingManager` signals and reach
   `ChallengeManager`. Ordinary fish go into storage.
5. Caught NPC fish become `NPCInteractable` scenes; initial dialogue is
   coordinated by `DialogueManager`, with flags held by `NPCManager`.
6. `RecruitmentHandler` removes accepted NPCs from future catches and places
   them in **first-come, first-served** housing. If the houses are full, accepted
   NPCs wait by the dock and are automatically moved into the next free house.
   **Declined** NPCs disappear from the world and remain catchable.
7. `ShopManager` validates trades, deducts items, records pending upgrades,
   and asks the scene's `ShopInteractable` to deliver pickups.
8. Picking up an upgrade calls its `FishingManager.shop_reward_*` method;
   picking up a gift places it in the player's hand.

## State ownership

| State | Authoritative owner | Other systems should do |
| --- | --- | --- |
| Fish pool, catches, bait, storage, fishing upgrades | `FishingManager` | Call methods or respond to signals |
| Trade validity, purchases, uncollected upgrade IDs | `ShopManager` | Call `make_trade`, `mark_upgrade_delivered` |
| Physical delivery packages and drone animations | `ShopInteractable`, `DeliveryDrone` | Never treat them as saved purchase records |
| Challenge progression/unlocks | `ChallengeManager` | Listen for progress/complete signals |
| NPC flags, attraction, encounter selection, gifts | `NPCManager` | Request flag/effect changes, avoid writing flags from UI |
| Current conversation and dialogue graph | `DialogueManager` | Use request/start/end APIs |
| NPC housing queue and temporary placement | `RecruitmentHandler` | Send caught actor + FishData to `engage_listen`; register vacated/new houses via `register_available_home` |
| Bobber unlocks/equipment | `BobberManager` | Use unlock/equip methods |
| Scene presentation, optional encounter transitions | `IllustrationSceneController` | Avoid owning long-lived NPC progression |
| Modal input lock | `GameManager` | Add appropriate UI nodes to `modal_ui` |

### Common signals

- `FishingManager.fish_hooked / fish_caught / fish_lost / parry_resolved`
- `FishingManager.bait_changed / upgrades_changed`
- `ChallengeManager.challenge_progressed / challenge_completed`
- `DialogueManager.conversation_started / conversation_finished / scene_requested`
- `ShopManager.trade_completed / upgrade_state_changed / shop_opened / shop_closed`
- `RecruitmentHandler.npc_waiting_for_home / npc_moved_into_home`
- `BobberManager.collection_changed / equipped_changed`

### Known limitations and next refactor candidates

- Physical **uncollected upgrade** packages are recreated when a world scene
  reloads during the same session. Gift item pickups are still not tracked
  as orders after being dropped; rebuilding their delivery history is a
  separate change.
- Accepted NPCs wait near the dock when the village is full. New or
  vacated houses must be registered with `RecruitmentHandler.register_available_home(home)`;
  the queue is served automatically in arrival order. The world initially
  registers its empty houses with `set_available_homes(homes)`.
  **Only re-register a house after its prior resident has actually moved out.**
  NPCs do not persist across application restarts; saving their houses/queue
  is a future feature.
- NPC state and cosmetics are currently intertwined through Silas-specific
  flags. A future NPC progression API can provide one owner for route rewards.
- `FishingController` mixes combat with catch presentation. Extract the
  animation and NPC spawn sequence **after** adding full-flow tests.
- `ShopMenu` contains several tabs' presentation in one script. Extract
  the tabs without changing `ShopManager` ownership.
- Dialogue uses both JSON graph and legacy resource formats. Migrate only
  after identifying all consumers.

## Regression tests

Run from `hook,-line,-and-sinker/`:

```bash
godot --headless --path . -s res://tests/first_arc_upgrades_test.gd
godot --headless --path . -s res://tests/recruitment_pool_test.gd
godot --headless --path . -s res://tests/delivery_recovery_test.gd
```

There are additional `res://tests/*_test.gd` scripts for catch odds,
combat, bobber rewards, shop gifts, and Silas visuals. Run a smoke test of
catching/declining/recruiting Silas, collecting drone packages, and opening
each terminal tab before declaring a gameplay refactor complete.

## Editing guidelines

- Work only on `penni-diving` for underwater changes; **do not modify `main` or backup branches** without explicit approval.
- Keep data in typed `.tres` resources, not hard-coded scene paths.
- Don't mutate an autoload's arrays/flags from UI when an API can own it.
- Pair every state-machine change with at least one test.
- Add a signal when state changes; don't make UI poll or infer it indirectly.
- Prefer small behavior-preserving changes over large system rewrites.

## Underwater regression checks

Run `res://tests/sea_storyboard_test.gd`,
`res://tests/sea_level_layout_test.gd` and
`res://tests/diving_island_transition_test.gd` from Godot's headless
SceneTree runner before merging. The environment running this analysis
cannot currently execute Godot; static references alone do not verify
the rendering or real-game playback.

## Speech visibility regression fix

The attempt to move `SeaSpeechBubble` into the 320×180 `SubViewport`
caused it to disappear in user playtests. This change restores the last
working Main-level CanvasLayer and applies display-relative pixel scaling.
The `help_called` story flag is set only after `is_call_shown()` confirms
the rendered bubble controls were made visible; otherwise the story event
continues retrying rather than being silently lost. The hint uses fixed
native-game coordinates instead of main-window anchors.


## November speech bubble regression: safe baseline

Silas's original "Help me!" popup was visible when its CanvasLayer was a
direct child of Main, with a 340x100 Control measured in outer UI pixels.
Moving the CanvasLayer into the game SubViewport caused the bubble to
disappear; applying a dynamic CanvasLayer.scale/offset was not verified
by an in-engine test. We have now restored the last visibly working
rendering arrangement (CanvasLayer on Main, unscaled bubble and text),
but retain the user's supplied white 9-slice artwork and separate
rotatable tail. Only the Silas anchor point is projected through the
SubViewportContainer's global display rect.

Story beats have two paths: the intended initial fish escape followed by
swimming left, or a near-Silas recovery trigger when the player reaches
the eel without completing the first fish tutorial. This prevents a
reached Silas from remaining silent. The renderer's is_call_shown() is
checked before marking help_called; it must not be a hidden/failed event.

Do not change viewport ownership or pixel scaling again without an
actual Godot runtime test. First ensure the story beat and bubble draw
are reliable. Tuning pixel art scale can be done after that.

## Silas bubble ownership wiring (confirmed branch constraint)

`SeaStoryDirector` is a descendant of `World` inside the game
`SubViewport`, but `SeaSpeechBubble` is a sibling of
`SubViewportContainer` in the outer `Main` scene. It should not try
to discover the screen UI by guessing the parent chain of
`get_viewport()`. At `Main._ready()`, obtain the exact instance at
`Main/SeaSpeechBubble` and call
`Sea/StoryDirector.bind_speech_bubble(speech)`.
The director uses that explicit reference for all its messages.
The historical `sea_speech_bubble` scene group is only a
fallback for standalone use. The renderer and the user's bubble/tail
textures were not changed as part of this wiring repair.


## Native-pixel voice and physical companion battle

The initial Silas cry uses **one** `SeaSpeechBubble` CanvasLayer owned
by `Main`. The startup recovery in `Main._ensure_sea_speech_bubble()`
must not be removed: it resolved a real user's missing-UI instance.
The outer CanvasLayer is scaled and offset to match the
`SubViewportContainer`'s 320×180 game image, so **12 native-pixel
Pixel Operator text** and the user's 32px nine-slice art share Penni's
pixel grid. No bubble node is moved inside the SubViewport. The text
reveals character by character; the nine-slice grows from the width
of visible letters. For the first cry, it holds, fades, waits, and repeats
until the player interacts with Silas. The story's `_help_ui_pending`
checks `is_call_active()`, **not** `is_call_shown()`, so the intended
gap between repeated cries does not cause premature restarts.
A later timed companion hint is one-shot.

`DivingCompanionBattle` remains the existing `main` combat authority
for species stats, HP, attack timers, exhaustion, recall, and signals.
The reusable `SeaNPC` now owns **only** companion movement, sprite
orientation/lunge and hit-flash presentation, chasing the battle target
as on `main` instead of always following Penni.
`DivingWorld` coordinates right-click target selection, listens for
battle signals, and passes `SeaNPC.can_strike_target()` to
`CompanionBattle.step(delta, in_attack_range)`. While approaching,
battle timers do not advance and no contact damage is applied.
This avoids a second combat loop or duplicating NPC stats.

F7 now includes the bubble's reveal phase, animation size/scale,
Silas following state, battle/target HP, movement state and attack-range
readiness, and last right-click outcome. Output logs tag encounter events
with `[SEA STORY]` and combat transitions/hits with `[SEA COMBAT]`.
The F7+B isolated bubble test remains available; F8 remains Godot Stop.


## Sea / Main refactor: ownership map (November 2026)

The previous `scripts/main_controller.gd` reached **694 lines** and
mixed gameplay transitions, Fish Co onboarding dialogue, UI recovery,
and debugging. It is now a **78-line Main coordinator**, not the
owner of those systems. The scene still uses **one** `World`,
`Player`, `Camera2D`, `SubViewport`, `DialogueUI` and
`ShopMenu`. We did **not** create new global singletons.

| Scene node | Script | Owns |
|---|---|---|
| `Main` | `scripts/main_controller.gd` | Dependency wiring, the stable `request_dive(player,dock)` API used by `Dock`, and one input forwarding boundary |
| `Main/IntroLayer` | `fish_co_opening_sequence.gd` | Fish Co opening/second phone call, first terminal visit, dock Yes/No confirmation, one-time onboarding flags |
| `Main/TransitionLayer` | `sea_dive_transition.gd` | Iris, jump/splash, sea entry/surfacing, return position, movement locks, underwater mode |
| `Main/SeaSpeechBubbleHost` | `sea_speech_bubble_host.gd` | Binding/recovering the **editable** `Main/SeaSpeechBubble` if the original scene is unavailable |
| `Main/SeaSpeechBubble` | `sea_speech_bubble.gd` | Existing animated Pixel Operator message, nine-slice and circle marker; edits in its own `.tscn` |
| `Main/SeaDebugLayer` | `sea_debug_panel.gd` | F7, B bubble test, the authored diagnostic panel, and Skip Dialogue |
| `World/Sea` | `diving_world.gd` | Existing local sea world orchestration; still coordinates fish spawns, net input and tutorial targets |
| `World/Sea/StoryDirector` | `sea_story_director.gd` | One-time encounter/story flags and Silas's introduction/rescue dialogue |
| `World/Sea/Combat` | `diving_combat.gd` | Existing fishing reel/tension/parry combat, species attack timing |
| `World/Sea/CompanionBattle` | `companion_battle.gd` | Existing companion health/attack simulation |
| `World/Sea/NPCs/Silas` | `sea_npc.gd` | Silas's visuals and physical approach/attack presentation |

**Call sequence:** Dock invokes `Main.request_dive` → IntroLayer
decides whether the story allows it → `dive_confirmed(dock)`
signal → TransitionLayer animates the *same* Player into the
existing Sea. Surfacing uses `Sea.surface_requested` →
TransitionLayer. The speech-bubble host injects the exact Main UI
instance into StoryDirector. Debug reads state but doesn't own it.

**Rules for future work:**
- Do not add fishing, Fish Co dialogue, or UI drawing logic to
  `dive_entry.gd`. Add code to its existing owner instead.
- Do not create another `Player`, `GameManager`, `DialogueManager`,
  global story flags, world scene, or second combat model.
- Add repeatable fish/NPC/level tuning to editor-placeable resources
  and Inspector exports; keep one-off storyboard conditions in
  StoryDirector/sea encounter code rather than `Main`.
- No new input route except the one on `Main`; sea input is
  forwarded to `DivingWorld.handle_input` as before.
- A bugfix must identify **which owner is broken**, include an
  Output log or focused regression test, and avoid changing other
  components as collateral.

**Further cleanup candidates (not silently rewritten in this pass):**
`diving_world.gd` (612 lines: tutorial state and world routing),
`fishing_controller.gd` (legacy fishing feedback),
`shop_menu.gd` and `dev_panel.gd` (each > 45 KB).
The next gameplay task should restore reel/parry feel by working
inside `DivingCombat` and its existing feedback utilities, rather
than trying to rewrite the land fishing controller and sea fishing
simultaneously.

**Regression entry points:**
`tests/sea_architecture_boundaries_test.gd`,
`tests/diving_island_transition_test.gd`,
`tests/sea_storyboard_test.gd`,
`tests/sea_level_layout_test.gd`,
`tests/sea_companion_actor_test.gd`.
Execute from the Godot project root with `godot --headless --path . -s
res://tests/<file>.gd` (Godot 4). These remain subject to runtime
verification in an installed editor; source-level checks alone do
not prove the game plays correctly.
