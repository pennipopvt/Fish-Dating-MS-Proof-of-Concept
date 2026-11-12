# Barracuda: temporary playable route (penni only)

This is a **draft implementation**, not final character writing or art. All eight
JSON files are intentionally written so Penni can rewrite the lines and choices
with the designer without rebuilding the systems.

## Asset swap points

- **Fish (right-facing):** `sprites/fish/barracuda_placeholder.png` — a
  128×32 transparent compressed version of the mirrored supplied barracuda art.
- **NPC standing/caught:** `sprites/characters/barracuda_actor.svg`. The
  placeholder uses a single frame for both `default` and `on_caught`;
  replace `prefabs/barracuda.tscn` SpriteFrames with Jenny's animation.
- **Portrait:** `sprites/characters/barracuda_portrait.svg`.
- **Gift:** `sprites/gifts/barracuda_sunglasses.svg`. Sunglasses are a
  temporary choice: update the gift item, NPC desired_gift and trade together.
- **Optional scene:** `prefabs/illustration_scene.tscn` now displays the NPC
  portrait on its shared placeholder illustration panel. No adult art is
  included. Both show and skip continue to post-scene dialogue.

## Flow and flags

1. Barracuda joins the weighted fish pool and is easiest to catch with
   Hard Fish Bait. His attack data lives in `resources/fish/barracuda.tres`.
2. First successful catch runs `barracuda_first_catch.json`. The first
   conversation marks `barracuda_met`. Recruiting sets `Recruited`, removes
   him from the pool and moves him to an available house (or waiting dock).
3. If recruitment is declined, the actor despawns while the fish remains in
   the catch pool. The next successful catch runs
   `barracuda_second_catch.json`, with another chance to recruit.
4. Talking with empty hands runs `barracuda_casual.json`. The sun/style
   conversations set `barracuda_sun_hint` and
   `barracuda_style_hint` for reminder options.
5. Order sunglasses in the Gifts tab (currently **1 easy + 1 hard fish**,
   next-day delivery); pick them up and carry them to Barracuda. Gift dialogues
   use the existing `give_held_item` choice effect; declining keeps the item.
   Wrong gifts are consumed only if offered and provide an extra clue.
6. Correct gift sets `barracuda_sunglasses_complete`. Next talk gives
   `barracuda_invitation.json`. Declining allows trying again, accepting
   sets `barracuda_invitation_accepted` and requests `barracuda_house`.
7. The existing 18+ opt-in screen appears; Skip or Show progresses. The
   optional scene itself is currently a neutral fade-to-black placeholder.
   Post-scene dialogue plays automatically in the overworld.
8. After finishing that dialogue, `barracuda_route_complete` is set.
   There is **no cosmetic reward yet**; Silas's bobber remains unchanged.

## Testing

- Open the project in Godot and run:
  `godot --headless --path . -s res://tests/barracuda_route_test.gd`.
- F9 > Fishing > Force fish: **barracuda** (after its resource loads).
- Test both first-catch options (stay / leave). After leaving, force another
  Barracuda catch; you should get a different conversation.
- After recruiting, F9 can also supply test items; or order sunglasses in the
  terminal Gifts tab and sleep until delivery. Verify wrong gift / keep gift /
  accept correct gift / decline invitation / accept invitation / skip scene /
  show scene / post-scene flags.
- Verify Silas recruitment, gift, invitation, and bobber still work.

Note: the day clock is saved independently by GameManager, but NPC flags and
item purchases remain session-only. The new route follows that same behavior.
