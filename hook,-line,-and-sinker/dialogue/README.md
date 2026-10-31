# JSON dialogue encounters (penni branch)

Each JSON file defines ONE encounter's dialogue graph. Nodes link to other nodes via string IDs, including loops. No .tres dialogue graphs are generated on disk. DialogueLineData and DialogueChoiceData are instantiated in memory on each node entry; Jerry's DialogueUI API is unchanged.

## NPC setup (Inspector)
1. Set NPCData.npc_id, display_name, and optionally portrait as usual.
2. Under **JSON Encounter Rules**, add EncounterRuleData entries in order from most specific to least specific.
3. For each entry set json_path, required_flags, forbidden_flags, and optionally use_min_attraction + min_attraction.
4. For the garden eel, set rules in this order:
   - path: res://dialogue/garden_eel_casual.json ; required_flags: [Recruited]
   - path: res://dialogue/garden_eel.json ; forbidden_flags: [Recruited]
5. When talking to the NPC, NPCManager examines NPC state and chooses the FIRST matching encounter. No match means no conversation.
6. JSON choice effects such as {"set_flags":["Recruited"]} change NPCManager's state, so the next interaction selects a different encounter.

## Compatibility
The old defined_flags and dialogue_rules fields remain to avoid breaking existing .tres NPCs. The original dialogue_json_path remains as a fallback for NPCData without encounter_rules; it is no longer the recommended field. NPCs with encounter_rules use ONLY those rules, even when no rule matches.

## JSON format
A graph has entry and nodes. Nodes have lines (strings as NPC speech, or objects with speaker/text/expression), choices (text, next, optional spoken_text, expression, effects), or next (automatic transition after lines). Choice effects support attraction (integer), set_flags (array of names), and clear_flags (array of names). A response node can return to a menu-only node to loop safely without cyclical resource references. intro_0 and intro_1 implement the two evasive choices in the sample without a counter.

## Important limits
- JSON is loaded at conversation start. It doesn't write new resources to disk.
- NPC state is only kept in memory during the current game run; there is no save/load persistence yet.
- Changing flags doesn't swap the encounter mid-conversation; selection happens at the next interaction.
- Legacy dialogue support, project autoloads, and dialogue_ui.gd/tscn remain unchanged.
- Please test in Godot; this commit has not been compiled or played in the editor.

## Player speech and choice playback
- Lines can be objects such as `{"speaker":"player","text":"Hello!"}`; strings remain NPC dialogue for backward compatibility. The existing DialogueUI displays player lines using Penni’s name and portrait styling.
- After a JSON choice is selected, DialogueManager displays the selected text as a player line. Press Continue to proceed to the choice target. Its effects apply at that point, not on the initial click.
- Set optional `spoken_text` on a choice if Penni should say something different from the button label, and optional `expression` for the player line. Without `spoken_text`, she speaks the button text exactly.
- Legacy resource-based dialogue remains unchanged.
