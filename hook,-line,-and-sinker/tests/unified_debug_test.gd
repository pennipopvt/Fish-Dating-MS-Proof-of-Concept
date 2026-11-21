extends Node

# F3 menu owns all developer controls; old F7/backslash overlays stay hidden.
# Room previews use the existing iris + DialogueUI, without recruiting actors.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
var failures: int = 0
var stage: String = "startup"


func _ready() -> void:
	call_deferred("_run")


func _watchdog() -> void:
	await get_tree().create_timer(20.0).timeout
	push_error("Unified debug test timed out at: " + stage)
	get_tree().quit(1)


func _run() -> void:
	_watchdog()
	var main: Control = MAIN.instantiate() as Control
	# SceneTree.current_scene must be a direct root child, as in real play.
	# This also exercises the DevPanel autoload's normal scene lookup.
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var water: ColorRect = world.get_node("Water") as ColorRect
	var player: Player = world.get_node("Player") as Player
	var room: NPCRoomView = main.get_node("NPCRoomView") as NPCRoomView
	var dialogue: DialogueUI = main.get_node("CanvasLayer/DialogueUI") as DialogueUI
	var water_probe: WaterRenderDebug = main.get_node("WaterDebugLayer") as WaterRenderDebug
	var sea_probe: SeaDebugPanel = main.get_node("SeaDebugLayer") as SeaDebugPanel
	var tabs: TabContainer = DevPanel.get("_tabs") as TabContainer
	var debug_tabs: TabContainer = DevPanel.get("_debug_tabs") as TabContainer
	var tab_names: Array[String] = []
	for i in tabs.get_tab_count():
		tab_names.append(String(tabs.get_tab_control(i).name))
	_check(tab_names.has("Debug") and tab_names.has("Flags") and tab_names.has("Fishing"),
		"Existing developer tools plus unified Debug tab coexist")
	_check(debug_tabs.get_tab_count() == 3
		and String(debug_tabs.get_tab_control(0).name) == "Jump"
		and String(debug_tabs.get_tab_control(1).name) == "Sea"
		and String(debug_tabs.get_tab_control(2).name) == "Water",
		"Jump, Sea, and Water live in one F3 developer panel")
	var mapped_f3: bool = false
	for event in InputMap.action_get_events("debug_panel"):
		var key := event as InputEventKey
		if key != null and key.physical_keycode == KEY_F3:
			mapped_f3 = true
	_check(mapped_f3, "F3 is mapped to the developer panel")
	_check(not InputMap.has_action("debug_clock_overlay")
		and not water_probe.visible and not sea_probe.visible,
		"Old clock binding and separate diagnostic panels are disabled")

	# The renderer is still the exact same node: menu commands only change
	# reversible probe state; none of the sea/land gameplay scripts move.
	stage = "render probes"
	var original_mat: Material = water.material
	DevPanel.call("_set_water_view", 4)
	_check(water_probe.mode == 4 and water.material == null
		and water.color == Color(1, 0, 1, 1)
		and not water_probe.visible and not sea_probe.visible,
		"Solid magenta water is available without opening another menu")
	DevPanel.call("_restore_water_view")
	_check(water.material == original_mat and water_probe.mode == 0,
		"Restoring water returns its original shader/material")
	var sea_text: String = sea_probe.diagnostics_text()
	_check(sea_text.contains("SEA DEBUG"), "Existing sea diagnostics are readable in unified panel")

	stage = "room preview"
	DevPanel.call("_jump_to_room", SILAS.npc_id)
	await get_tree().create_timer(1.55).timeout
	_check(room.visible and dialogue.visible and bool(dialogue.get("_room_mode"))
		and player.busy, "Jump starts the existing iris, room scene and DialogueUI")
	_check(not RecruitmentHandler.is_resident(SILAS.npc_id),
		"Room preview does not recruit the NPC or allocate a house")
	var room_position: Vector2 = player.global_position
	stage = "leaving preview"
	DevPanel.call("_leave_preview_room")
	await get_tree().create_timer(1.55).timeout
	_check(not room.visible and not dialogue.visible and not player.busy
		and not bool(dialogue.get("_room_mode"))
		and player.global_position == room_position,
		"Leave Room restores the island without moving Penni or leaving dialogue active")
	_check(not water_probe.visible and not sea_probe.visible,
		"No F7 or backslash overlay appears during room preview")
	DevPanel.hide()
	get_tree().current_scene = null
	main.queue_free()
	await get_tree().process_frame
	print("unified_debug_test: PASS" if failures == 0 else
		"unified_debug_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("PASS " if ok else "FAIL ") + note)
	if not ok:
		failures += 1
