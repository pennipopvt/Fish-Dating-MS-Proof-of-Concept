# Relationship events

Each NPC may define any number of `RelationshipEventData` resources in the
**Relationship Events** array of their `NPCData` Inspector. This reuses
`NPCManager`, `DialogueManager`, and the usual JSON dialogue; there is no
special-case Kuda/Silas logic or additional dialogue controller.

## Creating a relationship incident

1. Add a `RelationshipEventData` to the character's NPC resource.
2. Give it a stable `event_id`, for example `prelude_boundary`. All NPCs
   can use the same event ID: history is stored per NPC, never globally.
3. Optionally set **Followup Dialogue Json** and its **Priority**. The highest
   priority active event with a dedicated follow-up takes precedence over
   ordinary encounters. Leave blank to handle it through existing dialogue
   `when` conditions instead.
4. Use **Blocks Actions** for action IDs that cannot happen until repaired,
   for example `overnight`. The room view reads this generically. Other
   gameplay systems can choose to check their own action IDs.

After the character communicates a boundary or incident, add this to the
dialogue choice or node effects (fires after the player sees the response):

```json
"effects": {"start_relationship_events": ["prelude_boundary"]}
```

After a genuine reconciliation, add:

```json
"effects": {"resolve_relationship_events": ["prelude_boundary"]}
```

To change greetings, choices, and routing while an event is unresolved:

```json
"when": {"active_events": ["prelude_boundary"]}
```

For later callbacks to a repaired incident, use `resolved_events` instead.
The existing `required_flags`, `forbidden_flags`, `line_variants`,
`conditional_next`, and priority mechanisms still work normally.

## Runtime and flags

`NPCManager` stores `relationship_events[event_id]` inside each NPC state
with `active`, `started_day`, and (after repair) `resolved_day`. It also
mirrors two ordinary flags, for legacy dialogue/conditions:

- `relationship_event_<id>_active`
- `relationship_event_<id>_resolved`

Start is idempotent while the event is active, so repeating an interaction
doesn't change its recorded day. Resolution only works on active events,
and a previously resolved incident can be started again if the story warrants.

`NPCManager.has_blocking_relationship_event(npc, action_id)` checks every
active configured event. A night-time reconciliation is recognized by the
room, but cannot surprise the player with a same-night intimacy retry.

Kuda and Silas both define `prelude_boundary`, with different dialogue on
return. The event mechanics and flags are identical; their reactions are
individually authored. The event architecture does not automatically change affection. Add an
authored `affection_delta` effect when an incident should affect the single
relationship score. Jealousy remains independent for context-specific reactions.


## Affection, jealousy, and time together

There is **no automatic +12 affection on conversation completion**. A visit
records `last_talk_day` and can prevent the next day's passive neglect,
but a hello or goodbye does not raise affection. Only authored dialogue
choices, date outcomes and other explicit events can do that. The existing
five-day grace for unrecruited/early companions and affection-based diving
refusal thresholds are unchanged.

Jealousy is not a synonym for low affection:
- Completing another romance adds 45 jealousy and costs 12 affection for
  existing recruited romantic partners.
- Completing a date with one partner adds 15 jealousy to each **other**
  recruited romantic partner; the person on the date is unaffected.
- Missing an appointment costs its NPC 18 affection, not jealousy.
- Dates retain their existing jealousy-tier-dependent reactions and
  reassurance/playful/bold choices.

The first jealousy incident starts the reusable `other_romance` relationship
event defined on each NPC's `Relationship Events` Inspector array. The
priority follow-ups are `dialogue/silas_other_romance.json` and
`dialogue/kuda_other_romance.json`, each with the NPC's own voice and
choices. They use standard `DialogueManager` and may be edited without
editing the manager code. The authored `jealousy_delta` effect changes
the shared jealousy score; `affection_delta` changes affection.
Reassurance reduces jealousy by 25 and resolves the incident after the
response has been read. Dismissal raises jealousy, hurts affection, and
leaves the issue active; asking to talk later leaves it unresolved.
When another partner-date happens, a previously resolved incident can start
again, and reconciliation can work again too.

The ordinary post-romance dialogue now recognizes jealousy from 25 onward,
rather than waiting for 50, and the incident dialogue has priority over
everyday conversation. Like other incidents, higher-priority events
(e.g. a companion knockout) may take precedence.

Coverage: `tests/jealousy_relationship_test.tscn`,
`tests/relationship_dates_test.tscn`,
`tests/companion_morale_test.tscn`, and the Godot smoke workflow.

## Morning invitation story beats

Silas and Kuda's first invitation is no longer selected by ordinary room
encounters. After receiving the desired gift and waiting at least one new day,
an eligible resident approaches Penni as a world actor when she wakes from a
night's sleep. `IslandStoryDirector` owns eligibility, morning-only scheduling,
input lock, actor entrance/exit and the fade when both characters are ready.
The NPC's existing `land_actor_scene_path` is spawned non-interactively using
`NPCTemporaryActor`; the dialogue is still authored in the existing JSON
files, and flags still belong to `NPCManager`.

Editor controls: move `World/MorningStoryEntry` to change where guests enter;
edit `resources/story_events/*_morning_invitation.tres` to change conditions,
approach distance/speed or retry interval. A declined invitation may be offered
again no sooner than three days later; accepting its flag ends further offers.
Only `GameManager.day_started` queues morning events, so receiving a gift
midday will not trigger the invitation until waking on a later morning.

Manual regression: give both gifts on the same day, sleep overnight, verify
Silas walks in and initiates his invitation, walks out afterward, then a screen
fade separates Kuda's own entrance and conversation. Test accept/decline,
decline again after the cooldown, accepted flags preventing repeats, ordinary
room dialogue without invitations, and Fish Co daytime events.
