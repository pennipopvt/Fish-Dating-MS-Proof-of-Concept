extends SceneTree

# Integrated dock/underwater regression:
# godot --headless --path . -s res://tests/diving_island_transition_test.gd
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const FISH_CO_PORTRAIT: Texture2D = preload("res://sprites/characters/fish co/fish-co.png")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = MAIN.instantiate()
	get_root().add_child(main)
	await process_frame

	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var dock: Node2D = world.get_node("Dock") as Node2D
	var dock_prompt: InteractPrompt = dock.get_node("InteractPrompt") as InteractPrompt
	var player: Player = world.get_node("Player") as Player
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var iris: ColorRect = main.get_node("TransitionLayer/Iris") as ColorRect
	var dialogue_ui: DialogueUI = main.get_node("CanvasLayer/DialogueUI") as DialogueUI
	var intro: FishCoIntro = main.get_node("IntroLayer/FishCoIntro") as FishCoIntro
	_check(main.get("_intro_layer") is CanvasLayer and main.get("_intro") is FishCoIntro,
		"Main initializes references to both Fish Co intro nodes")
	_check((main.get("_intro_layer") as CanvasLayer).get_node_or_null("FishCoIntro") == intro,
		"Fish Co intro belongs to the correctly layered CanvasLayer")
	var terminal: ShopMenu = main.get_node("CanvasLayer/ShopMenu") as ShopMenu
	var tabs: VBoxContainer = terminal.get_node("TerminalRoot/NavTabs") as VBoxContainer
	var boat: Node2D = world.get_node("IntroBoat") as Node2D
	var controller: WorldCameraController = world.get_node("CameraController") as WorldCameraController
	var camera: Camera2D = controller.get_node("Camera2D") as Camera2D
	var dock_intro_position: Vector2 = (boat.get_node("PlayerSpot") as Marker2D).global_position
	_check(not intro.visible and player.busy and not bool(main.get("_contract_call_finished"))
		and player.global_position.distance_to(dock_intro_position) < 1.0,
		"Opening Fish Co call uses the actual east-side boat and not the fake backdrop")
	_check(camera.get_parent() == controller and not player.has_node("Camera2D")
		and camera.get_screen_center_position().distance_to(
			(boat.get_node("CameraFocus") as Marker2D).global_position) < 4.0,
		"World camera frames the boat independently of Penni and her animation")
	_check((boat.get_node("Sprite") as IntroBoatSprite).sprite_frames != null,
		"Real world boat uses the imported animated sprite")
	_check(DialogueManager.is_active and dialogue_ui.visible
		and DialogueManager.current_npc.npc_id == &"fish_co_operator",
		"Fish Co call plays through normal DialogueManager and DialogueUI")
	_check(dialogue_ui.layer > (main.get_node("IntroLayer") as CanvasLayer).layer,
		"Regular dialogue portraits appear over the real world boat")
	_check(not intro.has_node("DialoguePanel"),
		"No separate custom phone-call dialogue box remains")
	_check((dialogue_ui.get_node("NPCPortrait") as TextureRect).texture == FISH_CO_PORTRAIT,
		"Fish Co phone call shows the newly imported operator portrait")
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
	_check(not dock_prompt.visible, "Dock interaction cue stays hidden until the first quota call finishes")
	main.call("request_dive", player, dock)
	_check(not DialogueManager.is_active and not bool(main.get("_underwater")),
		"Dock cannot start diving before the first quota is reviewed")
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
	_check(not bool(main.get("_first_dive_call_finished")),
		"Closing the first quota page has not yet unlocked diving")
	main.call("request_dive", player, dock)
	_check(not bool(main.get("_transitioning")),
		"Dock interaction does nothing until Fish Co finishes the second call")
	await process_frame
	_check(DialogueManager.is_active and DialogueManager.current_npc.npc_id == &"fish_co_operator",
		"Closing the first quota page triggers the second call through normal dialogue")
	_check((DialogueManager.get_current_line() as DialogueLineData).text == "*ring ring*",
		"The second call begins with the ringing phone")
	main.call("request_dive", player, dock)
	_check(not bool(main.get("_underwater")) and not bool(main.get("_transitioning")),
		"Dock cannot start diving while Fish Co is speaking")
	var second_call_lines: Array[String] = []
	var second_call_player_lines: int = 0
	while DialogueManager.is_active and second_call_lines.size() < 15:
		var current: DialogueLineData = DialogueManager.get_current_line()
		if current != null:
			second_call_lines.append(current.text)
			if current.speaker == DialogueLineData.Speaker.PLAYER:
				second_call_player_lines += 1
		DialogueManager.advance()
	_check(second_call_lines.size() == 8 and second_call_player_lines == 2,
		"Second Fish Co call has eight separately advanced, correctly attributed lines")
	_check(second_call_lines[-2] == "*Click*" and second_call_lines[-1] == "Just throw me into the deep end, I guess...",
		"Fish Co hangs up and Penni gets the last line")
	_check(bool(main.get("_first_dive_call_finished")) and not player.busy and dock_prompt.visible,
		"First dive is unlocked, with the normal interaction prompt persistently above the dock")
	_check(not terminal.visible and tabs.get_node("QuotaTab").visible and not tabs.get_node("ShopTab").visible,
		"Quota remains the only terminal tab until a dive is actually confirmed")

	# Existing dialogue choice UI: declining must not start the dive or
	# consume an action, and the same Yes/No prompt is available again.
	var actions_before_decline: int = GameManager.get_actions_left()
	main.call("request_dive", player, dock)
	_check(DialogueManager.is_active and DialogueManager.current_npc.npc_id == &"dock_dive_prompt",
		"Dock asks Start diving? through the shared DialogueManager")
	_check((DialogueManager.get_current_line() as DialogueLineData).text == "Start diving?",
		"Dock confirmation question uses authored dialogue")
	DialogueManager.advance()
	_check(DialogueManager.is_awaiting_choice() and DialogueManager.get_choices().size() == 2,
		"Dock offers exactly Yes and No")
	DialogueManager.select_choice(1)
	DialogueManager.advance()
	_check(not DialogueManager.is_active and not bool(main.get("_transitioning"))
		and not bool(main.get("_underwater")) and dock_prompt.visible,
		"Choosing No stays on shore with the interaction cue available")
	_check(GameManager.get_actions_left() == actions_before_decline,
		"Declining the first dive does not spend time")

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

	main.call("request_dive", player, dock)
	_check(DialogueManager.is_active and DialogueManager.current_npc.npc_id == &"dock_dive_prompt",
		"Dock offers confirmation again after No")
	DialogueManager.advance()
	DialogueManager.select_choice(0)
	DialogueManager.advance()
	_check(not tabs.get_node("ShopTab").visible and not tabs.get_node("StorageTab").visible,
		"Starting the dive alone does not unlock the terminal economy")
	_check(player.busy and bool(main.get("_transitioning")),
		"Accepting the dock prompt starts the dive jump and locks player movement")
	_check(not bool(dock.get("_first_dive_prompt")), 
		"Persistent tutorial dock prompt switches back to proximity-only after Yes")
	await create_timer(1.7).timeout
	_check(bool(main.get("_underwater")) and player.swimming,
		"One continuous dock jump enables swimming in the original World")
	_check(bool((main.get_node("TransitionLayer") as SeaDiveTransition).get("_dive_has_splashed")),
		"Depth crossing triggers a single splash on the continuous jump path")
	_check(sea.get_parent() == world and sea.get_node("Solids") is TileMapLayer,
		"Underwater level is an editable child of the same persistent World")
	_check(GameManager.diving_session_active, "Catching fish underwater does not spend additional actions")
	_check(not iris.visible, "No iris or black-screen cut is used for the dock dive")
	_check(bool(dialogue_ui.get("_underwater_mode")),
		"Existing dialogue UI switches to underwater fish sprite portraits")

	# First sea exit is intentionally blocked until Penni catches a fish
	# that Silas damaged. Direct test setup bypasses the story/tutorial only
	# AFTER asserting the guard; physical transition remains unchanged.
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	sea.call("_return_to_surface")
	_check(bool(main.get("_underwater")) and player.swimming and DialogueManager.is_active,
		"Cannot return to shore without a successful Silas-assisted fish catch")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	story.get("_events")[&"first_companion_catch"] = true
	sea.call("_return_to_surface")
	await create_timer(1.3).timeout
	_check(not bool(main.get("_underwater")) and not player.swimming,
		"Surfacing restores land controls without swapping scenes")
	_check(not player.busy and player.visible, "Normal overworld movement restored")
	_check(not GameManager.diving_session_active, "Diving action state clears on return")
	_check(not bool(dialogue_ui.get("_underwater_mode")), "Land dialogue portraits and layout are restored")
	_check(GameManager.get_day() == 1 and GameManager.get_period() == GameManager.Times.AFTERNOON
		and GameManager.get_actions_left() == GameManager.ACTIONS_PER_PERIOD,
		"Returning from a morning dive advances to afternoon with fresh actions")

	# The same sea is preserved across a second jump.
	var original_sea_id: int = sea.get_instance_id()
	main.call("request_dive", player, dock)
	_check(DialogueManager.is_active and DialogueManager.current_npc.npc_id == &"dock_dive_prompt",
		"Subsequent dives also use the dock confirmation dialog")
	DialogueManager.advance()
	DialogueManager.select_choice(0)
	DialogueManager.advance()
	await create_timer(1.7).timeout
	_check(sea.get_instance_id() == original_sea_id and sea.get_parent() == world,
		"Same sea NPCs and fish remain in World across multiple dives")

	sea.call("_return_to_surface")
	await create_timer(1.3).timeout
	_check(not player.swimming and not bool(main.get("_underwater")),
		"Second dive returns to shore without a second Player")

	main.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Integrated diving-to-island checks passed")
	quit(1 if failures > 0 else 0)

func _check(ok: bool, message: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + message)
	if not ok:
		failures += 1
