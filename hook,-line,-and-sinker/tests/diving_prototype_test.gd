extends SceneTree

# Run from the Godot project directory:
# godot --headless --path . -s res://tests/diving_prototype_test.gd
#
# Headless integration checks for the diving branch's separate vertical slice.
const PROTOTYPE: PackedScene = preload("res://scenes/diving_prototype.tscn")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var prototype := PROTOTYPE.instantiate()
	get_root().add_child(prototype)
	await process_frame
	var world: Node2D = prototype.get_node("SubViewportContainer/SubViewport/Lagoon")
	var player: Sprite2D = world.get_node("Player")
	var silas: Sprite2D = world.get_node("Silas")
	var wild_fish: Array = world.get("_wild_fish")
	_check(bool(world.get("_underwater")), "Starts in the underwater level")
	_check(wild_fish.size() == 8, "Wild fish are present with autonomous movement")
	_check(not bool(world.get("_silas_following")), "Silas is initially independent")
	_check(not bool(world.get("_silas_met")), "Silas is a hidden talking-fish surprise")

	# Catch an ordinary fish in reach; clicking from far away must not work.
	var first_fish: DivingWildFish = wild_fish[0]
	var target: Vector2 = first_fish.position
	var before: int = world.call("_total_catches")
	world.call("_try_catch", target)
	_check(int(world.call("_total_catches")) == before, "No long-distance net catches")
	player.position = target
	world.call("_try_catch", target)
	_check(int(world.call("_total_catches")) == before + 1, "Nearby clicked fish is caught")

	# Find and talk to the eel before rescuing him.
	player.position = world.SILAS_BURROW + Vector2(0, -14)
	world.call("_talk_to_silas")
	_check(bool(world.get("_silas_met")), "Talking eel reveal starts underwater")
	_finish_dialogue(world)
	world.call("_try_catch", world.TANGLED_NET)
	_check(bool(world.get("_net_cleared")), "Player can free Silas's tangled burrow")
	_finish_dialogue(world)
	_check(bool(world.get("_silas_following")), "Rescued Silas begins following the player")

	# Silas can conceal the player, making ordinary fish less skittish.
	world.call("_ask_silas_to_hide")
	_check(float(world.get("_veil_time")) > 0.0, "Silas's concealment ability activates")
	world.set("_talk_cooldown", 0.0)
	world.call("_talk_to_silas")
	_finish_dialogue(world)
	world.set("_talk_cooldown", 0.0)
	world.call("_talk_to_silas")
	_finish_dialogue(world)
	_check(int(world.get("_silas_talks")) >= 2, "Multiple conversations build trust")

	# Only after getting to know him does Silas ask to come ashore.
	player.position = world.SURFACE_POINT
	world.call("_try_surface")
	_finish_dialogue(world)
	_check(bool(world.get("_choice_active")), "Surface invitation gives an actual choice")
	world.call("_choose_surface", true)
	_check(not bool(world.get("_underwater")), "Inviting Silas returns to shore")
	_check(bool(world.get("_silas_ashore")), "Silas chooses to come ashore")
	_check(silas.texture is AtlasTexture, "On land Silas uses his humanoid sprite")
	_finish_dialogue(world)

	world.call("_go_underwater")
	_check(bool(world.get("_underwater")), "Player can dive back in")
	_check(silas.texture == world.SILAS_FISH, "Silas returns to his fish sprite underwater")
	_check(bool(world.get("_silas_following")), "Companion relationship persists across dives")

	prototype.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Diving prototype tests passed")
	quit(1 if failures > 0 else 0)

func _finish_dialogue(world: Node) -> void:
	for i in range(12):
		if not bool(world.get("_dialogue_active")) or bool(world.get("_choice_active")):
			return
		world.call("_advance_dialogue")

func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
