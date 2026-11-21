# Dialogue audit — Silas and Kuda

Audited the current authored Silas and Kuda JSON dialogue, including first
encounters, underwater story beats, rooms, gifts, invitations, dates, overnight
preludes, morning-after scenes and post-romance check-ins.

## Classification and decisions

| Existing scene or choice | Classification | Decision |
|---|---|---|
| Initial catches, rescue, first return, transformation and recruitment | Story progression | **Keep** existing story and recruitment flags. Do not create duplicate relationship events. |
| Correct gift, wrong gift, Silas's spyglass hints and Kuda's scarf | Quest progression | **Keep** `spyglass_complete`, `barracuda_scarf_complete`, `gift_attempted`, and hint flags. Add optional dialogue callbacks to acknowledge received gifts. |
| Ordinary curiosity, teasing, observations, first-meeting replies | Personality and attraction | **Keep** as dialogue/attraction choices. Do not make incidental speech a persistent conflict. |
| Silas's offer to explore together | Open personal commitment | **New `explore_together` event** when he accepts Penni's offer. Recall it in casual and post-romance conversations. Leave active because no exploration outing has been implemented; do not falsely mark it fulfilled. |
| Silas refuses to injure a weakened fish and Penni asks for another hit | Boundary and repair | **New `fish_hurt_pressure` event**, minor morale loss, and a prioritized follow-up in his room. Acknowledging his boundary repairs it; dismissing him does not. His existing nonlethal combat behavior stays unchanged. |
| Silas or Kuda is rushed during a romantic night | Boundary and repair | **Keep** shared `prelude_boundary` event and character-authored reconciliation. |
| Silas beach date and Kuda boat date | Repeatable date scenes | **Keep** date styles, per-character scores and jealousy-tier variants. Jokes and affectionate remarks aren't automatically promises. |
| Kuda mentions a possible future swim together on the boat | Potential future date activity | **Defer** as an event until there is a swim outing to actually deliver. Keep the existing reaction and date scoring unchanged. |
| Choosing to postpone a romantic evening respectfully | Consent/choice | **Keep** as a no-penalty postponement. Only pushy choices create the boundary incident. |
| Post-romance morale, neglect and jealousy check-ins | Ongoing relationship status | **Keep** condition-driven variants and rotating topics, not separate incident events. |
| Morning-after dialogue and bobber rewards | Completed story milestones | **Keep** romance completion and reward flags, not new relationship events. |
| Test-only dialogue files | Developer fixtures | **Leave** as test fixtures; don't convert them into story events. |

## New authoring notes

Relationship events are appropriate for incidents or commitments that should
survive the end of a conversation. Ordinary gifts and quest progress already
have their own flags. Date mood is handled by the existing date system.

Silas now has three event definitions in `resources/npcs/silas.tres`:
`prelude_boundary` (existing), `explore_together` (a positive open thread),
and `fish_hurt_pressure` (an unresolved incident with priority follow-up).

`explore_together` does not force daily maintenance and currently cannot be
completed because no shared exploration activity exists. When such an activity
is implemented, its conclusion can use:
`"resolve_relationship_events": ["explore_together"]`.

`fish_hurt_pressure` does not block diving or change how Silas's safe
combat retreat works. The new morale_delta effect is optional and can be
used by any NPC's authored dialogue.
