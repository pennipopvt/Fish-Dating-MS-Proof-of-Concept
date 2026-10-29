# JSON dialogue prototype (penni branch)

Author dialogue in res://dialogue/garden_eel.json. This is a runtime loader, NOT a .tres converter: DialogueLineData and DialogueChoiceData are instantiated in memory when entering a node. Cyclic next IDs are safe.

## Setup
- Open NPCData in the Inspector and set dialogue_json_path to res://dialogue/garden_eel.json.
- Keep existing NPC id, name, portrait, NPCInteractable, and DialogueUI.
- Existing test_npc.tres is intentionally retained. NPCs without a JSON path use their existing resource dialogue.
- Do not remove the current DialogueData/DialogueChoiceData classes: the UI expects them, and old NPC dialogue still uses them.

## Format
Root has entry and nodes. Each node can have lines (NPC strings or objects with speaker/text/expression), choices (text, next and optional effects), or next (automatic transition after its lines). A choice effect supports attraction, set_flags, clear_flags. Those apply to NPCManager's runtime state.

Choice response loops go via a response node and back to a menu-only node. Intro_0 / intro_1 model the first/second evasive answer without counters.

## Limitations / tests
- Run in Godot to validate GDScript and scene integration. No headless Godot test was available here.
- JSON path must be set on the NPC used by an interactable. The supplied sample isn't automatically assigned to the old test NPC.
- JSON is loaded at conversation start; runtime line/choice objects are generated on node entry. No files are generated on disk.
- 'Recruited' flag is recorded but the JSON entry is not yet gated on that flag, so speaking again restarts the catch sequence. Add post-recruitment dialogue entry logic later.
- Existing NPCManager state/affection lasts only for the current runtime session, not across game restarts.
- Stage directions need a narration presentation mode if you want them rendered differently in Jerry's UI. The JSON sample currently includes only spoken text.
- Jerry's dialogue_ui.gd and dialogue_ui.tscn have not been modified.
