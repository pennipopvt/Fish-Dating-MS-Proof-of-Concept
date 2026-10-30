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
		if node.has("next") and not nodes.has(str(node["next"])):
			push_error("Missing next dialogue node at: " + str(id))
			return {}
		for choice in node.get("choices", []):
			if not choice is Dictionary or not choice.has("text") or not nodes.has(str(choice.get("next", ""))):
				push_error("Bad dialogue choice target at: " + str(id))
				return {}
	return graph
