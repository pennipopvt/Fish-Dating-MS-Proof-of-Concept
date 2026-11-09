extends Node

# Tracks challenge progress from fishing events, saves completion,
# and tells the shop which trades are still locked behind a challenge.

signal challenge_progressed(challenge: ChallengeData)
signal challenge_completed(challenge: ChallengeData)
signal streak_changed(streak: int)
signal progress_reset

const SAVE_PATH := "user://challenges.cfg"

# Debug hotkeys (project Input Map). Ignored in release exports.
const ACTION_RESET := &"debug_reset_challenges"          # F9
const ACTION_TEST_POPUP := &"debug_test_challenge_popup"  # F10

## Order here is the order shown in the Challenges tab.
@export var challenges: Array[ChallengeData] = []

## Fish caught in a row without losing one (any species).
var catch_streak: int = 0

@onready var _toast: ChallengeToast = $ChallengeToast
@onready var _unlock_sfx: AudioStreamPlayer = $UnlockSfx


func _ready() -> void:
	_load()
	FishingManager.fish_caught.connect(_on_fish_caught)
	FishingManager.fish_lost.connect(_on_fish_lost)


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return

	if event.is_action_pressed(ACTION_RESET):
		reset_all()
		print("Challenges: progress reset")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACTION_TEST_POPUP):
		test_popup()
		get_viewport().set_input_as_handled()


# Debug: show the unlock popup for the 3-fish challenge without completing it.
func test_popup() -> void:
	var preview: ChallengeData = null
	for challenge in challenges:
		if challenge == null:
			continue
		if preview == null:
			preview = challenge
		if challenge.requirement_type == ChallengeData.RequirementType.CONSECUTIVE_CATCHES \
				and challenge.target_amount == 3:
			preview = challenge
			break

	if preview == null:
		return

	_toast.show_challenge(preview)
	if _unlock_sfx.stream != null:
		_unlock_sfx.play()


# FishingManager.fish_caught emits the caught fish's ItemData (item.item_data).
func _on_fish_caught(item: ItemData) -> void:
	catch_streak += 1
	streak_changed.emit(catch_streak)

	var changed := false
	for challenge in challenges:
		if challenge == null or challenge.completed or not challenge.counts_item(item):
			continue

		changed = true
		if challenge.record_catch(item):
			_complete(challenge)
		else:
			challenge_progressed.emit(challenge)

	if changed:
		_save()


# Any lost fish (line snapped, fish escaped, or walking away mid-fight) ends the streak.
func _on_fish_lost(_fish: FishData) -> void:
	if catch_streak != 0:
		catch_streak = 0
		streak_changed.emit(catch_streak)

	var changed := false
	for challenge in challenges:
		if challenge != null and challenge.record_loss():
			changed = true
			challenge_progressed.emit(challenge)

	if changed:
		_save()


func _complete(challenge: ChallengeData) -> void:
	challenge.progress = challenge.target_amount
	challenge.completed = true
	challenge.completed_at = int(Time.get_unix_time_from_system())

	print("Challenge completed: ", challenge.challenge_id)
	challenge_completed.emit(challenge)
	_toast.show_challenge(challenge)

	if _unlock_sfx.stream != null:
		_unlock_sfx.play()


# ---- Queries -------------------------------------------------------------

func is_trade_locked(trade: TradeData) -> bool:
	return get_locking_challenge(trade) != null


# The first incomplete challenge that rewards this trade, or null if it's unlocked.
func get_locking_challenge(trade: TradeData) -> ChallengeData:
	for challenge in challenges:
		if challenge != null and not challenge.completed and challenge.unlocks_trade(trade):
			return challenge
	return null


func get_completed_count() -> int:
	var count := 0
	for challenge in challenges:
		if challenge != null and challenge.completed:
			count += 1
	return count


func get_total_count() -> int:
	var count := 0
	for challenge in challenges:
		if challenge != null:
			count += 1
	return count


# ---- Save / load ---------------------------------------------------------

func _save() -> void:
	var config := ConfigFile.new()

	for challenge in challenges:
		if challenge == null or challenge.challenge_id == &"":
			continue

		var section := String(challenge.challenge_id)
		config.set_value(section, "progress", challenge.progress)
		config.set_value(section, "completed", challenge.completed)
		config.set_value(section, "completed_at", challenge.completed_at)

	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save challenges to %s (error %d)" % [SAVE_PATH, error])


func _load() -> void:
	for challenge in challenges:
		if challenge != null:
			_reset_state(challenge)

	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return

	for challenge in challenges:
		if challenge == null or challenge.challenge_id == &"":
			continue

		var section := String(challenge.challenge_id)
		if not config.has_section(section):
			continue

		challenge.completed = bool(config.get_value(section, "completed", false))
		challenge.completed_at = int(config.get_value(section, "completed_at", 0))
		challenge.progress = clampi(
			int(config.get_value(section, "progress", 0)), 0, challenge.target_amount
		)

		if challenge.completed:
			challenge.progress = challenge.target_amount


# Debug helper: wipe all challenge progress and the save file.
func reset_all() -> void:
	catch_streak = 0
	streak_changed.emit(catch_streak)
	for challenge in challenges:
		if challenge != null:
			_reset_state(challenge)

	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	progress_reset.emit()


func _reset_state(challenge: ChallengeData) -> void:
	challenge.progress = 0
	challenge.completed = false
	challenge.completed_at = 0
