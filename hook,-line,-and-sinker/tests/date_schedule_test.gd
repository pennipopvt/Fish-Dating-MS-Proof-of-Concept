extends Node

# Run from the Godot project folder:
#   godot --headless --path . res://tests/date_schedule_test.tscn
# NPC-only bookings, the meaning of "next", and first-action start rules.

var _failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.reset_clock()

	var beach := DateManager.get_date(&"silas_beach")
	var boat := DateManager.get_date(&"kuda_ship")
	_expect(beach != null and boat != null, "Silas beach and Kuda boat dates are present")
	if beach == null or boat == null:
		get_tree().quit(1)
		return

	_expect(DateManager.get_date(&"silas_ship") == null and DateManager.get_date(&"kuda_beach") == null,
		"Only one date is registered for each character")
	var kuda_flags: Dictionary = NPCManager.get_npc_state(boat.npc.npc_id)["flags"]
	kuda_flags[&"Recruited"] = true
	kuda_flags[&"barracuda_route_complete"] = true
	var flags: Dictionary = NPCManager.get_npc_state(beach.npc.npc_id)["flags"]
	flags[&"Recruited"] = true
	_expect(not DateManager.can_ask(beach), "Date is locked until first romance scene")
	flags[&"silas_route_complete"] = true
	_expect(DateManager.can_ask(beach), "Finished romance route allows asking out")
	var encounter := NPCManager.get_encounter_json_path(beach.npc)
	_expect(encounter == "res://dialogue/silas_post_romance.json",
		"Post-romance interaction offers NPC-side date scheduling")
	var dialogue := DialogueJsonLoader.read_graph(encounter)
	_expect(not dialogue.is_empty(), "Ask-out dialogue graph is valid")
	_expect(DateManager.book_next_period(beach, GameManager.Times.AFTERNOON, 1, GameManager.Times.MORNING),
		"NPC can schedule the next afternoon")
	_expect(DateManager.describe_booking(beach) == "Day 1 Afternoon",
		"Calendar shows the day and period chosen in conversation")
	_expect(not DateManager.can_book_at(boat, 1, GameManager.Times.AFTERNOON),
		"Different NPCs cannot be booked in the same period")
	_expect(DateManager.can_book_at(boat, 1, GameManager.Times.NIGHT),
		"Kuda can book a different free period while Silas has a date")

	GameManager.rest()
	_expect(DateManager.is_booking_ready(beach), "Date becomes ready at first afternoon action")
	_expect(DateManager.get_ready_booking_for_npc(&"test_npc") == beach,
		"Talking to the NPC can start their planned date")
	GameManager.spend_actions(1)
	_expect(not DateManager.is_booked(beach), "Using the first action misses the date")
	_expect(bool(flags.get(beach.get_missed_flag(), false)), "Missed flag is recorded")

	GameManager.reset_clock()
	_expect(DateManager.book_next_period(beach, GameManager.Times.MORNING, 1, GameManager.Times.MORNING),
		"Next morning means TOMORROW when asked in morning")
	_expect(DateManager.describe_booking(beach) == "Day 2 Morning",
		"Next occurrence of same period is next day")
	DateManager.cancel_booking(beach)

	# The conversation may spend its last action BEFORE scene_requested fires.
	# Booking still points to the NEXT period chosen at conversation start.
	GameManager.reset_clock()
	GameManager.spend_actions(3)
	_expect(DateManager.book_next_period(beach, GameManager.Times.AFTERNOON, 1, GameManager.Times.MORNING),
		"After a clock rollover, NPC's chosen next afternoon is still today")
	_expect(DateManager.is_booking_ready(beach), "Rollover booking begins at first action")
	DateManager.cancel_booking(beach)
	GameManager.reset_clock()

	print("date_schedule_test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, explanation: String) -> void:
	if ok:
		print("  ok   ", explanation)
	else:
		_failures += 1
		print("  FAIL ", explanation)
