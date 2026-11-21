class_name DialogueJsonLoader
extends RefCounted

# Checks references before the manager begins displaying the graph.
static func read_graph(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Dialogue JSON missing: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open dialogue JSON: " + path)
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		push_error("Dialogue JSON parse error in %s line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if not parser.data is Dictionary:
		push_error("Dialogue JSON root must be a dictionary: " + path)
		return {}
	var graph: Dictionary = parser.data
	if not graph.has("entry") or not graph.get("nodes") is Dictionary:
		push_error("Dialogue JSON needs entry and nodes: " + path)
		return {}
	var nodes: Dictionary = graph["nodes"]
	if not nodes.has(str(graph["entry"])):
		push_error("Dialogue entry does not exist: " + path)
		return {}
	for id in nodes:
		var node: Variant = nodes[id]
		if not node is Dictionary:
			push_error("Dialogue node is not a dictionary: " + str(id))
			return {}
		if not node.get("lines", []) is Array or not node.get("choices", []) is Array:
			push_error("Invalid lines or choices at dialogue node: " + str(id))
			return {}
		# Optional response alternatives for jealousy tiers 1, 2 and 3.
		# Tier 0 remains the ordinary "lines" array.
		if node.has("jealousy_lines"):
			var variants: Variant = node["jealousy_lines"]
			if not variants is Dictionary:
				push_error("Invalid jealousy lines at dialogue node: " + str(id))
				return {}
			for tier in variants:
				if not str(tier) in ["1", "2", "3"] or not variants[tier] is Array or variants[tier].is_empty():
					push_error("Invalid jealousy tier variant at dialogue node: " + str(id))
					return {}
				for line in variants[tier]:
					if not line is String and not (line is Dictionary and line.has("text")):
						push_error("Invalid jealousy dialogue line at node: " + str(id))
						return {}
		# A node can choose state-aware text while retaining its original path.
		# Variants are checked top-to-bottom; the first matching condition wins.
		if node.has("line_variants"):
			if not node["line_variants"] is Array:
				push_error("Invalid line variants at: " + str(id))
				return {}
			for variant in node["line_variants"]:
				if not variant is Dictionary or not _valid_conditions(variant.get("when", {})) \
						or not _valid_lines(variant.get("lines", null)) or variant["lines"].is_empty():
					push_error("Invalid conditional lines at: " + str(id))
					return {}
		# Optional dialogue-only routers keep full story-stage graphs reusable.
		if node.has("conditional_next") or node.has("rotating_next"):
			if not node.get("lines", []).is_empty() or not node.get("choices", []).is_empty() \
					or node.has("effects") or node.has("cue") or node.has("next"):
				push_error("Dialogue router must not also contain lines, choices or effects: " + str(id))
				return {}
		if node.has("conditional_next"):
			if not node["conditional_next"] is Array:
				push_error("Invalid conditional topic routing at: " + str(id))
				return {}
			for route in node["conditional_next"]:
				if not route is Dictionary or not nodes.has(str(route.get("next", ""))) \
						or not _valid_conditions(route.get("when", {})):
					push_error("Invalid conditional topic destination at: " + str(id))
					return {}
		if node.has("rotating_next"):
			if not node["rotating_next"] is Array or node["rotating_next"].is_empty():
				push_error("Invalid rotating topic list at: " + str(id))
				return {}
			for route in node["rotating_next"]:
				var destination: String = str(route.get("next", "")) if route is Dictionary else str(route)
				if not nodes.has(destination) or (route is Dictionary and not _valid_conditions(route.get("when", {}))):
					push_error("Invalid rotating topic destination at: " + str(id))
					return {}
		if node.has("next") and not nodes.has(str(node["next"])):
			push_error("Missing next dialogue node at: " + str(id))
			return {}
		if node.has("cue") and not node["cue"] is String:
			push_error("Invalid dialogue cue at: " + str(id))
			return {}
		if node.has("effects") and not _valid_effects(node["effects"]):
			push_error("Invalid node effects at: " + str(id))
			return {}
		for choice in node.get("choices", []):
			if not choice is Dictionary or not choice.has("text") or not nodes.has(str(choice.get("next", ""))):
				push_error("Bad dialogue choice target at: " + str(id))
				return {}
			if not _valid_conditions(choice.get("when", {})):
				push_error("Invalid state condition on choice in: " + str(id))
				return {}
			if choice.has("priority") and not _json_number(choice["priority"]):
				push_error("Invalid choice priority in: " + str(id))
				return {}
			for condition in ["required_flags", "forbidden_flags"]:
				if not _string_array(choice.get(condition, [])):
					push_error("Invalid " + condition + " at choice in: " + str(id))
					return {}
			if choice.has("effects") and not _valid_effects(choice["effects"]):
				push_error("Invalid choice effects at: " + str(id))
				return {}
	return graph

# Explicit schema catches misspelled condition names during import/testing.
static func _valid_conditions(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in value:
		if key in ["required_flags", "forbidden_flags"]:
			if not _string_array(value[key]):
				return false
		elif key in ["min_affection", "max_affection", "min_jealousy", "max_jealousy",
				"min_jealousy_tier", "max_jealousy_tier", "min_days_since_talk", "max_days_since_talk"]:
			if not _json_number(value[key]):
				return false
		else:
			return false
	return true


# JSON numeric literals are floats in Godot's parser (even 10), while
# in-memory graphs may contain true ints.
static func _json_number(value: Variant) -> bool:
	return value is int or value is float


static func _valid_lines(value: Variant) -> bool:
	if not value is Array:
		return false
	for line in value:
		if not line is String and not (line is Dictionary and line.has("text") and line["text"] is String):
			return false
	return true


static func _string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry in value:
		if not entry is String:
			return false
	return true

static func _valid_effects(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if not _string_array(value.get("set_flags", [])) or not _string_array(value.get("clear_flags", [])):
		return false
	if value.has("give_held_item") and not value["give_held_item"] is bool:
		return false
	if value.has("request_scene") and (not value["request_scene"] is String or value["request_scene"].is_empty()):
		return false
	return true

# Resolve the requested jealousy tier, falling back to ordinary dialogue.
# This does not alter the graph or the options the player can pick.
static func lines_for_jealousy_tier(node: Dictionary, tier: int) -> Array:
	var variants: Variant = node.get("jealousy_lines", {})
	if variants is Dictionary and variants.has(str(clampi(tier, 0, 3))):
		var alternate: Variant = variants[str(clampi(tier, 0, 3))]
		if alternate is Array:
			return alternate
	return node.get("lines", [])
