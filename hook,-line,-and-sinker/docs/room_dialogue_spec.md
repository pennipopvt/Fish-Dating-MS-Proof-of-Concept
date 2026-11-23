# NPC room conversations (approved 2026-11-23)

Contextual interactions (ready date, intimate night, unresolved relationship event,
held gift, story context) take priority. Otherwise: greeting -> Let's talk /
Wanna go on a date (if unlocked) / Goodbye.

Let's talk shows up to two eligible topics per day, drawn from a persistent bag.
The same authored bag works before and after romance. Previous choices are grey
but still selectable on subsequent days. A topic already used today disappears.
When daily topics are exhausted the NPC politely sets a boundary. Every
conversation ends by exiting the room, never looping to the same menu.

Numerical affection/jealousy check-in variants have been retired from the room
dialogue files. Date jealousy-tier text has been removed, but the underlying
scoring and decline/incident system still needs a separate runtime cleanup.

Planned: other-romance events trigger on sleeping together, not dating; repeat
offenses for knockouts/other-romance escalate; wrong apology means next-day
retry; event-driven refusal to answer the door and to dive. Preserve story
progression, gifts, authored dates, and all conflict responses.
