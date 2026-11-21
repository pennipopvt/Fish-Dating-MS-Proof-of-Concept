
extends Node

# Affection ("attraction") every NPC starts with; AffectionManager caps it at 100.
const START_ATTRACTION := 10

var npc_states: Dictionary = {}


# Get an NPC's state, or create it if it doesn't exist.
func get_npc_state(npc_id: StringName) -> Dictionary:
	if not npc_states.has(npc_id):
		npc_states[npc_id] = {
			"attraction": START_ATTRACTION,
			"jealousy": 0,
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

# Read-only predicates shared by choice visibility, optional line variants,
# and conditional topic routing. Keep relationship state in NPCManager; neither
# DialogueManager nor JSON files should mutate it while choosing a line.
func dialogue_conditions_match(npc_id: StringName, conditions: Dictionary, jealousy_tier: int = -1) -> bool:
	if npc_id == &"":
		return false
	var state: Dictionary = get_npc_state(npc_id)
	var flags: Dictionary = state.get("flags", {})
	for flag in conditions.get("required_flags", []):
		if not flags.get(StringName(str(flag)), false):
			return false
	for flag in conditions.get("forbidden_flags", []):
		if flags.get(StringName(str(flag)), false):
			return false
	var affection: int = int(state.get("attraction", START_ATTRACTION))
	var jealousy: int = int(state.get("jealousy", 0))
	var tier: int = jealousy_tier if jealousy_tier >= 0 else mini(floori(float(jealousy) / 25.0), 3)
	if conditions.has("min_affection") and affection < int(conditions["min_affection"]):
		return false
	if conditions.has("max_affection") and affection > int(conditions["max_affection"]):
		return false
	if conditions.has("min_jealousy") and jealousy < int(conditions["min_jealousy"]):
		return false
	if conditions.has("max_jealousy") and jealousy > int(conditions["max_jealousy"]):
		return false
	if conditions.has("min_jealousy_tier") and tier < int(conditions["min_jealousy_tier"]):
		return false
	if conditions.has("max_jealousy_tier") and tier > int(conditions["max_jealousy_tier"]):
		return false
	if conditions.has("min_days_since_talk") or conditions.has("max_days_since_talk"):
		# Unknown last-talk day is not the same as neglect; first visits
		# should fall through to the usual conversation.
		if not state.has("last_talk_day"):
			return false
		var days: int = maxi(GameManager.get_day() - int(state["last_talk_day"]), 0)
		if conditions.has("min_days_since_talk") and days < int(conditions["min_days_since_talk"]):
			return false
		if conditions.has("max_days_since_talk") and days > int(conditions["max_days_since_talk"]):
			return false
	return true


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
		if rule.min_days_after_gift > 0:
			if not state.has("gift_received_day") \
					or GameManager.get_day() - int(state["gift_received_day"]) < rule.min_days_after_gift:
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


# Gift outcomes belong here; DialogueManager only requests the transfer.
func get_gift_encounter_path(npc: NPCData, item: ItemData) -> String:
	if npc == null or item == null or npc.desired_gift == null:
		return ""
	var flags: Dictionary = get_npc_state(npc.npc_id).get("flags", {})
	if not flags.get(&"Recruited", false) or flags.get(npc.gift_completed_flag, false):
		return ""
	if item.item_id == npc.desired_gift.item_id:
		return npc.correct_gift_json
	if npc.incorrect_gift_json_pool.is_empty():
		return ""
	return str(npc.incorrect_gift_json_pool.pick_random())

func accept_gift(npc: NPCData, player: Player, expected_item_id: StringName) -> bool:
	if npc == null or player == null or player.held_item == null:
		return false
	if player.held_item.item_id != expected_item_id:
		return false
	if get_gift_encounter_path(npc, player.held_item).is_empty():
		return false
	var is_correct := player.held_item.item_id == npc.desired_gift.item_id
	player.remove_held_item()
	if is_correct:
		var state: Dictionary = get_npc_state(npc.npc_id)
		var flags: Dictionary = state["flags"]
		flags[npc.gift_completed_flag] = true
		state["gift_received_day"] = GameManager.get_day()
	return true


# Development shortcut: F6 skips Silas's initial catch conversation.
# Only active in debug builds; leaves the gift puzzle and hint selection untouched.
func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		var state := get_npc_state(&"test_npc")
		var flags: Dictionary = state["flags"]
		flags[&"Recruited"] = true
		print("[DEV] Silas recruited. Next interaction begins his gift quest.")
		get_viewport().set_input_as_handled()
