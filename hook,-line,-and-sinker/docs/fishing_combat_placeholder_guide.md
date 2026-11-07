# Fishing combat state machine

Combat uses the fish's current `FishEscapeState` for attack timings and
movement speed. The visible attack/feedback animations are still editable in
`res://scenes/fishing_controller.tscn` → `FishingLine/RippleTell`.

## State transitions

| Current state | What happens | Next state |
| --- | --- | --- |
| **PRE_WINDUP** | Immediately starts when a fish hooks or the previous attack resolves. Reeling/parry scrolls are ignored. Plays `pre_windup`. | WINDUP after `pre_windup_duration` |
| **WINDUP** | Plays the timed `windup` telegraph. A close-enough parry near the attack opens contested reeling; an early miss starts DASH. | ATTACK when the windup ends, or DASH on miss |
| **ATTACK** | Plays `start_attack` then `attacking`. Close parry allows reeling **while the fish swims away**; perfect parry interrupts with STUN. A missed parry, including letting the attack expire without parrying, starts DASH. | PRE_WINDUP after a successful close encounter's attack finishes, DASH on miss, or STUN on perfect |
| **DASH** | Exactly one constant-speed backward movement; **all reel input is locked**. | Immediately PRE_WINDUP at the end of `miss_dash_duration` |
| **STUN** | Perfect parry. Fish cannot pull away and **reeling adds no tension**. Existing counter-tension relief still applies. | Immediately PRE_WINDUP when `stun_duration` ends |

There is **no recovery/idle delay between attacks**. The fish does not drift
backward on its own outside a close-parry contest or the brief miss dash.

## Distance and tension

- **Dash distance:** `max(escape_rate, 0) × miss_dash_duration`. For
  example, a fish moving at 0.3 progress/second dashes backward by 0.06
  progress during a 0.20-second dash. Dash interpolation is linear so it is
  one clean movement.
- **Close parry:** The player can reel as usual, with normal
  tension buildup. In WINDUP/ATTACK the fish simultaneously retreats at
  `escape_rate` progress/second; the player's reeling fights that movement.
- **Perfect parry:** Fish movement is stopped for the stun. Scrolls
  increase reel progress but add **zero tension**, even if the attack was
  previously in progress.
- **Miss:** Applies the existing `miss_tension_gain` penalty once,
  then completes the dash before deciding if the fish escaped. Reeling
  cannot resume during the dash or pre-windup.

## Inspector tuning

| Source | Property | Meaning |
| --- | --- | --- |
| `FishEscapeState` | `escape_rate` | Movement speed for close-parry resistance and the dash (progress/second) |
| `FishingController` | `miss_dash_duration` | How long each miss dash lasts (default 0.20 s) |
| `FishEscapeState` | `pre_windup_duration` | Uninterruptible attack-warning length |
| `FishEscapeState` | `windup_duration` | Parry telegraph length |
| `FishEscapeState` | `close_early_window` / `counter_window` / `close_late_window` | Early close, perfect, and late close timing |
| `FishEscapeState` | `state_length` | Active attack duration |
| `FishEscapeState` | `stun_duration` | Perfect-parry free-reel duration |
| `FishEscapeState` | `miss_tension_gain` | One-time extra tension on a miss |
| `FishingController` | `strong_reel_scrolls` / `strong_reel_interval` | Existing fast-scroll gesture; final qualifying scroll determines the parry outcome |

`FishEscapeState.miss_progress_loss`, `recovery_duration`, and
`grace_start`, plus `FishData.passive_escape_rate`, are retained for
saved-resource compatibility but do not determine the current combat movement.

## Swapping animation art

Open `scenes/fishing_controller.tscn` → `FishingLine` →
`RippleTell` and edit its **SpriteFrames**. Keep these animation names:
`pre_windup`, `windup`, `start_attack`, `attacking`,
`counter_close`, `counter_fail`, `counter_success`, `stun`,
and `idle`. Your current frames are kept. No temporary color tints are
applied. A new `pre_windup` immediately replaces an unfinished
`counter_fail` flash after a dash.

## Regression checks

Run the optional script from the Godot project folder:

```sh
godot --headless --path . -s res://tests/fishing_combat_states_test.gd
```

It checks the state transitions, dash distance, close-parry resistance,
perfect-parry zero-tension movement, and scroll lock. These tests must
still be run locally in Godot.
