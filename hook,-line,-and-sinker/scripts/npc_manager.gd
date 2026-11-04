
extends Node

var npc_states: Dictionary = {}


# Get an NPC's state, or create it if it doesn't exist.
func get_npc_state(npc_id: StringName) -> Dictionary:
	if not npc_states.has(npc_id):
		npc_states[npc_id] = {
			"attraction": 0,
			"flags": {}
		}

	return npc_states[npc_id]


# Find the first dialogue whose conditions are met.
func get_dialogue(npc: NPCData) -> DialogueData:
	if npc == null:
		return null

	var state := get_npc_state(npc.npc_id)
	var flags: Dictionary = state["flags"]

	for rule in npc.dialogue_rules:
		if rule == null or rule.dialogue == null:
			continue

		var valid := true

		for flag in rule.required_flags:
			if flag == null or not flags.get(flag.flag_id, false):
				valid = false
				break

		if not valid:
			continue

		for flag in rule.forbidden_flags:
			if flag != null and flags.get(flag.flag_id, false):
				valid = false
				break

		if valid:
			return rule.dialogue

	return null


# Apply the consequences of a player choice.
func apply_choice(
	npc: NPCData,
	choice: DialogueChoiceData
) -> void:
	if npc == null or choice == null:
		return

	var state := get_npc_state(npc.npc_id)
	var flags: Dictionary = state["flags"]

	state["attraction"] += choice.attraction_change

	for flag in choice.flags_to_set:
		if flag != null:
			flags[flag.flag_id] = true

	for flag in choice.flags_to_clear:
		if flag != null:
			flags[flag.flag_id] = false

# Returns a JSON encounter file path, or "" when none of the configured rules match.
# When rules exist, a failure to match deliberately does not use the legacy dialogue.
func get_encounter_json_path(npc: NPCData) -> String:
	if npc == null:
		return ""
	var state: Dictionary = get_npc_state(npc.npc_id)
	var flags: Dictionary = state.get("flags", {})
	for rule in npc.encounter_rules:
		if rule == null or (rule.json_path.is_empty() and rule.json_pool.is_empty()):
			continue
		if rule.use_min_attraction and int(state.get("attraction", 0)) < rule.min_attraction:
			continue
		var matches := true
		for flag in rule.required_flags:
			if not flags.get(flag, false):
				matches = false
				break
		if not matches:
			continue
		for flag in rule.forbidden_flags:
			if flags.get(flag, false):
				matches = false
				break
		if matches:
			if rule.json_pool.is_empty():
				return rule.json_path
			# Remember the selection for this NPC and rule until explicitly reset.
			var selections: Dictionary = state.get("encounter_pool_selections", {})
			state["encounter_pool_selections"] = selections
			var key: int = npc.encounter_rules.find(rule)
			if not selections.has(key):
				selections[key] = rule.json_pool.pick_random()
			return str(selections[key])
	return ""
