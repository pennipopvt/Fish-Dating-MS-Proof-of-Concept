extends SceneTree

# Run from the Godot project directory:
# godot --headless --path . -s res://tests/diving_prototype_test.gd
#
# Headless integration checks for the diving branch's separate vertical slice.
const PROTOTYPE: PackedScene = preload("res://scenes/diving_prototype.tscn")
const SILAS_FISH: Texture2D = preload("res://sprites/fish/silas_eel.png")
const PENNI_PORTRAIT: Texture2D = preload("res://sprites/characters/penni/penni_portrait.png")
const SILAS_BURROW := Vector2(385.0, 258.0)
const TANGLED_NET := Vector2(411.0, 250.0)
const SURFACE_POINT := Vector2(78.0, 92.0)
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var prototype := PROTOTYPE.instantiate()
	get_root().add_child(prototype)
	await process_frame
	await process_frame
	var world: Node2D = prototype.get_node("SubViewportContainer/SubViewport/Lagoon")
	var player: Sprite2D = world.get_node("Player")
	var viewport_container: SubViewportContainer = prototype.get_node("SubViewportContainer")
	var pixel_viewport: SubViewport = prototype.get_node("SubViewportContainer/SubViewport")
	var hud: Control = prototype.get_node("HUD")
	_check(pixel_viewport.size == Vector2i(320, 180) and viewport_container.stretch_shrink == 6,
		"Lagoon world uses the same 320x180 pixel grid as the island")
	_check(hud.get_parent() == prototype and hud.has_node("Location"),
		"Diving HUD renders outside the pixel viewport for readable typography")
	_check(is_equal_approx(player.scale.x, 1.0) and is_equal_approx(player.scale.y, 1.0),
		"Penni is at the original game's full character scale")
	var silas: Sprite2D = world.get_node("Silas")
	var wild_fish: Array = world.get("_wild_fish")
	var dialogue: DialogueUI = world.get("_standalone_dialogue_ui") as DialogueUI
	_check(dialogue != null, "Standalone lagoon opens the same DialogueUI component")
	_check(dialogue != null and bool(dialogue.get("_underwater_mode")), "Underwater portraits use fish sprite mode")
	_check(bool(world.get("_underwater")), "Starts in the underwater level")
	_check(wild_fish.size() == 8, "Wild fish are present with autonomous movement")
	_check(not bool(world.get("_silas_following")), "Silas is initially independent")
	_check(not bool(world.get("_silas_met")), "Silas is a hidden talking-fish surprise")

	# Approaching and clicking no longer catches automatically: it starts
	# the same three-scroll parry combat, with species-authored attacks.
	var combat: DivingCombat = world.get_node("Combat") as DivingCombat
	var first_fish: DivingWildFish = wild_fish[0]
	var target: Vector2 = first_fish.position
	var before: int = world.call("_total_catches")
	world.call("_try_catch", target)
	_check(not combat.is_active() and int(world.call("_total_catches")) == before,
		"Clicking a distant fish does not start a battle or catch it")
	player.position = target
	world.call("_try_catch", target)
	_check(combat.is_active(), "Clicking a nearby fish engages parry combat")
	_check(int(world.call("_total_catches")) == before,
		"Fish is not automatically caught when clicked")
	_check(world.get_node("../../../HUD/CombatPanel").visible,
		"Combat panel appears while the fish is engaged")
	combat.call("_start_windup")
	combat.call("_start_attack")
	combat.reel_scroll()
	combat.reel_scroll()
	combat.reel_scroll()
	_check(int(combat.phase) == DivingCombat.Phase.STUN and combat.free_reel,
		"Three fast scrolls in the perfect window stun the fish")
	combat.progress = 0.95
	combat.reel_scroll()
	_check(not combat.is_active(), "Completing reel progress ends the encounter")
	_check(int(world.call("_total_catches")) == before + 1,
		"Only winning the combat adds the fish to storage")
	_check(wild_fish.size() == 7, "Caught fish disappears from the underwater world")

	# A failed encounter leaves the fish swimming in the world.
	var second: DivingWildFish = wild_fish[0]
	player.position = second.position
	world.call("_try_catch", second.position)
	_check(combat.is_active(), "Another fish can initiate its own attack")
	combat.call("_start_windup")
	combat.reel_scroll()
	_check(int(combat.phase) == DivingCombat.Phase.DASH,
		"An early scroll triggers the missed-parry dash")
	combat.release()
	_check(not combat.is_active() and second.catch_cooldown > 0.0,
		"Releasing the battle lets the wild fish escape and be pursued again")
	_check(int(world.call("_total_catches")) == before + 1,
		"Escaping fish are never added to storage")

	# Find and talk to the eel before rescuing him.
	player.position = SILAS_BURROW + Vector2(0, -14)
	world.call("_talk_to_silas")
	_check(bool(world.get("_silas_met")), "Talking eel reveal starts underwater")
	_check(DialogueManager.is_active and DialogueManager.get_current_speaker_name() == "???",
		"Shared dialogue manager preserves Silas's mysterious introduction")
	if dialogue != null:
		_check((dialogue.get_node("NPCPortrait") as TextureRect).texture == SILAS_FISH,
			"Dialogue shows Silas's fish sprite, not the humanoid portrait")
		_check((dialogue.get_node("PlayerPortrait") as TextureRect).texture == PENNI_PORTRAIT,
			"Penni uses her ORIGINAL dialogue portrait underwater")
	_finish_dialogue()
	world.call("_try_catch", TANGLED_NET)
	_check(bool(world.get("_net_cleared")), "Player can free Silas's tangled burrow")
	_finish_dialogue()
	_check(bool(world.get("_silas_following")), "Rescued Silas begins following the player")

	# Silas can conceal the player, making ordinary fish less skittish.
	world.call("_ask_silas_to_hide")
	_check(float(world.get("_veil_time")) > 0.0, "Silas's concealment ability activates")
	world.set("_talk_cooldown", 0.0)
	world.call("_talk_to_silas")
	_finish_dialogue()
	world.set("_talk_cooldown", 0.0)
	world.call("_talk_to_silas")
	_finish_dialogue()
	_check(int(world.get("_silas_talks")) >= 2, "Multiple conversations build trust")

	# Only after getting to know him does Silas ask to come ashore.
	player.position = SURFACE_POINT
	world.call("_try_surface")
	# Shared UI presents real selectable dialogue choices.
	_finish_dialogue()
	_check(DialogueManager.is_awaiting_choice(), "Surface invitation uses the shared dialogue choice UI")
	DialogueManager.select_choice(0)
	_finish_dialogue()
	_check(not bool(world.get("_underwater")), "Inviting Silas returns to shore")
	_check(bool(world.get("_silas_ashore")), "Silas chooses to come ashore")
	_check(silas.texture is AtlasTexture, "On land Silas uses his humanoid sprite")
	_finish_dialogue()
	if dialogue != null:
		_check(not bool(dialogue.get("_underwater_mode")), "Human portraits return on land")

	world.call("_go_underwater")
	_check(bool(world.get("_underwater")), "Player can dive back in")
	_check(silas.texture == SILAS_FISH, "Silas returns to his fish sprite underwater")
	_check(bool(world.get("_silas_following")), "Companion relationship persists across dives")

	prototype.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Diving prototype tests passed")
	quit(1 if failures > 0 else 0)

func _finish_dialogue() -> void:
	for i in range(18):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			return
		DialogueManager.advance()

func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
