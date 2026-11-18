extends SceneTree

# Run from the Godot project directory:
# godot --headless --path . -s res://tests/diving_prototype_test.gd
#
# Headless integration checks for the diving branch's separate vertical slice.
const PROTOTYPE: PackedScene = preload("res://scenes/diving_prototype.tscn")
const SILAS_FISH: Texture2D = preload("res://sprites/fish/silas_eel.png")
const PENNI_PORTRAIT: Texture2D = preload("res://sprites/characters/penni/penni_portrait.png")
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
	var level_art: Node2D = world.get_node("LevelArt") as Node2D
	var foreground_art: Node2D = world.get_node("ForegroundArt") as Node2D
	var spawn_group: Node2D = world.get_node("FishSpawns") as Node2D
	var locations: Node2D = world.get_node("Points") as Node2D
	var silas_burrow: Vector2 = (locations.get_node("SilasBurrow") as Marker2D).position
	var tangled_net: Vector2 = (locations.get_node("TangledNet") as Marker2D).position
	var surface_point: Vector2 = (locations.get_node("SurfaceExit") as Marker2D).position
	_check(level_art.get_node_or_null("Solids") is TileMapLayer and foreground_art != null,
		"Compatibility test uses the real lagoon's solid-wall tiles and foreground art")
	_check(world.scene_file_path == "res://scenes/lagoon_area.tscn",
		"Old combat test scene instances the canonical underwater level, not a duplicate")
	_check(spawn_group.get_child_count() == 8 and spawn_group.get_child(0) is DivingFishSpawn,
		"Fish are controlled by editor-placeable spawn markers")
	_check(locations.has_node("Entry") and locations.has_node("ShellGarden"),
		"Story locations and dive entry are editor-placeable markers")
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
	_check(wild_fish.size() == spawn_group.get_child_count(),
		"Every configured fish spawn marker creates one autonomous fish")
	_check(not bool(world.get("_silas_following")), "Silas is initially independent")
	_check(not bool(world.get("_silas_met")), "Silas is a hidden talking-fish surprise")

	# A click anywhere fires an actual projectile in that direction; it
	# never auto-targets a fish or catches one merely by clicking it.
	var combat: DivingCombat = world.get_node("Combat") as DivingCombat
	var net: DivingNetProjectile = world.get_node("NetProjectile") as DivingNetProjectile
	var first_fish: DivingWildFish = wild_fish[0]
	var target: Vector2 = first_fish.position
	var before: int = world.call("_total_catches")
	player.position = target + Vector2(-185.0, -10.0)
	world.call("_try_catch", target)
	_check(net.is_busy() and net.state == DivingNetProjectile.State.OUTBOUND,
		"Click fires the net projectile even without a fish within reach")
	net.call("_process", 1.0)
	_check(not combat.is_active() and net.state == DivingNetProjectile.State.RETURNING,
		"Fish beyond maximum net range cannot be hooked")
	_check(is_equal_approx(net.tip.distance_to(player.position + Vector2(0.0, -7.0)), net.max_range),
		"Net reaches its hard maximum distance and then retracts")
	net.call("_process", 1.0)
	_check(not net.is_busy() and not combat.is_active(),
		"A missed net returns to the player without opening combat")
	_check(int(world.call("_total_catches")) == before,
		"Long-distance casts never award fish")

	# The same shot may hit a moving fish along its path. Its collision
	# starts the original parry/reel combat, with a real tether attached.
	player.position = target + Vector2(-65.0, 0.0)
	world.call("_try_catch", target + Vector2(200.0, 0.0))
	_check(net.is_busy() and not combat.is_active(),
		"Firing does not start combat before the projectile reaches a fish")
	net.call("_process", 0.4)
	_check(net.is_latched() and combat.is_active(),
		"Swept projectile collision latches to the fish and starts combat")
	_check(int(world.call("_total_catches")) == before,
		"Fish is not automatically caught on projectile impact")
	_check(not hud.has_node("CombatPanel"),
		"Underwater combat uses no large panel or progress bars")
	_check(net.is_latched(), "Tension feedback stays on the actual attached net")
	var initial_distance: float = combat.line_distance
	var initial_progress: float = combat.progress
	_check(initial_distance > combat.catch_distance + combat.reel_pixels_per_scroll * 2.0,
		"Fish begins visibly farther than the net landing distance")
	_check(not hud.has_node("CombatStagger"),
		"Stagger is retained internally without a visible bar")
	combat.tension = 0.72
	world.call("_update_net_tension")
	_check(net.get_line_color().r > net.calm_line_color.r,
		"Raised tension visibly warms the net's color")
	combat.call("_start_windup")
	combat.call("_start_attack")
	combat.reel_scroll()
	combat.reel_scroll()
	combat.reel_scroll()
	_check(combat.is_active() and combat.reel_open and not combat.free_reel,
		"One perfect parry opens contested reeling without an automatic stun or catch")
	world.call("_update_net_tension")
	_check(is_zero_approx(combat.tension) and net.get_line_color().is_equal_approx(net.calm_line_color),
		"Perfect parry clears tension and restores the pale net line")
	_check(is_equal_approx(combat.stagger, combat.perfect_stagger_gain),
		"Perfect parry raises stagger but needs additional pressure to break the fish")
	_check(is_equal_approx(combat.line_distance, initial_distance)
		and is_equal_approx(combat.progress, initial_progress),
		"Parrying alone doesn't move the fish or fill the catch progress bar")

	combat.reel_scroll()
	world.call("_sync_combat_fish", 0.016)
	_check(combat.is_active() and combat.line_distance < initial_distance,
		"One earned reel pulls the fish closer but does not catch it from far away")
	_check(is_equal_approx(
		first_fish.position.distance_to(player.position), combat.line_distance
	), "Fish's visible position matches the actual catch distance")

	# The next authored attack can be parried to fill the species' meter.
	combat.call("_start_warning")
	combat.call("_start_windup")
	combat.call("_start_attack")
	combat.reel_scroll()
	combat.reel_scroll()
	combat.reel_scroll()
	_check(combat.phase == DivingCombat.Phase.STUN and combat.free_reel,
		"Enough perfect parries fill mullet stagger and earn the free-reel stun")

	var pulls: int = 0
	while combat.is_active() and pulls < 25:
		combat.reel_scroll()
		pulls += 1
	_check(pulls > 1, "Even after stagger break, the fish needs several actual reel pulls")
	_check(not combat.is_active() and not net.is_busy(),
		"Winning at close range releases the net projectile")
	_check(int(world.call("_total_catches")) == before + 1,
		"Only winning combat by pulling the fish in adds it to storage")
	_check(wild_fish.size() == 7, "Caught fish disappears from the lagoon")

	# An escaped fish remains physically present for future exploration.
	var second: DivingWildFish = wild_fish[0]
	player.position = second.position + Vector2(-40.0, 0.0)
	world.call("_try_catch", second.position)
	net.call("_process", 0.2)
	_check(net.is_latched() and combat.is_active(),
		"A second directional cast can latch onto another species")
	combat.call("_start_windup")
	combat.reel_scroll()
	_check(int(combat.phase) == DivingCombat.Phase.DASH,
		"An early scroll triggers the original missed-parry dash")
	combat.release()
	_check(not combat.is_active() and not net.is_busy() and second.catch_cooldown > 0.0,
		"Releasing the fish frees the net and lets the fish swim away")
	_check(int(world.call("_total_catches")) == before + 1,
		"Escaped fish are never added to storage")

	# Silas first asks to be pulled free; simply speaking to him or
	# clicking the tangled net must not recruit him.
	player.position = silas_burrow + Vector2(0, -14)
	world.call("_talk_to_silas")
	_check(bool(world.get("_silas_met")), "Talking eel asks to be pulled out")
	_check(not bool(world.get("_net_cleared")) and not bool(world.get("_silas_following")),
		"Silas is still trapped after the first conversation")
	_check(DialogueManager.is_active and DialogueManager.get_current_speaker_name() == "???",
		"Shared dialogue manager preserves Silas's mysterious introduction")
	if dialogue != null:
		var npc_portrait: TextureRect = dialogue.get_node("NPCPortrait") as TextureRect
		_check(npc_portrait.texture == SILAS_FISH,
			"Dialogue shows the actual eel sprite, not the humanoid portrait")
		_check(npc_portrait.flip_h,
			"Underwater fish portraits face Penni")
		_check((dialogue.get_node("PlayerPortrait") as TextureRect).texture == PENNI_PORTRAIT,
			"Penni retains her original dialogue portrait")
	_finish_dialogue()
	var trapped_eel: DivingWildFish = world.get("_silas_rescue_target") as DivingWildFish
	_check(trapped_eel != null and trapped_eel.trapped and not silas.visible,
		"After the help request, a stationary Silas fish becomes net-catchable")
	_check(wild_fish.has(trapped_eel) and wild_fish.size() == spawn_group.get_child_count() + 1,
		"Silas is a special world target, not an automatic collectible")

	# Missed rescue: the fish stays trapped instead of entering storage.
	player.position = trapped_eel.position + Vector2(-40.0, 0.0)
	world.call("_try_catch", trapped_eel.position + Vector2(160, 0))
	net.call("_process", 0.22)
	_check(net.is_latched() and combat.is_active(),
		"The actual projectile can hook Silas for parry/reel combat")
	combat.release()
	_check(not bool(world.get("_net_cleared")) and not bool(world.get("_silas_following")),
		"Losing the encounter does not rescue Silas")
	_check(is_equal_approx(trapped_eel.position.distance_to(silas_burrow + Vector2(0, -16)), 0.0),
		"A failed rescue puts Silas back at the burrow")
	_check(int(world.call("_total_catches")) == before + 1,
		"Silas is never counted as an ordinary fish capture")

	# Winning actually reels him free; the following relationship begins
	# once his thank-you dialogue finishes.
	trapped_eel.catch_cooldown = 0.0
	player.position = trapped_eel.position + Vector2(-40.0, 0.0)
	world.call("_try_catch", trapped_eel.position + Vector2(160, 0))
	net.call("_process", 0.22)
	_check(combat.is_active(), "Silas can be netted again after a failed rescue")
	combat.call("_start_recovery")
	combat.line_distance = combat.catch_distance + 1.0
	combat.reel_scroll()
	_check(bool(world.get("_net_cleared")), "Reeling Silas all the way in completes his rescue")
	_check(not bool(world.get("_silas_following")), "Silas thanks you before joining the party")
	_check(world.get("_silas_rescue_target") == null,
		"Rescued Silas no longer exists as a separate catchable fish")
	_check(int(world.call("_total_catches")) == before + 1,
		"Rescuing a companion never adds him to the inventory")
	_finish_dialogue()
	_check(bool(world.get("_silas_following")), "After being rescued, Silas swims alongside Penni")

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
	player.position = surface_point
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
