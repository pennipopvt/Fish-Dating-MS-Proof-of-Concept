extends SceneTree

# Integrated dock/underwater regression:
# godot --headless --path . -s res://tests/diving_island_transition_test.gd
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = MAIN.instantiate()
	get_root().add_child(main)
	await process_frame

	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var dock: Node2D = world.get_node("Dock") as Node2D
	var player: Player = world.get_node("Player") as Player
	var dive_layer: CanvasLayer = main.get_node("DivingLayer") as CanvasLayer
	var lagoon: DivingWorld = main.get_node(
		"DivingLayer/DivingPrototype/SubViewportContainer/SubViewport/Lagoon"
	) as DivingWorld
	var iris: ColorRect = main.get_node("TransitionLayer/Iris") as ColorRect
	var dialogue_ui: DialogueUI = main.get_node("CanvasLayer/DialogueUI") as DialogueUI
	var intro: FishCoIntro = main.get_node("IntroLayer/FishCoIntro") as FishCoIntro
	var terminal: ShopMenu = main.get_node("CanvasLayer/ShopMenu") as ShopMenu
	var tabs: VBoxContainer = terminal.get_node("TerminalRoot/NavTabs") as VBoxContainer
	_check(intro.visible and player.busy and not bool(main.get("_contract_call_finished")),
		"New game opens on Fish Co boat backdrop before the player can move")
	_check(DialogueManager.is_active and dialogue_ui.visible
		and DialogueManager.current_npc.npc_id == &"fish_co_operator",
		"Fish Co call plays through normal DialogueManager and DialogueUI")
	_check(dialogue_ui.layer > (main.get_node("IntroLayer") as CanvasLayer).layer,
		"Regular dialogue portraits appear in front of the boat backdrop")
	_check(not intro.has_node("DialoguePanel"),
		"No separate custom phone-call dialogue box remains")
	_check((dialogue_ui.get_node("NPCPortrait") as TextureRect).texture == dialogue_ui.placeholder_portrait,
		"Fish Co portrait uses a placeholder until the phone sprite is added")
	_check(tabs.get_node("QuotaTab").visible and not tabs.get_node("ShopTab").visible
		and not tabs.get_node("StorageTab").visible,
		"Only quota tab exists visually during the introductory phone call")
	var penni_lines: int = 0
	var fish_co_lines: int = 0
	var phone_lines: int = 0
	var dialogue_text: Array[String] = []
	while DialogueManager.is_active and phone_lines < 24:
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null:
			dialogue_text.append(line.text)
			if line.speaker == DialogueLineData.Speaker.PLAYER:
				penni_lines += 1
			else:
				fish_co_lines += 1
		DialogueManager.advance()
		phone_lines += 1
	_check(phone_lines == 18 and penni_lines == 8 and fish_co_lines == 10,
		"Each authored line advances separately while keeping its speaker")
	_check(dialogue_text.slice(-2) == ["*click*", "...bye."],
		"Fish Co hangs up before Penni's final goodbye")
	_check(bool(main.get("_contract_call_finished")) and player.busy,
		"Contract ending begins the reused radial iris while movement stays locked")
	await create_timer(1.3).timeout
	_check(not DialogueManager.is_active and not dialogue_ui.visible
		and not intro.visible and not terminal.visible and not player.busy,
		"Iris opens onto the dock without automatically opening the quota terminal")
	_check(player.global_position.distance_to(dock.global_position + Vector2(22.0, 11.0)) < 1.0,
		"Penni appears next to the original dock after the radial transition")
	_check(bool(main.get("_contract_call_finished")) and not iris.visible,
		"Contract introduction and radial transition have completed")
	var world_terminal: ShopInteractable = world.get_node("Shop") as ShopInteractable
	_check(bool(world_terminal.get("_intro_quota_notice"))
		and world_terminal.get_node("UnclaimedAchievementNotice").visible,
		"Existing terminal exclamation notice directs the player to review the quota")
	ShopManager.request_shop()
	_check(terminal.visible and not bool(world_terminal.get("_intro_quota_notice")),
		"Opening the existing terminal acknowledges its introductory exclamation")
	_check(tabs.get_node("QuotaTab").visible and not tabs.get_node("ShopTab").visible,
		"Only quota tab is available during the dock introduction")
	var fish_preview: TextureRect = terminal.get_node(
		"TerminalRoot/Panel/Margin/Layout/Body/Details/PreviewFrame/PreviewIcon"
	) as TextureRect
	var quota_title: Label = terminal.get_node(
		"TerminalRoot/Panel/Margin/Layout/Body/Left/PageHint"
	) as Label
	var prize: Label = terminal.get_node(
		"TerminalRoot/Panel/Margin/Layout/Body/Details/DescriptionLabel"
	) as Label
	_check(fish_preview.texture == (FishingManager.possible_catches[0] as FishData).item_data.sprite,
		"Quota details preview uses the existing mullet sprite")
	_check(quota_title.text.contains("DAY 3") and prize.text.contains("$400,000"),
		"Quota prominently shows the three-day deadline and legendary prize")
	terminal.call("_select_quota_fish", &"porgy")
	_check(fish_preview.texture == (FishingManager.possible_catches[1] as FishData).item_data.sprite,
		"Selecting another quota fish updates its details image")
	terminal.close()

	_check(not dive_layer.visible, "Game starts on the original island")
	_check(not iris.visible, "Iris is not visible during ordinary gameplay")
	_check(main.get_node_or_null("CanvasLayer/ShopMenu") != null, "Original terminal remains in island scene")
	_check(main.get_node_or_null("CanvasLayer/BaitMenu") == null
		and main.get_node_or_null("CanvasLayer/BobberMenu") == null,
		"Old bait and bobber menus are removed")
	_check(world.get_node_or_null("BaitBox") == null
		and world.get_node_or_null("BobberShelf") == null,
		"Bait box and bobber shelf no longer appear on the island")
	var obsolete_trade: bool = false
	for trade in ShopManager.trades:
		if trade != null and trade.reward_method in [&"shop_reward_unlock_hard_bait", &"shop_reward_unlock_yellow_bait", &"shop_reward_upgrade_casts", &"shop_reward_add_casts"]:
			obsolete_trade = true
	_check(not obsolete_trade, "Shop no longer sells bait and obsolete extra casts")

	var actions_before: int = GameManager.get_actions_left()
	main.call("request_dive", player, dock)
	_check(tabs.get_node("ShopTab").visible and tabs.get_node("StorageTab").visible,
		"Other terminal tabs unlock once Penni begins her first dive")
	_check(player.busy, "Player input locks during the jump")
	await create_timer(1.7).timeout
	_check(dive_layer.visible and bool(main.get("_underwater")), "Dock jump leads to underwater scene")
	_check(bool(lagoon.get("_embedded_in_world")), "Diving scene uses real island as its shore")
	_check(GameManager.diving_session_active, "Catching fish underwater does not spend additional actions")
	_check(not iris.visible, "Circular transition opens fully underwater")
	_check(bool(dialogue_ui.get("_underwater_mode")) and dialogue_ui.layer > dive_layer.layer,
		"Existing dialogue UI switches to fish sprites above the underwater world")

	# Surface without Silas and ensure the normal island and its clock return.
	lagoon.call("_return_to_surface", false)
	await create_timer(1.3).timeout
	_check(not dive_layer.visible and not bool(main.get("_underwater")), "Surface returns to island")
	_check(not player.busy and player.visible, "Normal overworld movement restored")
	_check(not GameManager.diving_session_active, "Diving action state clears on return")
	_check(not bool(dialogue_ui.get("_underwater_mode")), "Land dialogue portraits and layout are restored")
	_check(GameManager.get_actions_left() == actions_before - 1, "One completed dive costs one action")

	# The same lagoon is preserved across a second jump.
	var original_lagoon_id: int = lagoon.get_instance_id()
	main.call("request_dive", player, dock)
	await create_timer(1.7).timeout
	_check(lagoon.get_instance_id() == original_lagoon_id, "Underwater NPCs and catches persist across dives")

	# Silas's land decision requests the same exit instead of switching to
	# the obsolete standalone prototype's drawn shoreline.
	lagoon.set("_silas_following", true)
	lagoon.set("_silas_met", true)
	lagoon.set("_net_cleared", true)
	lagoon.set("_silas_talks", 3)
	lagoon.call("_return_to_surface", true)
	await create_timer(1.8).timeout
	_check(bool(lagoon.get("_silas_ashore")), "Silas remembers choosing to surface")
	_check(main.get("_silas_actor") is NPCInteractable, "Human Silas spawns in the original island")
	_check(not dive_layer.visible, "Island is visible after Silas's transformation")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
		await process_frame
	_check(bool(main.get("_silas_recruited")), "Silas enters existing town recruitment flow")

	main.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Integrated diving-to-island checks passed")
	quit(1 if failures > 0 else 0)

func _check(ok: bool, message: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + message)
	if not ok:
		failures += 1
