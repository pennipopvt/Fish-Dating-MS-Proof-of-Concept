extends Node

# Run from the project folder:
#   godot --headless --path . res://tests/dev_panel_npc_flags_test.tscn
# The F9 flag editor must not display Kuda's definitions on Silas or vice versa.

var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	NPCManager.npc_states.clear()

	var silas_id := &"test_npc"
	var kuda_id := &"barracuda"
	var silas_flags: Array[StringName] = DevPanel.call("_known_flags", silas_id)
	var kuda_flags: Array[StringName] = DevPanel.call("_known_flags", kuda_id)

	_expect(silas_flags.has(&"silas_route_complete"), "Silas's romance flag appears on Silas")
	_expect(silas_flags.has(&"date_ok_silas_beach"), "Silas's date flags appear on Silas")
	_expect(not silas_flags.has(&"barracuda_invitation_accepted"),
		"Silas is not offered Kuda's invitation flag")
	_expect(not silas_flags.has(&"date_ok_kuda_beach"),
		"Silas is not offered Kuda's date flags")

	_expect(kuda_flags.has(&"barracuda_route_complete"), "Kuda's romance flag appears on Kuda")
	_expect(kuda_flags.has(&"date_ok_kuda_beach"), "Kuda's date flags appear on Kuda")
	_expect(not kuda_flags.has(&"silas_route_complete"),
		"Kuda is not offered Silas's romance flag")
	_expect(not kuda_flags.has(&"date_ok_silas_beach"),
		"Kuda is not offered Silas's date flags")

	# NPCManager owns two different dictionaries, not a single shared flags set.
	var silas_state := NPCManager.get_npc_state(silas_id)
	var kuda_state := NPCManager.get_npc_state(kuda_id)
	silas_state["flags"][&"silas_route_complete"] = true
	_expect(not kuda_state["flags"].has(&"silas_route_complete"),
		"Changing Silas flags does not modify Kuda's flags")
	kuda_state["flags"][&"barracuda_route_complete"] = true
	_expect(not silas_state["flags"].has(&"barracuda_route_complete"),
		"Changing Kuda flags does not modify Silas's flags")

	DevPanel.call("_rebuild_flags")
	var npc_picker := DevPanel.get("_flag_npc") as OptionButton
	_expect(npc_picker.item_count >= 2, "Both NPCs appear before being encountered")
	var silas_option := -1
	var kuda_option := -1
	for i in range(npc_picker.item_count):
		var id := str(npc_picker.get_item_metadata(i))
		if id == String(silas_id):
			silas_option = i
			_expect(npc_picker.get_item_text(i).begins_with("Silas"),
				"Silas is named in the dropdown")
		if id == String(kuda_id):
			kuda_option = i
			_expect(npc_picker.get_item_text(i).begins_with("Kuda"),
				"Kuda is named in the dropdown")
	_expect(silas_option >= 0 and kuda_option >= 0, "Both NPCs have independent selectable IDs")
	if kuda_option >= 0:
		npc_picker.select(kuda_option)
		DevPanel.call("_rebuild_flags")
		var rebuilt := DevPanel.get("_flag_npc") as OptionButton
		_expect(str(rebuilt.get_item_metadata(rebuilt.selected)) == String(kuda_id),
			"Rebuilding the flag editor keeps Kuda selected")

	NPCManager.npc_states.clear()
	print("dev_panel_npc_flags_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _expect(ok: bool, message: String) -> void:
	if ok:
		print("  ok   ", message)
	else:
		failures += 1
		push_error("  FAIL " + message)
