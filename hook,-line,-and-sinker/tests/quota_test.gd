extends Node

# godot --headless --path . res://tests/quota_test.tscn
# Weekly inventory submissions, calendar deadline and termination behavior.
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

	_expect(QuotaManager.week == 1 and QuotaManager.deadline_day == 7,
		"Week one quota is due at the end of day seven")
	_expect(QuotaManager.get_target(&"easy_test_fish") == 5
		and QuotaManager.get_target(&"hard_test_fish") == 1,
		"First week's targets start at five common and one hard fish")
	FishingManager.add_to_storage(EASY, 8)
	FishingManager.add_to_storage(HARD, 1)
	_expect(QuotaManager.submit(&"easy_test_fish", 2) == 2,
		"Partial submission immediately accepts two common fish")
	_expect(FishingManager.count_in_storage(&"easy_test_fish") == 6,
		"Submitted fish are removed from inventory, not just counted")
	_expect(QuotaManager.submit(&"easy_test_fish") == 3,
		"Send available submits only the remaining three quota fish")
	_expect(FishingManager.count_in_storage(&"easy_test_fish") == 3,
		"Extra fish remain in storage for upgrades and gifts")
	_expect(QuotaManager.submit(&"easy_test_fish") == 0,
		"Cannot submit excess fish after a target is filled")
	_expect(not QuotaManager.is_complete(), "Common fish alone do not complete the contract")
	_expect(QuotaManager.submit(&"hard_test_fish") == 1,
		"Hard fish submit through the same inventory API")
	_expect(QuotaManager.is_complete(), "Both deliveries finish the week's quota")
	_expect(FishingManager.count_in_storage(&"hard_test_fish") == 0,
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
	shop.call("_select_default_schedule_slot")
	shop.set("_page", ShopMenu.Page.SCHEDULE)
	shop.call("_refresh_schedule_page")
	var last_slot := shop.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/ScheduleDays").get_child(3).find_children("*", "Button", true, false)
	# Day 7 is outside the initial 4-day window. Check at day 4.
	QuotaManager.call("_on_day_started", 5) # does not advance a completed quota early
	_expect(QuotaManager.week == 1, "Completed quota stays active until deadline passes")
	shop.queue_free()

	QuotaManager.call("_on_day_started", 8)
	_expect(QuotaManager.week == 2 and QuotaManager.deadline_day == 14,
		"Completing the contract opens next week's quota on day eight")
	_expect(QuotaManager.get_target(&"easy_test_fish") == 7
		and QuotaManager.get_target(&"hard_test_fish") == 2,
		"Second week's targets increase")
	QuotaManager.call("_on_day_started", 14)
	_expect(not QuotaManager.failed, "Day fourteen remains available for last-minute submissions")
	QuotaManager.call("_on_day_started", 15)
	_expect(QuotaManager.failed and get_tree().paused,
		"An incomplete quota ends the run when next week begins")
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
