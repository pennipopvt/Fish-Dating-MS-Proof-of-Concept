# Fishing combat — temporary art and tuning

The new combat loop is **pre-windup warning → windup → attack → recovery**. 
Players cannot gain reel progress unless they successfully parry. A **close parry**
allows resisted reeling; a **perfect parry** retains the existing stun, tension
relief, and free reeling. A miss pushes the fish back and adds tension.

## Replacing the animation placeholders (no code changes)

Open `res://scenes/fishing_controller.tscn`. Select:
`FishingController / FishingLine / RippleTell`, then open **Sprite Frames** in the Inspector.

The animations are named:

| Animation | Temporary effect | Intended replacement |
| --- | --- | --- |
| `pre_windup` | existing windup ripple with a warm tint | short warning ripple/line cue |
| `windup` | existing ripples (preserved) | building attack tell |
| `start_attack` | existing small splash (preserved) | one-shot attack onset |
| `attacking` | existing ripples (preserved) | looping fish-pull effect |
| `counter_close` | existing stun-flash frames tinted green | close-parry splash |
| `counter_success` | existing stun flash (preserved) | perfect-parry effect |
| `counter_fail` | existing splash frames tinted red | failed-parry effect |
| `stun` | existing ripple (preserved) | stunned water effect |
| `idle` | existing calm water ripples (preserved) | recovery effect |

All placeholder frames reuse the existing 32×32 art-pixel ripple atlases.
Draw replacement animation frames at **32×32 art pixels** and use
transparent backgrounds. Replace frames under those names; keep the animation
names unchanged. `start_attack`, `counter_close`, `counter_fail`, and
`counter_success` should be **non-looping**; `pre_windup`, `attacking`,
`stun`, and `idle` may loop.

The fishing line turns pale yellow during pre-windup; its color is exported as
`pre_windup_line_color` in `FishingLine`. The flash tints are temporarily set
in `res://scripts/fishing_line.gd` under `play_ripple()`.

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
| `miss_progress_loss` | 0.04 | Distance lost for a failed parry, before strength scaling |
| `miss_tension_gain` | 0.10 | Tension added for a failed parry, before strength scaling |
| `stun_duration` | 1.7 s | Existing perfect-parry stun |

`strong_reel_scrolls` (default 3) and `strong_reel_interval`
(default 0.15 s) remain editable on the `FishingController`: a parry
resolves after the existing strong-reel scroll sequence. The last qualifying
scroll determines perfect vs. close timing.

The controller emits `parry_resolved(result)` with `"miss"`,
`"close"`, or `"perfect"`, plus
`reel_window_changed(is_open, is_free)`.
These signals are ready for future player animation, sound, or UI hooks.

## Manual gameplay checklist

1. Scroll before a parry window: no reel progress; failed parry pushes fish out and increases tension.
2. Scroll at the late end of windup or just after the perfect interval: close parry opens resisted reeling while the fish keeps pulling.
3. Counter immediately after attack starts: perfect parry gives the old stun and free reeling.
4. Reeling stops being effective when the next `pre_windup` warning begins.
5. Catch, lost line, exit, and recast still reset the combat state.

Gameplay is **not engine-tested** by this guide; run the scene in Godot and tune
the per-fish values to your desired timing.
