extends Node

# Run: godot --headless --path . res://tests/room_lighting_test.tscn
# Room appearance comes from the existing GameManager clock and a single
# Inspector-editable resource, without dimming the dialogue portrait.
const ROOM: PackedScene = preload("res://scenes/npc_room_view.tscn")
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameManager.reset_clock()
	var view: NPCRoomView = ROOM.instantiate() as NPCRoomView
	add_child(view)
	await get_tree().process_frame
	var background: TextureRect = view.get_node("Background") as TextureRect
	var backdrop: ColorRect = view.get_node("Backdrop") as ColorRect
	var profile: RoomLightingProfile = view.lighting_profile
	_check(profile != null, "All NPC rooms use a shared editable lighting profile")
	_check(profile.base_brightness < 1.0,
		"All rooms are a little darker by default, independently of time of day")
	_check(background.modulate.is_equal_approx(
		profile.color_for_period(GameManager.Times.MORNING)),
		"Day 1 morning begins with the shared warm room tint")
	_check(background.modulate.r > background.modulate.b,
		"Morning has a warm orange-yellow bias")

	GameManager.rest()
	_check(GameManager.is_period(GameManager.Times.AFTERNOON)
		and background.modulate.is_equal_approx(
			profile.color_for_period(GameManager.Times.AFTERNOON)),
		"Changing the existing game clock instantly updates afternoon room lighting")
	_check(is_equal_approx(background.modulate.r, background.modulate.g)
		and is_equal_approx(background.modulate.g, background.modulate.b),
		"Afternoon has no color tint, only a general brightness adjustment")

	GameManager.rest()
	_check(GameManager.is_period(GameManager.Times.NIGHT)
		and background.modulate.is_equal_approx(
			profile.color_for_period(GameManager.Times.NIGHT)),
		"Night uses a deeper, cooler room color")
	_check(background.modulate.b > background.modulate.r
		and background.modulate.get_luminance()
		< profile.color_for_period(GameManager.Times.AFTERNOON).get_luminance(),
		"Night looks blue and is darker than afternoon")

	# This is how morning-after scenes work: sleeping advances the clock
	# while the room stays open, so its background must refresh immediately.
	GameManager.rest()
	_check(GameManager.is_period(GameManager.Times.MORNING)
		and background.modulate.is_equal_approx(
			profile.color_for_period(GameManager.Times.MORNING)),
		"Overnight transitions restore warm morning lighting in the same room")
	_check(view.modulate == Color.WHITE and backdrop.modulate == Color.WHITE,
		"Only the background is tinted, leaving the portrait and UI unaffected")

	# The resource can be tuned in the Inspector without changing the clock,
	# other UI or per-NPC room backgrounds.
	var custom: RoomLightingProfile = profile.duplicate() as RoomLightingProfile
	custom.base_brightness = 0.65
	view.lighting_profile = custom
	view._refresh_room_lighting()
	_check(background.modulate.is_equal_approx(
			custom.color_for_period(GameManager.Times.MORNING)),
		"Changing the shared brightness setting changes the room appearance")
	_check(background.modulate.get_luminance()
		< profile.color_for_period(GameManager.Times.MORNING).get_luminance(),
		"Lower global brightness darkens the room with the same tint")

	view.queue_free()
	GameManager.reset_clock()
	print("room_lighting_test: PASS" if failures == 0 else
		"room_lighting_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
