extends Node

# godot --headless --path . res://tests/terminal_shop_challenges_test.tscn
# Regression for the combined shop, recruit-gated gifts, claimable
# achievements, notification bubble, and one-time upgrade ownership.

const SHOP_MENU = preload("res://prefabs/shop_menu.tscn")
const TERMINAL = preload("res://prefabs/shop.tscn")
const QUOTA_ICON = preload("res://sprites/ui/icon_quota.png")
const SCHEDULE_ICON = preload("res://sprites/ui/icon_schedule.png")
const SCARF = preload("res://resources/trades/kuda_scarf.tres")
const REEL = preload("res://resources/trades/stronger_reel.tres")
const LINE = preload("res://resources/trades/reinforced_line.tres")
const CAST = preload("res://resources/trades/increase_casts.tres")
var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var previous_states := NPCManager.npc_states.duplicate(true)
	NPCManager.npc_states.clear()
	ChallengeManager.reset_all()
	FishingManager.reset_session_upgrades()

	var shop := SHOP_MENU.instantiate() as ShopMenu
	add_child(shop)
	_expect(shop.get("_page") == ShopMenu.Page.QUOTA, "Quota is the first page")
	var quota_icon := shop.get_node("TerminalRoot/NavTabs/QuotaTab/Icon") as TextureRect
	var schedule_icon := shop.get_node("TerminalRoot/NavTabs/ScheduleTab/Icon") as TextureRect
	_expect(quota_icon.texture == QUOTA_ICON and QUOTA_ICON.get_size() == Vector2(16, 16),
		"Quota tab uses the supplied 16x16 PNG")
	_expect(schedule_icon.texture == SCHEDULE_ICON and SCHEDULE_ICON.get_size() == Vector2(16, 16),
		"Schedule tab uses the supplied 16x16 PNG")
	_expect((shop.get("_nav_buttons") as Array).size() == 6,
		"Six terminal tabs remain after merging gifts and upgrades")
	var nav := shop.get_node("TerminalRoot/NavTabs") as VBoxContainer
	_expect(nav.get_child(1).name == "ShopTab", "Shop is the second outer tab")
	_expect(nav.get_child_count() == 6, "There is no standalone Gifts tab")
	shop.call("_select_page", ShopMenu.Page.SHOP)
	_expect(not (shop.get("_shop_gifts") as Button).visible,
		"Gifts are hidden before the first NPC is recruited")
	_expect(not ShopManager.can_trade(SCARF),
		"Shop purchase API also blocks gifts before first recruitment")

	var silas_flags: Dictionary = NPCManager.get_npc_state(&"test_npc")["flags"]
	silas_flags[&"Recruited"] = true
	shop.call("_refresh_page")
	_expect((shop.get("_shop_gifts") as Button).visible,
		"Gifts subtab appears once an NPC is recruited")
	shop.call("_select_shop_section", 1)
	for entry in shop.get("_entries"):
		var trade := entry.get("ref") as TradeData
		_expect(trade != null and trade.reward_item != null,
			"Only gifts appear in the Gifts subtab")
	shop.call("_select_shop_section", 0)
	for entry in shop.get("_entries"):
		var trade := entry.get("ref") as TradeData
		_expect(trade != null and trade.reward_method != &"",
			"Only fishing upgrades appear in the Upgrades subtab")

	_expect(REEL.one_time_purchase and LINE.one_time_purchase,
		"Reel and line upgrades cannot be repeatedly bought")
	_expect(CAST.one_time_purchase and ShopManager.trades.has(CAST),
		"Extra Cast is offered as a one-time purchase")
	var original_casts := FishingManager.casts_per_action
	FishingManager.shop_reward_upgrade_casts(1)
	FishingManager.shop_reward_upgrade_casts(1)
	_expect(FishingManager.casts_per_action == original_casts + 1
		and ShopManager.is_upgrade_owned(CAST),
		"Extra Cast applies once and becomes owned")

	var hot := ChallengeManager.challenges[0]
	_expect(hot.challenge_id == &"hot_streak", "Hot Streak is the first challenge")
	_expect(ChallengeManager.challenges.size() == 2,
		"Only Hot Streak and Perfect Timing remain active")
	_expect(hot.unlocks_trade(SCARF),
		"Three consecutive catches unlock the scarf")
	_expect(ShopManager.is_trade_locked(SCARF), "Unclaimed scarf starts locked")

	var terminal := TERMINAL.instantiate() as ShopInteractable
	add_child(terminal)
	ChallengeManager.debug_complete(hot)
	_expect(ChallengeManager.get_claimable_count() == 1,
		"Finishing a challenge queues one claimable reward")
	_expect(not hot.claimed and ShopManager.is_trade_locked(SCARF),
		"Finishing the challenge alone does not unlock the scarf")
	var world_notice := terminal.get_node("UnclaimedAchievementNotice") as PanelContainer
	_expect(world_notice != null and world_notice.visible,
		"A persistent exclamation bubble appears above the physical terminal")
	_expect(world_notice.get_theme_stylebox("panel") is StyleBoxTexture,
		"The persistent notification uses the terminal's nine-slice border")
	shop.call("_select_page", ShopMenu.Page.CHALLENGES)
	_expect((shop.get("_challenge_notification") as PanelContainer).visible,
		"The Challenges tab also displays its nine-slice alert")
	shop.call("_on_order_pressed")
	_expect(hot.claimed and ChallengeManager.get_claimable_count() == 0,
		"Claiming in the Challenges tab marks the achievement claimed")
	_expect(not ShopManager.is_trade_locked(SCARF),
		"Claiming Hot Streak unlocks its scarf trade")
	_expect(not world_notice.visible and not (shop.get("_challenge_notification") as PanelContainer).visible,
		"Notifications disappear after all claims have been collected")

	ChallengeManager.reset_all()
	FishingManager.reset_session_upgrades()
	NPCManager.npc_states = previous_states
	shop.queue_free()
	terminal.queue_free()
	print("terminal_shop_challenges_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _expect(ok: bool, message: String) -> void:
	if ok:
		print("  ok   ", message)
	else:
		failures += 1
		push_error("  FAIL " + message)
