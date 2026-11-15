extends Node

# Prototype FISH CO. employment contract. Quotas are inventory submissions,
# not a catch counter: surrendered fish cannot also buy upgrades or gifts.
signal quota_changed
signal quota_completed(week: int)
signal quota_failed(week: int)

const WEEK_DAYS: int = 7
const EASY_FISH_ID: StringName = &"easy_test_fish"
const HARD_FISH_ID: StringName = &"hard_test_fish"

var week: int = 1
var deadline_day: int = WEEK_DAYS
var requirements: Array[Dictionary] = []
var delivered: Dictionary = {}
var failed: bool = false
var _failure_layer: CanvasLayer = null


func _ready() -> void:
	_start_week(1)
	GameManager.day_started.connect(_on_day_started)


static func week_for_day(day: int) -> int:
	return maxi(1, (maxi(1, day) - 1) / WEEK_DAYS + 1)


static func deadline_for_week(for_week: int) -> int:
	return maxi(1, for_week) * WEEK_DAYS


static func targets_for_week(for_week: int) -> Array[Dictionary]:
	# Escalating temporary playtest numbers; replace with authored contracts
	# once we can evaluate how much time dating competes with fishing.
	var difficulty := maxi(0, for_week - 1)
	return [
		{"item_id": EASY_FISH_ID, "label": "Common fish", "target": 5 + difficulty * 2},
		{"item_id": HARD_FISH_ID, "label": "Hard fish", "target": 1 + difficulty},
	]


func _start_week(for_week: int) -> void:
	week = maxi(1, for_week)
	deadline_day = deadline_for_week(week)
	requirements = targets_for_week(week)
	delivered.clear()
	failed = false
	quota_changed.emit()


func get_target(item_id: StringName) -> int:
	for requirement in requirements:
		if requirement["item_id"] == item_id:
			return int(requirement["target"])
	return 0


func get_delivered(item_id: StringName) -> int:
	return int(delivered.get(item_id, 0))


func get_remaining(item_id: StringName) -> int:
	return maxi(0, get_target(item_id) - get_delivered(item_id))


func is_complete() -> bool:
	for requirement in requirements:
		if get_remaining(requirement["item_id"]) > 0:
			return false
	return true


func submit(item_id: StringName, amount: int = -1) -> int:
	# Returns the number of fish actually transferred to the company.
	# The storage removal is all-or-nothing for the chosen batch.
	if failed or is_complete():
		return 0
	var remaining := get_remaining(item_id)
	if remaining <= 0:
		return 0
	var available := FishingManager.count_in_storage(item_id)
	var requested := available if amount < 0 else amount
	var take := mini(remaining, mini(available, requested))
	if take <= 0 or not FishingManager.remove_from_storage(item_id, take):
		return 0
	delivered[item_id] = get_delivered(item_id) + take
	quota_changed.emit()
	if is_complete():
		quota_completed.emit(week)
	return take


func _on_day_started(day: int) -> void:
	if failed or day <= deadline_day:
		return
	# Due at the END of night on the displayed deadline day. The player can
	# still submit during day 7; failure happens when day 8 begins.
	if not is_complete():
		failed = true
		quota_failed.emit(week)
		_show_failure()
		return
	_start_week(week_for_day(day))


func reset_run() -> void:
	if is_instance_valid(_failure_layer):
		_failure_layer.queue_free()
	_failure_layer = null
	get_tree().paused = false
	_start_week(1)


func _show_failure() -> void:
	# Deliberately simple prototype ending: failure ends the current run.
	# Restart the game from the editor to begin again.
	_failure_layer = CanvasLayer.new()
	_failure_layer.layer = 256
	_failure_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_failure_layer)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.05, 0.06, 0.94)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_failure_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 300)
	panel.theme = PixelUI.get_theme()
	panel.add_theme_stylebox_override("panel", preload("res://resources/ui/terminal_border.tres"))
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 30)
	panel.add_child(margin)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	margin.add_child(body)

	var title := PixelUI.label("FISH CO. / CONTRACT TERMINATED", &"HeaderLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)

	var message := PixelUI.label(
		"WEEK %d QUOTA INCOMPLETE\n\nEMPLOYMENT TERMINATED.\nYOUR RUN HAS ENDED." % week,
		&"TitleLabel"
	)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(message)

	var instruction := PixelUI.label("Restart the game to begin a new run.", &"DimLabel")
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(instruction)
	get_tree().paused = true
