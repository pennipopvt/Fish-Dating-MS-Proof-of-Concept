extends Node

# From the Godot project folder:
#   godot --headless --path . res://tests/date_schedule_test.tscn
# Tests date eligibility, calendar scheduling, and first-action appointments.

var _failures: int = 0


func _ready() -> void:
	# DateManager's signal connections are deferred until autoloads are ready.
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.reset_clock()

	var beach := DateManager.get_date(&"silas_beach")
	var boat := DateManager.get_date(&"silas_ship")
	_expect(beach != null and boat != null, "Silas's dates are available")
	if beach == null or boat == null:
		get_tree().quit(1)
		return

	var flags: Dictionary = NPCManager.get_npc_state(&"test_npc")["flags"]
	flags[&"Recruited"] = true
	_expect(not DateManager.can_book_at(beach, 1, GameManager.Times.AFTERNOON),
		"Dates are locked until Silas's first romance route finishes")
	flags[&"silas_route_complete"] = true

	_expect(DateManager.can_book_at(beach, 1, GameManager.Times.AFTERNOON),
		"Completed romance route unlocks future date slots")
	_expect(not DateManager.can_book_at(beach, 1, GameManager.Times.MORNING),
		"Cannot book the current period")
	_expect(DateManager.book_at(beach, 1, GameManager.Times.AFTERNOON),
		"Can book tomorrow / next period from the terminal")
	_expect(not DateManager.can_book_at(boat, 1, GameManager.Times.AFTERNOON),
		"Can't double-book the same time slot")
	_expect(not DateManager.can_book_at(boat, 1, GameManager.Times.NIGHT),
		"Can't double-book the same NPC")

	GameManager.rest()
	_expect(DateManager.is_booking_ready(beach),
		"Appointment is ready at the first action of afternoon")
	GameManager.spend_actions(1)
	_expect(not DateManager.is_booked(beach),
		"Using first action causes the unstarted date to be missed")
	_expect(bool(flags.get(beach.get_missed_flag(), false)),
		"Missed-date story flag is recorded")

	GameManager.reset_clock()
	_expect(DateManager.book_at(beach, 2, GameManager.Times.MORNING),
		"Can rebook repeatable dates on a later day")
	GameManager.rest()
	GameManager.rest()
	GameManager.rest()
	_expect(DateManager.is_booking_ready(beach),
		"Booking becomes ready on the planned morning")
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
