extends Node

# Run: godot --headless --path . res://tests/post_dive_terminal_test.tscn
# Focused first-catch and terminal progression test. Full shore choreography
# is covered separately by sea_surface_reveal_test.gd.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MULLET: ItemData = preload("res://resources/items/mullet.tres")
const PORGY: ItemData = preload("res://resources/items/porgy.tres")
const PORGY_FISH: FishData = preload("res://resources/fish/porgy.tres")
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
		"Post-reveal terminal unlocks Fish without revealing Upgrades")
	_check(not menu.is_page_unlocked(ShopMenu.Page.COLLECTION)
		and not menu.is_page_unlocked(ShopMenu.Page.CHALLENGES)
		and not menu.is_page_unlocked(ShopMenu.Page.SCHEDULE)
		and not tabs.get_node("CollectionTab").visible,
		"No duplicate Collection tab, premature Challenges, or empty Schedule")
	var storage_notice: PanelContainer = tabs.get_node("StorageTab/StorageNoticeBubble") as PanelContainer
	_check(storage_notice.visible and notice.visible,
		"New Storage tab and the original world terminal display notices")
	menu.call("_select_page", ShopMenu.Page.STORAGE)
	_check(not storage_notice.visible and not notice.visible,
		"Visiting Fish clears both one-time notices")
	var fish_entries: Array = menu.get("_entries")
	var mullet: Dictionary = {}
	var porgy: Dictionary = {}
	var porgy_index: int = -1
	for i in range(fish_entries.size()):
		var entry: Dictionary = fish_entries[i]
		if entry.get("kind") != "fish":
			continue
		var species: FishData = entry.get("ref") as FishData
		if species.fish_id == &"mullet":
			mullet = entry
		elif species.fish_id == &"porgy":
			porgy = entry
			porgy_index = i
	_check(not mullet.is_empty() and int(mullet.get("quantity", 0)) == 1
		and mullet.get("icon") != null,
		"Combined Fish catalog shows the earned mullet and its live owned count")
	_check(not porgy.is_empty() and int(porgy.get("quantity", -1)) == 0
		and porgy.get("icon") != null and bool(porgy.get("locked", false))
		and bool(porgy.get("silhouette", false))
		and not bool(porgy.get("display_quantity", true))
		and porgy.get("name") == "???",
		"Uncaught porgy remains an anonymous silhouette with no owned count")
	if porgy_index >= 0:
		var tile: Button = (menu.get("_entry_buttons") as Array)[porgy_index] as Button
		var shadow: TextureRect = tile.get_node_or_null("Silhouette") as TextureRect
		_check(shadow != null and shadow.material is ShaderMaterial and tile.icon == null,
			"Unknown fish uses silhouette shader instead of revealing colored sprite")
		menu.call("_choose_tile", porgy_index)
		var details: Label = menu.get_node("TerminalRoot/Panel/Margin/Layout/Body/Details/DescriptionLabel") as Label
		var preview: TextureRect = menu.get_node("TerminalRoot/Panel/Margin/Layout/Body/Details/PreviewFrame/PreviewIcon") as TextureRect
		_check(details.text == "Catch this fish to reveal its entry."
			and preview.material is ShaderMaterial,
			"Unknown fish details and preview do not reveal its identity")
	menu.call("_select_page", ShopMenu.Page.SHOP)
	_check(int(menu.get("_page")) == ShopMenu.Page.STORAGE,
		"Before the first quota, player cannot open Upgrades")

	FishingManager.add_to_storage(MULLET)
	# An actual catch, not an inventory grant, reveals a species.
	FishingManager.catch_fish(PORGY_FISH)
	_check(QuotaManager.submit(&"mullet") == 2
		and QuotaManager.submit(&"porgy") == 1,
		"First complete quota submits exactly two mullet and one porgy")
	_check(QuotaManager.first_quota_completed and menu.is_page_unlocked(ShopMenu.Page.SHOP)
		and not menu.is_page_unlocked(ShopMenu.Page.CHALLENGES)
		and not menu.is_page_unlocked(ShopMenu.Page.SCHEDULE),
		"Finishing the quota unlocks ONLY Upgrades; Challenges and Schedule wait")
	menu.call("_select_page", ShopMenu.Page.STORAGE)
	var discovered_porgy: Dictionary = {}
	for entry in menu.get("_entries"):
		var fish_data: FishData = entry.get("ref") as FishData
		if fish_data != null and fish_data.fish_id == &"porgy":
			discovered_porgy = entry
			break
	_check(not discovered_porgy.is_empty() and not bool(discovered_porgy.get("locked", true))
		and not bool(discovered_porgy.get("silhouette", true))
		and int(discovered_porgy.get("quantity", -1)) == 0
		and bool(discovered_porgy.get("display_quantity", false))
		and bool(discovered_porgy.get("zero_quantity", false))
		and discovered_porgy.get("name") == "Porgy",
		"After catching and delivering porgy, its art stays revealed at x0")
	var shop_notice: PanelContainer = tabs.get_node("ShopTab/UpgradeNoticeBubble") as PanelContainer
	_check(shop_notice.visible and notice.visible,
		"Upgrades unlock prompts both a tab notice and the physical terminal badge")
	menu.call("_select_page", ShopMenu.Page.SHOP)
	_check(not shop_notice.visible and not notice.visible,
		"Visiting Upgrades acknowledges the new page")
	QuotaManager.call("_start_cycle", 2)
	_check(QuotaManager.first_quota_completed and menu.is_page_unlocked(ShopMenu.Page.SHOP),
		"Upgrade access persists after the next quota starts")
	menu.unlock_challenges()
	_check(menu.is_page_unlocked(ShopMenu.Page.CHALLENGES)
		and not menu.is_page_unlocked(ShopMenu.Page.SCHEDULE),
		"Challenges require an explicit later progression event")
	DateManager.date_booked.emit(null, 3, GameManager.Times.AFTERNOON)
	_check(menu.is_page_unlocked(ShopMenu.Page.SCHEDULE),
		"Schedule opens only when the first date is booked")
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
