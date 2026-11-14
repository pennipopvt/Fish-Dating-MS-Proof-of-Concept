extends Node

# Debug test for the GameManager day clock. Uses autoloads, so it runs as a
# scene, not with -s. From the Godot project folder:
#   godot --headless --path . res://tests/day_clock_test.tscn
# Exits with code 1 if any check fails. Never touches the real save file.

const TEST_SAVE: String = "user://day_clock_test.cfg"
const BED_SCENE: PackedScene = preload("res://prefabs/bed.tscn")

var _failures: int = 0
# What a dependent system saw when it was notified.
var _seen: Array[String] = []


func _ready() -> void:
	# GameManager connects to other managers deferred; wait for that.
	await get_tree().process_frame
	GameManager.save_path = TEST_SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	GameManager.time_changed.connect(_on_time_changed)

	_test_period_advancement()
	_test_night_blocks_actions()
	_test_rest_and_rollover()
	await _test_bed()
	_test_dependents_read_new_values()
	_test_save_round_trip()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	print("day_clock_test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _test_period_advancement() -> void:
	GameManager.reset_clock()
	_expect_clock(1, GameManager.Times.MORNING, 3, "reset is day 1 morning with 3 actions")
	var fish := FishData.new()
	FishingManager.catch_fish(fish, false)
	_expect_clock(1, GameManager.Times.MORNING, 2, "a caught fish spends 1 action")
	FishingManager.lose_fish(fish)
	_expect_clock(1, GameManager.Times.MORNING, 1, "a lost fish spends 1 action")
	DialogueManager.conversation_finished.emit(null)
	_expect_clock(1, GameManager.Times.AFTERNOON, 3, "a finished talk spends the last action; afternoon starts")
	GameManager.spend_actions(3)
	_expect_clock(1, GameManager.Times.NIGHT, 3, "spending all afternoon actions starts night")
	GameManager.spend_actions(10)
	_expect_clock(1, GameManager.Times.NIGHT, 0, "night doesn't roll over by itself")
	_expect(GameManager.get_save_data()["period"] == GameManager.Times.NIGHT, "save data reports night")


func _test_night_blocks_actions() -> void:
	_expect(not GameManager.can_act(), "can't act once night is spent")
	FishingManager.catch_fish(FishData.new(), false)
	DialogueManager.conversation_finished.emit(null)
	_expect_clock(1, GameManager.Times.NIGHT, 0, "more actions at spent night change nothing")
	_expect(_spends_time("res://prefabs/dock.tscn"), "dock costs time (blocked at spent night)")
	_expect(_spends_time("res://prefabs/test_npc.tscn"), "NPC talk costs time (blocked at spent night)")
	_expect(not _spends_time("res://prefabs/bed.tscn"), "bed is free (usable at spent night)")
	_expect(not _spends_time("res://prefabs/bait_box.tscn"), "bait menu is free")


func _test_rest_and_rollover() -> void:
	var new_days: Array[int] = []
	var on_day := func(d: int) -> void: new_days.append(d)
	GameManager.day_started.connect(on_day)
	GameManager.rest()
	_expect_clock(2, GameManager.Times.MORNING, 3, "resting at night starts the next day's morning")
	_expect(new_days == [2], "day_started fired once for day 2")
	GameManager.rest()
	_expect_clock(2, GameManager.Times.AFTERNOON, 3, "resting in the morning skips to afternoon")
	GameManager.spend_actions(1)
	GameManager.rest()
	_expect_clock(2, GameManager.Times.NIGHT, 3, "resting in the afternoon skips to night with fresh actions")
	_expect(new_days == [2], "no new day while skipping within a day")
	GameManager.day_started.disconnect(on_day)


func _test_bed() -> void:
	var bed := BED_SCENE.instantiate() as BedInteractable
	add_child(bed)
	# At night the bed fades out and back in before it's done; wait for it.
	await bed.interact(null)
	_expect_clock(3, GameManager.Times.MORNING, 3, "bed at night goes to day 3 morning")
	await bed.interact(null)
	_expect_clock(3, GameManager.Times.AFTERNOON, 3, "bed in the morning goes to afternoon")
	bed.queue_free()


func _test_dependents_read_new_values() -> void:
	_seen.clear()
	GameManager.rest()
	_expect(_seen == ["3 NIGHT NIGHT"], "a listener reads the new day/period inside time_changed (got %s)" % [_seen])
	_expect(GameManager.is_period(GameManager.Times.NIGHT) and GameManager.get_period_name() == "Night", "is_period / get_period_name")
	_seen.clear()
	GameManager.rest()
	_expect(_seen == ["4 MORNING MORNING"], "a listener reads day 4 morning after rollover (got %s)" % [_seen])
	_expect(GameManager.get_day() == 4 and GameManager.get_actions_left() == 3, "get_day / get_actions_left after rollover")


func _test_save_round_trip() -> void:
	GameManager.rest()
	GameManager.spend_actions(2)
	_expect_clock(4, GameManager.Times.AFTERNOON, 1, "setup for save")
	var config := ConfigFile.new()
	_expect(config.load(TEST_SAVE) == OK, "the clock was written to the save file")
	_expect(config.get_value("clock", "day", -1) == 4 and config.get_value("clock", "period", -1) == GameManager.Times.AFTERNOON and config.get_value("clock", "actions", -1) == 1, "save file holds day 4 afternoon, 1 action")

	# Scramble memory, then load like a fresh start.
	GameManager.load_save_data({})
	_expect_clock(1, GameManager.Times.MORNING, 3, "empty save data falls back to defaults")
	_expect(GameManager.load_from_disk(), "load_from_disk finds the clock")
	_expect_clock(4, GameManager.Times.AFTERNOON, 1, "loading restores day 4 afternoon, 1 action")

	GameManager.load_save_data({"day": -3, "period": 9, "actions": 99})
	_expect_clock(1, GameManager.Times.NIGHT, 3, "out-of-range save values are clamped")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	_expect(not GameManager.load_from_disk(), "no save file means nothing is loaded")


func _on_time_changed(d: int, t: GameManager.Times) -> void:
	# Mimics a shop/fish/NPC rule that reads the clock when notified.
	_seen.append("%d %s %s" % [d, GameManager.Times.keys()[t], GameManager.Times.keys()[GameManager.get_period()]])


func _spends_time(scene_path: String) -> bool:
	var node := (load(scene_path) as PackedScene).instantiate()
	var result: bool = node is Interactable and (node as Interactable).spends_time()
	node.free()
	return result


func _expect_clock(d: int, period: GameManager.Times, actions: int, message: String) -> void:
	var ok: bool = GameManager.get_day() == d and GameManager.get_period() == period and GameManager.get_actions_left() == actions
	if not ok:
		message += " (got day %d %s, %d actions)" % [GameManager.get_day(), GameManager.get_period_name(), GameManager.get_actions_left()]
	_expect(ok, message)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)
