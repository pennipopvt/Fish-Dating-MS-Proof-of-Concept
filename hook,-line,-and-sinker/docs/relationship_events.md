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
individually authored. The event architecture does not automatically change
affection or morale; those remain separate systems and can be combined in
authored content when desired.
