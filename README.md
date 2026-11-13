# Fish Dating — MS Proof of Concept

Working title **Hook, Line, and Sinker** · NYU Major Studio · Fall 2026
Team: Penni, Ethan, Jerry, Jenny

A cozy and strange side-scrolling fishing collection game. Learn fish habits,
target species with bait/time/gear, master tension-based reeling, and meet fish
people who might settle in your empty town.

> Design is in active discussion. The team design doc (Overview / Build Plan /
> Systems) is the source of truth. This README describes what is **in the repo**.

## Getting started

1. Install **Godot 4.7** (standard build).
2. Clone the repo and open `hook,-line,-and-sinker/project.godot` in Godot.
3. Press **F5** to run `scenes/main.tscn`.

### Controls

| Action | Input |
|---|---|
| Move left / right | A / D |
| Reel | Mouse wheel |
| Interact (talk / shop / bait box) | Space |
| Close menu | Esc |

Debug builds only (not in exports):

| Action | Input |
|---|---|
| Dev panel | F9 |
| Clock overlay (day, period, actions left; play continues) | F3 |
| End current dialogue | F5 |
| Recruit Silas (skip his first talk) | F6 |
| Preview challenge popup | F10 |

**Dev panel (F9)** (`prefabs/dev_panel.tscn`, autoload `DevPanel`). Tabs:
- **Info:** live state in four subtabs.
  - **World:** time, player, dialogue node, date bookings, recruitment.
  - **NPCs:** flags, attraction, next encounter.
  - **Fishing:** cast state, storage, catch dex, bobbers.
  - **Progress:** upgrades, challenges.
- **Talk:** Silas story checkpoints, which set flags, spawn him and open the talk; or play any `dialogue/*.json`. **Dates:** "Ask Silas out" opens the ask-out talk (the only way to trigger it for now); per date, "Accept" does what saying yes does and "Start here now" runs the date right away; plus a reset for bookings and done/missed flags. Day clock: spend 1 action, or rest (same as the bed).
- **Items:** put any item in your hands or storage.
- **Progress:** complete or reset challenges, grant or reset upgrades, reset everything.
- **Flags:** edit flags and attraction.
- **Fishing:** instant bite or catch, force a species, cast counts, unlock or equip bobbers, equip bait.

**F3** toggles a small clock overlay in the top-left (its own CanvasLayer, so it stays up while the panel is closed and doesn't pause play).

"Reset ALL" resets this session's progress and reloads the world. The panel uses the shared `PixelUI` theme (`scripts/ui/pixel_ui.gd`).

## What's implemented

- **Managers (autoloads):** `GameManager` (day clock, see below),
  `FishingManager` (catch pool, storage, casts per session), `NPCManager`
  (attraction and flags per NPC, picks dialogue by flag rules), `DialogueManager`,
  `ShopManager` (trades fish from storage for `FishingManager` upgrades).
- **Data as Resources:** items, fish, NPCs, flags, dialogue rules/lines/choices,
  trades. Instances are in `resources/`.
- **Bait (prototype):** `BaitData` resources (`resources/bait/`) give each fish a
  relative catch weight by `fish_id`. `FishingManager.get_random_catch()` uses the
  equipped bait's weights; this is the only place a cast's species is chosen.
  Changing bait affects the next cast, never a fish already decided. Bait A / B
  favor Placeholder Fish A / B at 75 / 25, and both fish stay catchable. Pick bait at
  the bait box on the ground: a 3x3 grid of baits on the left, and the selected
  bait's description and chance per fish on the right. Bait A / B, their icons
  and the bait box sprite are placeholders. An empty
  or malformed catch pool ends the cast instead of crashing.
- **Day clock (no display yet):** `GameManager` tracks `day` and `time_of_day`
  (morning, afternoon, night). Each period has 3 actions (`ACTIONS_PER_PERIOD`).
  A finished cast (caught or lost) and a finished NPC conversation each cost 1
  action. Menus (shop, bait, bobbers) cost nothing. Spending a period's last action
  moves to the next period. When night's actions are spent, fishing and starting a
  talk are blocked (the current fishing session stops recasting) until the player
  rests. **Bed** (`prefabs/bed.tscn`, a blank placeholder box right of the houses):
  `GameManager.rest()` skips to the next period with fresh actions (night → next
  day's morning). It's free and works any time, with no real-time timer.
  **Reading the clock:** shop/delivery rules, fish availability and NPC availability
  should call `GameManager.get_day()`, `get_period()`, `is_period(GameManager.Times.NIGHT)`,
  `get_period_name()`, `get_actions_left()`, or listen to `time_changed`. Values are
  already updated when signals fire. There's no event scheduler.
  **Saving:** the clock (day, period, actions left) is written to `user://save.cfg`
  (section `clock`) on every change and loaded on start, so a new run continues
  where the last one stopped. `get_save_data()` / `load_save_data()` are there for a
  future game-wide save. Dev panel "Reset ALL" puts it back to day 1 morning. Other activities
  (for example a future NPC hangout) can cost time with `GameManager.spend_actions(n)`.
  Interactables that cost time return `true` from `spends_time()`. The recruitment
  talk right after catching an NPC fish always happens, even at the end of night.
- **Dates (prototype, Silas only):** `DateManager` autoload + `DateData` resources
  in `resources/dates/` (one `.tres` per date, loaded automatically). Each date sets
  its NPC, place (`location_id`), dialogue JSON, **periods** it can happen in (none
  ticked = any time), and **when**: `NOW` starts right after the NPC says yes
  (with `jump_clock` on, the clock skips forward to the next allowed period, like
  resting; off, the date can only be asked for during an allowed period) or
  `SCHEDULED` books the next allowed period (`days_ahead` pushes it to later days),
  and Penni has to show up at the place during that period and interact with it.
  A missed booking sets `date_missed_<id>`. Requirements: `required_flags`,
  `forbidden_flags`, optional min attraction, `repeatable`. Result: sets
  `date_done_<id>` (or `completed_flag`), `flags_to_set`, `attraction_change`, and
  `extra_action_cost` on top of the 1 action every talk costs.
  **Asking out:** `dialogue/silas_ask_out.json` (dev panel only for now). Each choice
  is shown only when the flag `date_ok_<id>` is on (DateManager sets these when any
  conversation starts) and requests the scene `date:<id>`. When no date is available,
  the talk follows its `next` to a "not now" line.
  **The date:** fade out, Penni and the NPC move to the place's `PlayerSpot` /
  `NpcSpot`, the date JSON plays, then fade back and both return. Places are
  `DateLocation` interactables (`prefabs/beach.tscn`, a yellow triangle right of the
  bed; `prefabs/ship.tscn`, an upside-down triangle on the water past the beach);
  a booked place shows a sign with the date and time. Current data: beach =
  NOW, afternoon only (jumps the clock); ship = SCHEDULED, night. All lines are
  TODO placeholders. Bookings and flags live in memory only.
- **UI:** visual-novel style dialogue UI, shop menu, bait menu, interact prompt.
- **Player** movement on the dock, plus interactables for NPCs and the shop.
- **Fishing rod (visual only):** `prefabs/fishing_rod.tscn` on the player. When you
  start fishing, the player faces the water and pulls out the rod. Every cast swings
  the rod back and flicks it forward, and the equipped bait's icon flies out on the
  end of the line along a parabola, lands where the bobber floats, and sinks along
  the underwater line. The reel spins while you scroll,
  and the line stays attached to the fish as it flies out of the water.
  `fishing_rod.gd` only listens to `FishingController.state_changed`; timings and
  angles are exported on the FishingRod node.

### How systems connect (signals)

Managers emit signals; other systems and UI connect to them in `_ready`. A manager
never drives another system's nodes directly. Reading a manager's state for display
(`ShopManager.can_trade`, `ChallengeManager.is_trade_locked`) is still a plain call.

| Signal | Emitted by | Listened to by |
|---|---|---|
| `fish_caught` / `fish_lost` / `parry_resolved` | `FishingManager` | `ChallengeManager` (progress), shop menu (collection) |
| `storage_changed` | `FishingManager` (`add_to_storage`, `remove_from_storage`, catches) | shop menu, storage panel |
| `challenge_completed` / `challenge_preview_requested` | `ChallengeManager` | `ChallengeToast` (notice above the terminal and unlock sound) |
| `challenge_progressed` / `progress_reset` | `ChallengeManager` | shop menu, challenges panel |
| `delivery_requested(pickups)` | `ShopManager.make_trade` | the shop terminal (`ShopInteractable`), which sends the drone |
| `upgrade_state_changed` | `ShopManager.collect_upgrade` (upgrade package picked up) | shop menu |
| `state_changed(from, to)` | `FishingController` | `FishingRod` (deferred) |
| `fish_caught` / `fish_lost`, `conversation_finished` | `FishingManager`, `DialogueManager` | `GameManager` (spends 1 action) |
| `time_changed(day, time)` / `day_started(day)` / `actions_changed(remaining)` / `actions_exhausted` | `GameManager` | `DateManager` (expires missed bookings), `DateLocation` signs |
| `scene_requested(npc, "date:<id>")` | `DialogueManager` (JSON effect `request_scene`) | `DateManager` (starts or books the date) |
| `date_booked` / `date_started` / `date_finished` / `date_missed` / `bookings_changed` | `DateManager` | `DateLocation` (`bookings_changed`); the rest are for future UI |

Change storage only through `FishingManager.add_to_storage` / `remove_from_storage`,
so listeners hear about it. With no terminal in the scene (nobody listening to
`delivery_requested`), trade rewards apply right away.

Not yet built (planned or exploratory): bait stock/shop, time/weather odds, fishing journal, challenge-
unlocked gear, corporate storage/delivery, fish-person recruitment, houses.

## Project structure

```
hook,-line,-and-sinker/
  scenes/      main.tscn, dock, manager scenes
  prefabs/     player, world, dock, shop, test_npc, dialogue_ui, shop_menu,
               interact_prompt, bait_box, bait_menu, fishing_rod, dev_panel,
               beach, ship (date places)
  scripts/     managers, player, interactables, UI scripts
  resources/   Resource classes (*.gd) and data (*.tres in fish/, items/, npcs/,
               trades/, bait/, dates/)
  sprites/     placeholders/ — temporary art (fish_a/b.png tinted fish,
               bait_a/b.png bait icons, bait_box.png)
  tests/       headless debug tests (see below)
```

### Tests

Bait odds check (simulates 20,000 draws per bait and checks empty/malformed pools):

```
cd hook,-line,-and-sinker
godot --headless --path . -s res://tests/bait_odds_test.gd
```

Exits with code 1 if a check fails.

Day clock check (period advancement, night block, bed, rollover, listeners reading
the new values, save round trip). It uses autoloads, so it runs as a scene and
writes only to `user://day_clock_test.cfg`:

```
godot --headless --path . res://tests/day_clock_test.tscn
```

## Workflow

- Work on your personal branch (`penni`, `ethan`, `jerry`, …).
- Before starting a new task, merge the latest `main` into your branch.
- Talk to the team before changing shared scripts (managers, resources).
- Open a pull request into `main` for review.
- Placeholder art and standalone test scenes are welcome. Put art in
  `sprites/placeholders/`.
- If you use local editor plugins, don't commit their lines in `project.godot`.
