# Fishing combat — temporary art and tuning

The new combat loop is **pre-windup warning → windup → attack → recovery**. 
A **close parry** allows resisted reeling; a **perfect parry** retains the
existing stun, tension relief, and free reeling. On a miss, the fish makes
exactly one 0.2-second dash away, adds tension, and can be reeled back in
as soon as the dash finishes. There is no passive or continuous attack-driven
backward movement in this version.

## Replacing the animation placeholders (no code changes)

Open `res://scenes/fishing_controller.tscn`. Select:
`FishingController / FishingLine / RippleTell`, then open **Sprite Frames** in the Inspector.

The animations are named:

| Animation | Temporary effect | Intended replacement |
| --- | --- | --- |
| `pre_windup` | your authored animation | warning ripple/line cue |
| `windup` | existing ripples (preserved) | building attack tell |
| `start_attack` | existing small splash (preserved) | one-shot attack onset |
| `attacking` | existing ripples (preserved) | looping fish-pull effect |
| `counter_close` | your authored animation | close-parry splash |
| `counter_success` | existing stun flash (preserved) | perfect-parry effect |
| `counter_fail` | your authored animation | failed-parry effect |
| `stun` | existing ripple (preserved) | stunned water effect |
| `idle` | existing calm water ripples (preserved) | recovery effect |

The animation frames remain editable under these names. Continue using
**32×32 art-pixel frames** with transparent backgrounds, and keep the
animation names unchanged. `start_attack`, `counter_close`, `counter_fail`, and
`counter_success` should be **non-looping**; `pre_windup`, `attacking`,
`stun`, and `idle` may loop.

Ripple animations use their own authored colors, with no extra tint. The
existing line color still reflects line tension (and stun) but does not change
color just because pre-windup begins.

Do **not** draw a visible fish sprite for in-combat attacks: the fish stays
beneath the opaque water; water/line/ripple effects do the telegraphing.

## Adjusting combat difficulty in the Inspector

Each fish's attack entries are `FishEscapeState` resources. Existing attack
properties still work. The new exports are:

| Property | Default | Meaning |
| --- | --- | --- |
| `pre_windup_duration` | 0.22 s | Warning before windup; closes the reel opening |
| `close_early_window` | 0.10 s | Close-parry timing just before attack starts |
| `counter_window` | 0.16 s | Existing perfect timing from attack onset |
| `close_late_window` | 0.18 s | Close-parry timing just after perfect timing |
| `miss_progress_loss` | 0.04 | Distance lost in a smooth failed-parry dash, before strength scaling |
| `miss_tension_gain` | 0.10 | Tension added for a failed parry, before strength scaling |
| `stun_duration` | 1.7 s | Existing perfect-parry stun |

The FishingController has `miss_dash_duration` (default **0.20 s**) to control
how quickly a failed parry dashes away. The dash animates the distance and
line together; **all** passive and attack-rate backward drift is disabled,
including after the dash. Reeling becomes available when the dash completes.
`FishData.passive_escape_rate` is retained for existing resources but not used
for backward movement.

`strong_reel_scrolls` (default 3) and `strong_reel_interval`
(default 0.15 s) remain editable on the `FishingController`: a parry
resolves after the existing strong-reel scroll sequence. The last qualifying
scroll determines perfect vs. close timing.

The controller emits `parry_resolved(result)` with `"miss"`,
`"close"`, or `"perfect"`, plus
`reel_window_changed(is_open, is_free)`.
These signals are ready for future player animation, sound, or UI hooks.

## Manual gameplay checklist

1. Scroll during pre-windup or recovery: no reel progress and no failed-parry penalty. Scroll outside the parry windows *during windup or attack*: a miss dashes the fish away over 0.2 seconds and increases tension.
2. Miss during windup/attack: fish dashes once, stays at that distance, then can be reeled back in (with normal tension cost).
3. Scroll at the late end of windup or just after the perfect interval: close parry opens resisted reeling without automatic backward drift.
4. Counter immediately after attack starts: perfect parry gives the old stun and free reeling.
5. An upcoming `pre_windup` warning closes the reel window for the next parry opportunity.
6. Catch, lost line, exit, and recast still reset the combat state.

Gameplay is **not engine-tested** by this guide; run the scene in Godot and tune
the per-fish values to your desired timing.
