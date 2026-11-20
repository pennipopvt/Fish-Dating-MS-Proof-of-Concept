extends Node

# Run: godot --headless --path . res://tests/post_dive_terminal_test.tscn
# Focused first-catch and terminal progression test. Full shore choreography
# is covered separately by sea_surface_reveal_test.gd.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MULLET: ItemData = preload("res://resources/items/mullet.tres")
const PORGY: ItemData = preload("res://resources/items/porgy.tres")
var failures: int = 0


func _ready() -> void:
	QuotaManager.reset_run()
	GameManager.reset_clock()
	FishingManager.current_storage.clear()
	FishingManager.storage_changed.emit()
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	# Skip unrelated phone introduction before its deferred start.
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var sea: DivingWorld = main.get_node("SubViewportContainer/SubViewport/World/Sea") as DivingWorld
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var silas: SeaNPC = sea.get_node("NPCs/Silas") as SeaNPC
	var battle: DivingCompanionBattle = silas.get_node("CompanionBattle") as DivingCompanionBattle
	var menu: ShopMenu = main.get_node("CanvasLayer/ShopMenu") as ShopMenu
	var actor: ShopInteractable = sea.get_parent().get_node("Shop") as ShopInteractable
	var tabs: VBoxContainer = menu.get_node("TerminalRoot/NavTabs") as VBoxContainer
	var notice: PanelContainer = actor.get_node("UnclaimedAchievementNotice") as PanelContainer

	_check(QuotaManager.get_target(&"mullet") == 2 and QuotaManager.get_target(&"porgy") == 1,
		"First Fish Co contract requires two mullet and one porgy")
	_check(menu.is_page_unlocked(ShopMenu.Page.QUOTA)
		and not menu.is_page_unlocked(ShopMenu.Page.STORAGE)
		and not menu.is_page_unlocked(ShopMenu.Page.SHOP),
		"Before the first return, the terminal shows only Quota")
	_check(not story.can_surface(), "First shore exit is locked before assisted catch")
	var fish: DivingWildFish
	for candidate in sea.get("_wild_fish"):
		var wild: DivingWildFish = candidate as DivingWildFish
		if wild != null and not wild.trapped:
			fish = wild
			break
	_check(fish != null, "A normal fish is available for the companion catch test")
	if fish == null:
		_finish(main)
		return
	var lookup: Dictionary = sea.get("_fish_data")
	var data: FishData = lookup.get(fish) as FishData
	var flags: Dictionary = NPCManager.get_npc_state(story.silas_data.npc_id)["flags"]
	flags[&"silas_freed"] = true
	flags[&"silas_following"] = true
	_check(not fish.companion_weakened and not story.can_surface(),
		"Meeting and commanding Silas do not satisfy the catch requirement")
	_check(battle.start(fish, data), "Silas begins ordinary shared battle")
	battle.step(2.0, true)
	_check(fish.companion_weakened and fish.health < fish.max_health,
		"Only actual companion damage marks a fish as helped")
	_check(not story.can_surface(), "Helping is not enough until Penni catches that fish")
	battle.stop()
	GameManager.diving_session_active = true
	sea.call("_on_combat_finished", true, fish)
	_check(story.has_event(&"first_companion_catch") and story.can_surface(),
		"Successful catch of Silas-weakened fish unlocks the first exit")
	_check(FishingManager.count_in_storage(&"mullet") == 1,
		"First legitimate catch reaches normal shared inventory")
	GameManager.diving_session_active = false

	# This signal is emitted by the actual surface cinematic, not by a dive
	# start. No duplicate progression flag lives in Main.
	story.silas_surface_reveal_finished.emit()
	_check(menu.is_page_unlocked(ShopMenu.Page.STORAGE)
		and not menu.is_page_unlocked(ShopMenu.Page.SHOP)
		and tabs.get_node("StorageTab").visible
		and not tabs.get_node("ShopTab").visible,
		"Post-reveal terminal unlocks Storage without revealing upgrades")
	var storage_notice: PanelContainer = tabs.get_node("StorageTab/StorageNoticeBubble") as PanelContainer
	_check(storage_notice.visible and notice.visible,
		"New Storage tab and the original world terminal display notices")
	menu.call("_select_page", ShopMenu.Page.STORAGE)
	_check(not storage_notice.visible and not notice.visible,
		"Visiting Storage clears both one-time notices")
	menu.call("_select_page", ShopMenu.Page.SHOP)
	_check(int(menu.get("_page")) == ShopMenu.Page.STORAGE,
		"Before the first quota, player cannot open Upgrades")

	FishingManager.add_to_storage(MULLET)
	FishingManager.add_to_storage(PORGY)
	_check(QuotaManager.submit(&"mullet") == 2
		and QuotaManager.submit(&"porgy") == 1,
		"First complete quota submits exactly two mullet and one porgy")
	_check(QuotaManager.first_quota_completed and menu.is_page_unlocked(ShopMenu.Page.SHOP),
		"Completing the first quota permanently unlocks Upgrades")
	var shop_notice: PanelContainer = tabs.get_node("ShopTab/UpgradeNoticeBubble") as PanelContainer
	_check(shop_notice.visible and notice.visible,
		"Upgrades unlock prompts both a tab notice and the physical terminal badge")
	menu.call("_select_page", ShopMenu.Page.SHOP)
	_check(not shop_notice.visible and not notice.visible,
		"Visiting Upgrades acknowledges the new page")
	QuotaManager.call("_start_cycle", 2)
	_check(QuotaManager.first_quota_completed and menu.is_page_unlocked(ShopMenu.Page.SHOP),
		"Upgrade access persists after the next quota starts")
	_finish(main)


func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	print("post_dive_terminal_test: PASS" if failures == 0 else
		"post_dive_terminal_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
