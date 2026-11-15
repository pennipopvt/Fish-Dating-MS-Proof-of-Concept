extends Node

# Run from the project folder:
#   godot --headless --path . res://tests/schedule_ui_test.tscn
# Schedule uses 4 x 9 action slots; no booking control appears in the terminal.
# Greeting/bye is free, meaningful NPC dialogue costs an action, and the
# spyglass bubble shares the terminal's authored nine-slice artwork.

const SHOP_SCENE: PackedScene = preload("res://prefabs/shop_menu.tscn")
const BUBBLE_SCENE: PackedScene = preload("res://prefabs/ui/speech_bubble.tscn")
const SILAS: NPCData = preload("res://resources/npcs/test_npc.tres")
const TERMINAL_TEXTURE: Texture2D = preload("res://sprites/ui/ui_background_3x.png")
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.reset_clock()
	var flags: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)["flags"]
	flags[&"Recruited"] = true
	flags[&"silas_route_complete"] = true

	var shop := SHOP_SCENE.instantiate() as ShopMenu
	add_child(shop)
	shop.call("_select_default_schedule_slot")
	shop.set("_page", 5)
	shop.call("_refresh_schedule_page")
	var grid := shop.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/ScheduleDays") as HBoxContainer
	var old_scroll := shop.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/GridScroll") as ScrollContainer
	_expect(grid.visible and not old_scroll.visible, "Schedule is visible without using the shop scroll container")
	_expect(grid.get_child_count() == 4, "Current day and three future days are displayed")
	_expect(not shop.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/PageTitle").visible, "Redundant page title is hidden to save vertical space")
	_expect(not shop.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/PageHint").visible, "Redundant hint is hidden to save vertical space")
	var today := grid.get_child(0) as PanelContainer
	var future_day := grid.get_child(1) as PanelContainer
	_expect(today.size_flags_stretch_ratio > future_day.size_flags_stretch_ratio,
		"Today's column is wider than future days")
	_expect(today.get_theme_stylebox("panel") is StyleBoxTexture,
		"Day columns retain the terminal's strong 9-slice borders")
	for day in grid.get_children():
		var actions := day.find_children("*", "Button", true, false)
		var dividers := day.find_children("*", "ColorRect", true, false)
		_expect(actions.size() == 9, "Each day has nine action slots")
		_expect(dividers.size() == 8, "Only soft dividers separate actions and periods")
		if not actions.is_empty():
			_expect((actions[0] as Button).get_theme_stylebox("normal") is StyleBoxEmpty,
				"Individual action slots no longer have hard 9-slice borders")
	var day_one_actions := today.find_children("*", "Button", true, false)
	_expect((day_one_actions[0] as Button).text.begins_with("> 1"), "First action is marked NOW")
	GameManager.spend_actions(1)
	shop.call("_refresh_schedule_page")
	grid = shop.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/ScheduleDays")
	day_one_actions = grid.get_child(0).find_children("*", "Button", true, false)
	_expect((day_one_actions[1] as Button).text.begins_with("> 2"), "Current-action marker advances after use")

	var beach := DateManager.get_date(&"silas_beach")
	_expect(DateManager.book_at(beach, GameManager.get_day() + 1, GameManager.Times.AFTERNOON), "An NPC-booked date appears on the calendar")
	shop.call("_refresh_schedule_page")
	grid = shop.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/ScheduleDays")
	var tomorrow := grid.get_child(1).find_children("*", "Button", true, false)
	_expect((tomorrow[3] as Button).text.contains("SILAS"), "Booked date appears in afternoon's first-action slot")
	_expect((tomorrow[4] as Button).text.contains("DATE"), "The booked date reserves the next two actions")
	DateManager.cancel_booking(beach)
	shop.queue_free()

	GameManager.reset_clock()
	DialogueManager.start_conversation(SILAS, "res://dialogue/silas_post_romance.json")
	_finish_conversation_with_choice("See you later!")
	_expect(DialogueManager.last_conversation_cost == 0, "A hello and direct goodbye costs zero actions")
	_expect(GameManager.get_actions_left() == 3, "Goodbye does not advance the clock")

	DialogueManager.start_conversation(SILAS, "res://dialogue/silas_post_romance.json")
	_finish_conversation_with_choice("Want to go on a date?")
	_expect(DialogueManager.last_conversation_cost == 1, "Real conversation takes an action")
	_expect(GameManager.get_actions_left() == 2, "Calendar reflects the action spent on a real topic")

	var bubble := BUBBLE_SCENE.instantiate() as SpeechBubble
	add_child(bubble)
	_expect(bubble.texture == TERMINAL_TEXTURE, "Speech bubble reuses the terminal nine-slice texture")
	_expect(bubble.get_node_or_null("TailOutline") != null, "Bubble has a pointed tail")
	bubble.set_content(TERMINAL_TEXTURE)
	_expect((bubble.get_node("Icon") as TextureRect).visible, "Spyglass fish thumbnail is supported")
	bubble.queue_free()

	print("schedule_ui_test: %s" % ("PASS" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(0 if _failed == 0 else 1)


func _finish_conversation_with_choice(needle: String) -> void:
	for step in 20:
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			break
		DialogueManager.advance()
	var selected := -1
	for i in DialogueManager.get_choices().size():
		if DialogueManager.get_choices()[i].text == needle:
			selected = i
	_expect(selected >= 0, "Dialogue exposes '%s'" % needle)
	if selected < 0:
		DialogueManager.end_conversation()
		return
	DialogueManager.select_choice(selected)
	# "Want to go on a date?" enters another choice screen; abandon the plan.
	for step in 30:
		if not DialogueManager.is_active:
			break
		if DialogueManager.is_awaiting_choice():
			var choices := DialogueManager.get_choices()
			var cancel := -1
			for i in choices.size():
				if choices[i].text == "Actually, never mind.":
					cancel = i
				elif choices[i].text == "Maybe another time.":
					cancel = i
			if cancel < 0:
				break
			DialogueManager.select_choice(cancel)
		else:
			DialogueManager.advance()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failed += 1
		push_error("  FAIL " + message)
