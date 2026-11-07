# Fishing combat state machine

Combat uses the fish's current `FishEscapeState` for attack timings and
movement speed. The visible attack/feedback animations are still editable in
`res://scenes/fishing_controller.tscn` → `FishingLine/RippleTell`.

## State transitions

| Current state | What happens | Next state |
| --- | --- | --- |
| **PRE_WINDUP** | Immediately starts when a fish hooks or the previous attack resolves. Reeling/parry scrolls are ignored. Plays `pre_windup`. | WINDUP after `pre_windup_duration` |
| **WINDUP** | Plays the timed `windup` telegraph. A close-enough parry near the attack opens contested reeling; an early miss starts DASH. | ATTACK when the windup ends, or DASH on miss |
| **ATTACK** | Plays `start_attack` then `attacking`. Close parry allows reeling **while the fish swims away**; perfect parry interrupts with STUN. A missed parry, including letting the last close-parry window expire without input, starts DASH immediately (the full attack duration is not waited out). | PRE_WINDUP after a successful close encounter's attack finishes, DASH on miss, or STUN on perfect |
| **DASH** | Exactly one constant-speed backward movement; **all reel input is locked**. | Immediately PRE_WINDUP at the end of `miss_dash_duration` |
| **STUN** | Perfect parry. Fish cannot pull away and **reeling adds no tension**. Existing counter-tension relief still applies. | Immediately PRE_WINDUP when `stun_duration` ends |

There is **no recovery/idle delay between attacks**. The fish does not drift
backward on its own outside a close-parry contest or the brief miss dash.

## Distance and tension

- **Dash distance:** `max(escape_rate, 0) × miss_dash_speed_multiplier × miss_dash_duration`.
  At the default 3× dash-speed multiplier, a fish with `escape_rate = 0.1`
  dashes 0.075 progress over a 0.25-second dash (roughly 23 world pixels
  for the current line-distance settings). Dash interpolation is linear so
  it is one clean movement. Slow fish have shorter dashes unless you
  increase the multiplier or the fish's `escape_rate`.
- **Automatic miss timing:** If no close or perfect parry is landed,
  the dash starts when `counter_window + close_late_window` elapses
  after attack onset, not when `state_length` expires.
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
| `FishingController` | `miss_dash_speed_multiplier` | Dash speed boost relative to the fish's `escape_rate` (default 3×) |
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
