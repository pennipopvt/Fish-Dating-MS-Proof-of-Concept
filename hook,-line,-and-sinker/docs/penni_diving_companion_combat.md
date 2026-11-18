# Penni Diving — companion autobattle experiment

**Branch:** `penni-diving` (cut from `diving`). Do not merge to `main` until local playtesting. The current pre-experiment `main` snapshot is `backup-main-2026-11-18` at commit `c7b26c256d011c768481005d35aec6757f456dfa`. **A GitHub administrator still needs to configure branch rules for that backup**; creating the branch alone does not protect it against force-pushes or deletion.

## What we're actually testing

Keep the parts of diving that felt good: Penni freely swims in a spatial level, Silas is physically present as an eel, she catches fish with an aimable net projectile, and net encounters keep the real-distance reel/parry/tension/stagger system.

Add a **pre-capture combat layer**:
- **Right-click a wild fish:** Silas targets it, swims toward it, and periodically deals damage without further commands. Right-click the same fish or empty water to stand down.
- **Fish have HP:** different species start with different health. The target has five tiny health pips directly above its sprite, not a full-screen bar. A hit briefly flashes the fish.
- **Wild fish fight back:** when Silas gets close, the fish periodically hurts him. Three small pips appear above Silas when engaged or injured.
- **Silas auto-special:** at low health, his familiar sand concealment automatically shields him for a few seconds, then goes on cooldown. No new hotkey; `Q` is not needed for combat.
- **Out of commission:** if Silas's health reaches zero, he stops attacking for 18 seconds, visually dims, then partially recovers. Returning to shore rests him fully.
- **Risk of killing the catch:** continuing to attack until a wild fish has 0 HP causes it to sink/disappear. It adds **nothing** to storage or collections; the chance to net it is lost.
- **Catch timing is the player's decision:** left-click still casts the same physical, maximum-range net projectile. When it latches, companion attacks pause and the existing reel/parry fight takes over.
- **Health helps capture, never replaces it:** the fish's HP at hook time reduces pull speed, dash distance and line-tension penalties, and increases stagger earned from parries. Reeling must still close the *actual line distance*. A fully healthy fish can still be caught.

### Controls

| Input | Action |
| --- | --- |
| WASD | Swim |
| Right-click a wild fish | Target / cancel target for autonomous companion attacks |
| Right-click empty water | Stand down |
| Left-click | Throw directional net |
| Scroll down during net fight | Parry and reel exactly as in `diving` |
| E / Space | Talk, help Silas, surface |

No ability wheel or extra attack buttons. Silas's sand ability is deliberately automatic in this prototype.

## Balancing defaults — change in Inspector

- `CompanionBattle.auto_attack_damage`: **8 HP**
- `CompanionBattle.auto_attack_interval`: **1.5 seconds**
- `CompanionBattle.retaliation_damage`: **12 HP**
- `CompanionBattle.retaliation_interval`: **2.3 seconds**
- `CompanionBattle.max_companion_health`: **60 HP**
- `CompanionBattle.recovery_seconds`: **18 seconds**
- `CompanionBattle.cover_duration`: **3.5 seconds**
- `CompanionBattle.cover_cooldown`: **14 seconds**
- Wild fish HP initially scales as **60% of species stagger resistance**, with a 30 HP minimum.
- Net resistance at time of hooking: **40–100% of original** depending on fish HP. Species still have their authored FishData attack speed and stagger properties.

These are tuning placeholders, **not** finalized balance values.

## What stays deliberately unbuilt

Only Silas is battle-capable in this first pass. The architecture keeps autonomous battle logic separate from the net combat, but multiple companions, switching targets between several allies, NPC-specific active abilities, experience/progression, and actual knockout animation sprites need additional design and playtesting. Death is currently represented by sinking and fading without a gore effect.

## How to test

1. Start the usual island game. Dive, meet Silas and use the original net/parry encounter to rescue him.
2. Right-click a wild fish. See Silas swim over and chip away its five tiny health pips. Click the target again to call him off.
3. Net a **mostly healthy** fish, then a **weakened** fish and compare resistance during reel/parry.
4. Target another fish and **wait too long**. It will be defeated and become uncatchable rather than joining inventory.
5. Watch the fish strike back. At low HP Silas should trigger a defensive sand cloud without a button press. If depleted, he pauses and recovers, or can rest fully on shore.
6. Verify dialogue, Silas's following, and the circular island transition still behave normally.

Automated regression script (requires Godot installed locally):

```bash
godot --headless --path . -s res://tests/diving_companion_battle_test.gd
godot --headless --path . -s res://tests/diving_prototype_test.gd
godot --headless --path . -s res://tests/diving_combat_distance_test.gd
```

**Not runtime-tested in the GitHub editing environment.** The new branch should be tested in the Godot editor before any merge.

## Backup-branch protection

The backup branch is a separate pointer to the original `main` commit; it is not a configured GitHub protected branch yet. In the repo's **Settings → Rules → Rulesets**, create an **active branch ruleset** including exactly `refs/heads/backup-main-2026-11-18`. Enable **Restrict deletions**, **Block force pushes / non-fast-forward updates**, and **Restrict updates**, with no bypass actors unless required for recovery. Verify that the rule applies to the exact backup branch. Treat `main` as the ongoing PR integration branch and never merge work directly into the backup snapshot.
