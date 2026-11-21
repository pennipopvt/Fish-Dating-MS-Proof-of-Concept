
extends Node

# Run: godot --headless --path . res://tests/fish_co_gifts_unlock_test.tscn
# Real Main/terminal/phone wiring: no gift access on recruitment; unlock after
# the Day 2+ Fish Co phone call, and acknowledge its nested Gifts notification.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const SCARF: TradeData = preload("res://resources/trades/kuda_scarf.tres")
const OPERATOR: NPCData = preload("res://resources/npcs/fish_co_operator.tres")
var failures: int = 0


func _ready() -> void:
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	var previous_gifts: bool = ShopManager.gifts_unlocked
	var previous_quota: bool = QuotaManager.first_quota_completed
	ShopManager.gifts_unlocked = false
	QuotaManager.first_quota_completed = true
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	var opening: FishCoOpeningSequence = main.get_node("IntroLayer") as FishCoOpeningSequence
	var director: IslandStoryDirector = main.get_node("IslandStoryDirector") as IslandStoryDirector
	_check(director != null and director.events.size() == 2 \
		and director.events[0].event_id == &"fish_co_gifts",
		"The island-wide director owns the authored Fish Co gifts event")
	_check(director != null and not director.is_processing(),
		"The story scheduler stays dormant without an eligible event")
	opening._contract_call_finished = true
	opening._first_dive_call_started = true
	opening._first_dive_call_finished = true
	await get_tree().process_frame
	var menu: ShopMenu = main.get_node("CanvasLayer/ShopMenu") as ShopMenu
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var player: Player = world.get_node("Player") as Player
	var physical: ShopInteractable = world.get_node("Shop") as ShopInteractable
	menu.unlock_post_dive_storage()
	menu.call("_select_page", ShopMenu.Page.STORAGE) # Acknowledge the earlier Fish catalog notice.
	menu.call("_select_page", ShopMenu.Page.SHOP)
	_check(not menu._pending_progression_notice(),
		"Upgrades have been acknowledged and no gift notices are pending")
	_check(not (menu.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/ShopCategories/ShopGifts") as Button).visible
		and not ShopManager.can_trade(SCARF),
		"Day 1 gifts are not available even if Shop is open")

	# Silas gains a room on Day 1; this alone must not grant gifts.
	_check(RecruitmentHandler.assign_home(SILAS), "Silas gets a townhouse room")
	_check(int(NPCManager.get_npc_state(SILAS.npc_id).get("room_assigned_day", -1)) == 1,
		"Housing tracks the day of the first resident move-in")
	await get_tree().create_timer(0.15).timeout
	_check(not DialogueManager.is_active and not ShopManager.gifts_unlocked,
		"Fish Co does not call or enable gifts on the recruitment day")
	player.busy = true
	GameManager.rest() # Day 1 afternoon
	GameManager.rest() # Day 1 night
	GameManager.rest() # Day 2 morning
	await get_tree().create_timer(0.15).timeout
	_check(not DialogueManager.is_active and not ShopManager.gifts_unlocked,
		"Fish Co waits until Penni is free to answer the phone")
	_check(director.has_pending(&"fish_co_gifts") and director.is_processing(),
		"The event is queued by the new day and only polls while waiting for availability")
	player.busy = false
	for i in range(20):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.1).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc == OPERATOR,
		"Fish Co calls once on Day 2 after a resident has moved in")
	_check(director.get("_active") == director.events[0] and not director.is_processing(),
		"The director hands active dialogue to DialogueManager and stops polling")
	_check(not ShopManager.gifts_unlocked and player.busy,
		"Gifts stay locked until Penni finishes the phone call")
	# Check the exact authoring file rather than relying on the dialogue line index.
	var graph: Dictionary = DialogueJsonLoader.read_graph("res://dialogue/fish_co_gifts_unlocked.json")
	_check(str(graph.get("nodes", {}).get("call", {}).get("lines", [])[2].get("text", "")).contains("other inhabitants"),
		"The call uses the authored housing-observation dialogue")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	_check(ShopManager.gifts_unlocked and not player.busy,
		"Finishing the phone call enables gifts and restores player movement")
	_check(director.has_completed(&"fish_co_gifts"),
		"The director records the one-time story event as completed")
	var gifts: Button = menu.get_node("TerminalRoot/Panel/Margin/Layout/Body/Left/ShopCategories/ShopGifts") as Button
	var nested: PanelContainer = gifts.get_node("GiftsNoticeBubble") as PanelContainer
	var parent: PanelContainer = menu.get_node("TerminalRoot/NavTabs/ShopTab/UpgradeNoticeBubble") as PanelContainer
	var world_notice: PanelContainer = physical.get_node("UnclaimedAchievementNotice") as PanelContainer
	_check(gifts.visible and nested.visible and parent.visible and world_notice.visible,
		"New Gifts is visible and has subtab, Shop tab, and world terminal notices")
	menu.call("_select_shop_section", 1)
	_check(not nested.visible and not parent.visible and not world_notice.visible,
		"Opening Gifts acknowledges the notices without hiding the unlocked section")
	GameManager.rest()
	await get_tree().create_timer(0.15).timeout
	_check(not DialogueManager.is_active and ShopManager.gifts_unlocked,
		"Fish Co does not call again on later periods")

	main.queue_free()
	NPCManager.npc_states.clear()
	ShopManager.gifts_unlocked = previous_gifts
	QuotaManager.first_quota_completed = previous_quota
	print("fish_co_gifts_unlock_test: PASS" if failures == 0 else
		"fish_co_gifts_unlock_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
