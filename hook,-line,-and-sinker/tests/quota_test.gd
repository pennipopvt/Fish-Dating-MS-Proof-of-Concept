extends Node

# godot --headless --path . res://tests/quota_test.tscn
# Three-day inventory submissions, calendar deadline and termination behavior.
const EASY = preload("res://resources/items/easy_test_fish_item.tres")
const HARD = preload("res://resources/items/hard_test_fish_item.tres")
const SHOP = preload("res://prefabs/shop_menu.tscn")
var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	QuotaManager.reset_run()
	GameManager.reset_clock()
	var before_storage := FishingManager.current_storage.duplicate()
	FishingManager.current_storage.clear()
	FishingManager.storage_changed.emit()

	_expect(QuotaManager.week == 1 and QuotaManager.deadline_day == 3,
		"First quota is due at the end of day three")
	_expect(QuotaManager.get_target(&"placeholder_fish_a") == 5
		and QuotaManager.get_target(&"placeholder_fish_b") == 1,
		"First cycle targets start at five common and one hard fish")
	FishingManager.add_to_storage(EASY, 8)
	FishingManager.add_to_storage(HARD, 1)
	_expect(QuotaManager.submit(&"placeholder_fish_a", 2) == 2,
		"Partial submission immediately accepts two common fish")
	_expect(FishingManager.count_in_storage(&"placeholder_fish_a") == 6,
		"Submitted fish are removed from inventory, not just counted")
	_expect(QuotaManager.submit(&"placeholder_fish_a") == 3,
		"Send available submits only the remaining three quota fish")
	_expect(FishingManager.count_in_storage(&"placeholder_fish_a") == 3,
		"Extra fish remain in storage for upgrades and gifts")
	_expect(QuotaManager.submit(&"placeholder_fish_a") == 0,
		"Cannot submit excess fish after a target is filled")
	_expect(not QuotaManager.is_complete(), "Common fish alone do not complete the contract")
	_expect(QuotaManager.submit(&"placeholder_fish_b") == 1,
		"Hard fish submit through the same inventory API")
	_expect(QuotaManager.is_complete(), "Both deliveries finish the current quota")
	_expect(FishingManager.count_in_storage(&"placeholder_fish_b") == 0,
		"Hard fish cannot be spent twice")

	var shop := SHOP.instantiate() as ShopMenu
	add_child(shop)
	_expect(shop.get("_page") == ShopMenu.Page.QUOTA,
		"Quota is the terminal's default page")
	var quota_tab := shop.get_node("TerminalRoot/NavTabs/QuotaTab") as Button
	_expect(quota_tab.get_index() == 0, "Quota tab is visually first")
	shop.call("_refresh_quota_page")
	_expect(shop.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/QuotaView").visible,
		"Quota page renders submitted progress")
	# Today's four-column calendar shows the day-three deadline immediately.
	shop.call("_select_default_schedule_slot")
	shop.set("_page", ShopMenu.Page.SCHEDULE)
	shop.call("_refresh_schedule_page")
	var first_deadline := shop.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/ScheduleDays").get_child(2)
	var slots := first_deadline.find_children("*", "Button", true, false)
	_expect(slots.size() == 9 and (slots[8] as Button).text.contains("QUOTA"),
		"First deadline appears at the end of Day 3")
	QuotaManager.call("_on_day_started", 3)
	_expect(QuotaManager.week == 1 and not QuotaManager.failed,
		"Day three still belongs to the first quota")
	_expect(QuotaManager.cycle_for_day(3) == 1 and QuotaManager.cycle_for_day(4) == 2
		and QuotaManager.cycle_for_day(6) == 2 and QuotaManager.cycle_for_day(7) == 3,
		"Cycles begin on Days 1, 4, and 7")
	_expect(QuotaManager.deadline_for_cycle(2) == 6 and QuotaManager.deadline_for_cycle(3) == 9,
		"Every contract deadline is three days after the last one")

	# Complete first quota rolls over automatically when Day 4 starts.
	for step in range(9):
		GameManager.rest()
	_expect(GameManager.get_day() == 4, "Nine rests advance to day four")
	_expect(QuotaManager.week == 2 and QuotaManager.deadline_day == 6,
		"Second quota starts Day 4 and is due Day 6")
	_expect(QuotaManager.get_target(&"placeholder_fish_a") == 7
		and QuotaManager.get_target(&"placeholder_fish_b") == 2,
		"Second quota targets continue to increase")
	shop.call("_select_default_schedule_slot")
	shop.call("_refresh_schedule_page")
	var second_deadline := shop.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/ScheduleDays").get_child(2)
	var second_slots := second_deadline.find_children("*", "Button", true, false)
	_expect(second_slots.size() == 9 and (second_slots[8] as Button).text.contains("QUOTA"),
		"Second deadline appears at the end of Day 6")
	shop.queue_free()
	QuotaManager.call("_on_day_started", 6)
	_expect(not QuotaManager.failed, "The final deadline day remains available")
	QuotaManager.call("_on_day_started", 7)
	_expect(QuotaManager.failed and get_tree().paused,
		"Missing Day 6 quota ends the run when Day 7 begins")
	QuotaManager.reset_run()
	_expect(not get_tree().paused, "Resetting a run clears the termination screen")

	FishingManager.current_storage = before_storage
	FishingManager.storage_changed.emit()
	GameManager.reset_clock()
	print("quota_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _expect(ok: bool, label: String) -> void:
	if ok:
		print("  ok   ", label)
	else:
		failures += 1
		push_error("  FAIL " + label)
