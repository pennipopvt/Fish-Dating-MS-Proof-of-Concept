# Contextual underwater party commands

**Status:** implemented in the existing Sea scene on `penni-diving`.
This replaces only the Silas-specific right-click routing, not the fishing,
NPC dialogue, fish population, or party roster.

## Player controls
- **Right-click wild fish:** assigns the **first available** companion to that fish.
- **Right-click an assigned fish:** recalls its specific companion; all other battles continue.
- **Right-click empty water:** recalls everyone, then recreates the queue in `DivingParty` order.
- If everyone is assigned or knocked out, a new target cannot be assigned.
- If a companion refuses a target (Silas at/below his 50% safety threshold, or Silas refusing to interrupt Kuda's introductory hunt), the command is handled but **doesn't** use up that companion's queue slot. Right-clicking an assigned fish works even after the player swims out of its normal assignment range.
- Automatic returns (fish spared, fish knocked out, companion exhausted) join the **back** of the available queue. A full recall restores starting order.

The available queue is deliberately **not displayed as a HUD**; the actual fish actors approach the fish they are attacking and follow Penni when available.

## Ownership
- `DivingParty`: authoritative up-to-three-person roster and ordering.
- `SeaPartyCommands`: only FIFO assignment, targeting, recalls, and battle updates.
- `DivingCompanionBattle`: one independent battle/health/timers per companion.
- `CompanionCombatBehavior`: character-specific decisions without forks in combat math. Silas uses his existing nonlethal subclass; Kuda uses the lethal `KudaCombatBehavior` with configurable finisher bonus.
- `SeaNPC` (Silas) and `SeaPartyFollower` (Kuda): own visuals, movement into attack range, facing, and feedback. Kuda's follower instantiates battle and behavior from the referenced `NPCData` resource. Future NPCs can opt in by assigning `sea_battle_stats` and optionally `sea_combat_behavior_script`.
- `DivingWorld`: only input routing, fish registration, effects and gameplay events; a net hit stops the battle for **that fish only**.

## Editing
- `resources/companions/kuda_battle.tres`: Kuda's health, attack, defense, speed, and regeneration.
- `scripts/diving/kuda_combat_behavior.gd`: editable finishing threshold and extra damage. It does **not** clamp damage at 50%, so leaving Kuda attacking can kill fish and cost the player a catch.
- `resources/npcs/kuda.tres`: optional `sea_battle_stats` and `sea_combat_behavior_script` link to his loadout.
- `resources/visuals/kuda_sea_visuals.tres`: existing fish-form size and portrait framing, unchanged.

No new UI panels or shortcuts are needed.

## Silas's wounded-fish dialogue

Silas's combat safety threshold is unchanged: he stops on his own at 50%
health without needing a player command. His first automatic disengagement
can display the one-time tutorial speech bubble, but subsequent automatic
retreats remain silent.

A **deliberate right-click order** against an already-wounded fish always
routes through his existing `silas_refuses_attack.json` conversation, even if
the tutorial warning has appeared earlier. This lets Penni back off or keep
pressuring him, including the `fish_hurt_pressure` relationship-event
consequence. Rejected orders never hurt the fish or consume Silas's queue
slot. An active dialogue is never interrupted by a second refusal.
