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
| Interact (talk / shop) | Space |
| Choose bait | Click a bait button (top-left) before casting |

## What's implemented

- **Managers (autoloads):** `GameManager` (time of day, actions per day),
  `FishingManager` (catch pool, storage, casts per session), `NPCManager`
  (attraction and flags per NPC, picks dialogue by flag rules), `DialogueManager`,
  `ShopManager` (trades fish from storage for `FishingManager` upgrades).
- **Data as Resources:** items, fish, NPCs, flags, dialogue rules/lines/choices,
  trades. Instances are in `resources/`.
- **Bait (prototype):** `BaitData` resources (`resources/bait/`) give each fish a
  relative catch weight by `fish_id`. `FishingManager.get_random_catch()` uses the
  equipped bait's weights; this is the only place a cast's species is chosen.
  Changing bait affects the next cast, never a fish already decided. Bait A / B
  favor Placeholder Fish A / B at 75 / 25, and both fish stay catchable. An empty
  or malformed catch pool ends the cast instead of crashing.
- **UI:** visual-novel style dialogue UI, shop menu, interact prompt, placeholder
  bait selector.
- **Player** movement on the dock, plus interactables for NPCs and the shop.

Not yet built (planned or exploratory): bait stock/shop, time/weather odds, fishing journal, challenge-
unlocked gear, corporate storage/delivery, fish-person recruitment, houses.

## Project structure

```
hook,-line,-and-sinker/
  scenes/      main.tscn, dock, manager scenes
  prefabs/     player, world, dock, shop, test_npc, dialogue_ui, shop_menu,
               interact_prompt, bait_selector
  scripts/     managers, player, interactables, UI scripts
  resources/   Resource classes (*.gd) and data (*.tres in fish/, items/, npcs/,
               trades/, bait/)
  sprites/     placeholders/ — temporary art (fish_a.png / fish_b.png are
               tinted fish placeholders)
  tests/       headless debug tests (see below)
```

### Tests

Bait odds check (simulates 20,000 draws per bait and checks empty/malformed pools):

```
cd hook,-line,-and-sinker
godot --headless --path . -s res://tests/bait_odds_test.gd
```

Exits with code 1 if a check fails.

## Workflow

- Work on your personal branch (`penni`, `ethan`, `jerry`, …).
- Before starting a new task, merge the latest `main` into your branch.
- Talk to the team before changing shared scripts (managers, resources).
- Open a pull request into `main` for review.
- Placeholder art and standalone test scenes are welcome. Put art in
  `sprites/placeholders/`.
- If you use local editor plugins, don't commit their lines in `project.godot`.
