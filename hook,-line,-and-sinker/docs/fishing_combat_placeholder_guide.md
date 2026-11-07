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
| **STUN** | Perfect parry. Immediately resets all tension to zero; fish cannot pull away and reeling stays tension-free. | Immediately PRE_WINDUP when `stun_duration` ends |

There is **no recovery/idle delay between attacks**. The fish does not drift
backward on its own outside a close-parry contest or the brief miss dash.

## Distance and tension

- **Dash distance:** `max(attack.escape_rate, 0) × fish.miss_dash_speed_multiplier × fish.miss_dash_duration`.
  Each fish has its own dash duration (default 0.25 s) and speed multiplier
  (default 3×), editable on its **FishData** resource. At these defaults,
  an attack with `escape_rate = 0.1` dashes 0.075 progress (roughly 23 world
  pixels with the current line settings). Interpolation stays linear.
  The attack's own escape rate remains in **FishEscapeState**, allowing
  individual attacks to have different movement speeds.
- **Automatic miss timing:** If no close or perfect parry is landed,
  the dash starts when `counter_window + close_late_window` elapses
  after attack onset, not when `state_length` expires.
- **Recovery is gated by scroll access:** Tension **does not dissipate**
  during PRE_WINDUP, locked WINDUP/ATTACK, or DASH. When the player has
  an earned reel opening (close/perfect), tension can recover using the
  controller's existing `tension_recovery` and `recovery_delay` settings.
  During a perfect stun, tension is already zero.
- **Close parry:** The player can reel as usual. Each scroll adds
  `FishData.reel_tension_gain` (multiplied by the existing
  `attack_tension_multiplier` during an active attack). The fish also
  retreats at its attack's `escape_rate` progress/second.
- **Perfect parry:** **Immediately clears 100% of existing tension.**
  Fish movement is stopped, and scrolling adds zero new tension.
- **Miss:** `FishData.miss_tension_gain × FishData.attack_tension_multiplier`
  is added **gradually over the entire dash**, alongside the fish's
  backward motion. Tension recovery is disabled during the dash and
  throughout the subsequent locked phases. If the final tension is at
  the breaking point, the fish is lost when the dash finishes.

## Inspector tuning

| Source | Property | Meaning |
| --- | --- | --- |
| `FishEscapeState` | `escape_rate` | Movement speed for close-parry resistance and the dash (progress/second) |
| `FishData → Miss Dash` | `miss_dash_duration` | How long this fish dashes on a miss (default 0.25 s) |
| `FishData → Miss Dash` | `miss_dash_speed_multiplier` | Dash speed boost relative to the current attack's `escape_rate` (default 3×) |
| `FishEscapeState` | `pre_windup_duration` | Uninterruptible attack-warning length |
| `FishEscapeState` | `windup_duration` | Parry telegraph length |
| `FishEscapeState` | `close_early_window` / `counter_window` / `close_late_window` | Early close, perfect, and late close timing |
| `FishEscapeState` | `state_length` | Active attack duration |
| `FishEscapeState` | `stun_duration` | Perfect-parry free-reel duration |
| `FishData → Tension` | `reel_tension_gain` | Tension per reel scroll (default 0.015) |
| `FishData → Tension` | `miss_tension_gain` | Total tension applied over a missed-parry dash (default 0.10) |
| `FishData → Tension` | `attack_tension_multiplier` | Scales dash tension and attack-time reel tension |
| `FishingController` | `tension_recovery` / `recovery_delay` | Recovery only when the player can reel |
| `FishingController` | `strong_reel_scrolls` / `strong_reel_interval` | Existing fast-scroll gesture; final qualifying scroll determines the parry outcome |

`FishEscapeState.miss_progress_loss`, `recovery_duration`,
`grace_start`, `miss_tension_gain`, and `counter_tension_relief`,
plus `FishData.passive_escape_rate`, are retained for saved-resource
compatibility but no longer drive combat. Species-level tension now comes
from `FishData`.

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

It checks state transitions, dash distance, fish-specific tension gains,
locked-phase tension retention, perfect-parry zero tension, and scroll lock. These tests must
still be run locally in Godot.
