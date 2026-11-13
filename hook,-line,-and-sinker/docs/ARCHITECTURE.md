# Hook, Line, and Sinker — Architecture

This is the current **Godot 4** prototype architecture. Keep new features aligned
with these ownership rules to avoid changing the same gameplay state in several
scripts. For the current prototype, gameplay progression is **session-only**.

## Runtime flow

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

- Work on `penni`; **do not push to `main` without explicit approval**.
- Keep data in typed `.tres` resources, not hard-coded scene paths.
- Don't mutate an autoload's arrays/flags from UI when an API can own it.
- Pair every state-machine change with at least one test.
- Add a signal when state changes; don't make UI poll or infer it indirectly.
- Prefer small behavior-preserving changes over large system rewrites.
