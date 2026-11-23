extends Node

# Run: godot --headless --path . res://tests/sea_population_and_visuals_test.tscn
# Validate post-tutorial habitat generation, never-on-camera spawns, quota
# species minima, and fish-local combat animation reuse.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const VISUAL: PackedScene = preload("res://prefabs/sea_fish_combat_visual.tscn")
var failures: int = 0


func _ready() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var sea: DivingWorld = main.get_node("SubViewportContainer/SubViewport/World/Sea") as DivingWorld
	var player: Player = sea.get_parent().get_node("Player") as Player
	var camera: Camera2D = sea.get_parent().get_node("CameraController/Camera2D") as Camera2D
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var population: SeaPopulation = sea.get_node("SeaPopulation") as SeaPopulation
	var regions: Node2D = sea.get_node("SpawnRegions") as Node2D
	var pool: Array = sea.get("_wild_fish")
	# The fish are Node2D actors, so their open-water movement test must
	# recognize the same polygons that physically stop Penni and the net.
	var spline_colliders: Array = sea.get("_terrain_colliders")
	var expected_terrains: int = _count_sea_terrains(sea)
	_check(expected_terrains >= 9 and spline_colliders.size() == expected_terrains,
		"All solid and decorative splines are discovered even inside nested editor groups")
	var blocked_point: Vector2 = Vector2.INF
	var actors: Node2D = sea.get_node("FishActors") as Node2D
	for candidate in spline_colliders:
		var collider: CollisionPolygon2D = candidate as CollisionPolygon2D
		if collider == null:
			continue
		var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(collider.polygon)
		for i in range(0, triangles.size(), 3):
			var local_center: Vector2 = (
				collider.polygon[triangles[i]] +
				collider.polygon[triangles[i + 1]] +
				collider.polygon[triangles[i + 2]]
			) / 3.0
			var sea_point: Vector2 = actors.to_local(collider.to_global(local_center))
			if sea_point.y > 172.0 and sea_point.y < 740.0 \
					and not bool(sea.call("_is_open_water", sea_point)):
				blocked_point = sea_point
				break
		if blocked_point != Vector2.INF:
			break
	_check(blocked_point != Vector2.INF,
		"Fish treat the interior of a spline collider as solid rock")
	if blocked_point != Vector2.INF:
		# Disabling an individual spline is an authoring choice: the fish
		# query must follow it without needing a different terrain object.
		for candidate in spline_colliders:
			var shape: SeaTerrain = (candidate as CollisionPolygon2D).get_parent().get_parent() as SeaTerrain
			shape.collision_enabled = false
		_check(bool(sea.call("_is_open_water", blocked_point)),
			"Fish swim through decorative splines with collision disabled")
		for candidate in spline_colliders:
			var shape: SeaTerrain = (candidate as CollisionPolygon2D).get_parent().get_parent() as SeaTerrain
			shape.collision_enabled = true
		_check(not bool(sea.call("_is_open_water", blocked_point)),
			"Fish avoid the same terrain again when collision is enabled")
	var clear_point: Vector2 = Vector2.INF
	for x in range(-1700, -100, 100):
		for y in range(220, 700, 80):
			var candidate_point := Vector2(x, y)
			if bool(sea.call("_is_open_water", candidate_point)):
				clear_point = candidate_point
				break
		if clear_point != Vector2.INF:
			break
	_check(clear_point != Vector2.INF,
		"Fish can still swim in open water between the spline formations")
	if clear_point != Vector2.INF and blocked_point != Vector2.INF:
		var test_fish := DivingWildFish.new()
		test_fish.is_open = Callable(sea, "_is_open_water")
		var avoided: Vector2 = test_fish._avoid_solids(clear_point, blocked_point)
		_check(avoided != blocked_point
			and bool(sea.call("_is_open_water", avoided)),
			"Existing free-swimming fish slide or turn away from spline rock")
		test_fish.free()
	_check(regions.get_child_count() >= 5,
		"Expanded sea has five editable habitat regions, including the far and deep areas")
	var guide: SeaEditorGuide = sea.get_node("EditorGuide") as SeaEditorGuide
	_check(guide.map_origin == Vector2(-1792, 0)
		and guide.map_size == Vector2(1984, 760)
		and sea.call("_sea_bounds").has_point(Vector2(-1650, 670)),
		"Sea now extends 512 more pixels left with its dock-side boundary intact")
	var water: ColorRect = sea.get_parent().get_node("Water") as ColorRect
	_check(water.position == Vector2(-2052, 140)
		and water.size == Vector2(4852, 660),
		"Water visual automatically includes the larger sea and original shoreline")
	# Changing the guide in Inspector must resize the Water in this same
	# world scene, without reloading or manually editing World/Water.
	guide.map_origin = Vector2(-2048, 0)
	guide.map_size = Vector2(2240, 900)
	_check(water.position == Vector2(-2308, 140)
		and water.size == Vector2(5108, 800),
		"Live guide edits automatically expand water horizontally and downward")
	guide.map_origin = Vector2(-1792, 0)
	guide.map_size = Vector2(1984, 760)
	_check(water.position == Vector2(-2052, 140)
		and water.size == Vector2(4852, 660),
		"Restoring sea bounds restores the water coverage automatically")
	_check(not population.has_generated() and pool.size() == 3,
		"Tutorial begins with only two authored fish and hidden Silas target")
	var original_ids: Dictionary = {}
	for fish in pool:
		original_ids[fish.get_instance_id()] = true
	player.set_swimming(true, sea.call("_sea_bounds"))
	player.position = Vector2(-590.0, 220.0)
	camera.reset_smoothing()
	camera.force_update_scroll()
	var fish: DivingWildFish
	var data: FishData
	for candidate in pool:
		var wild: DivingWildFish = candidate as DivingWildFish
		if wild != null and not wild.trapped:
			fish = wild
			data = (sea.get("_fish_data") as Dictionary).get(wild) as FishData
			break
	_check(fish != null and data != null, "An existing normal fish can be used in tutorial")
	if fish == null:
		_finish(main)
		return

	var flags: Dictionary = NPCManager.get_npc_state(story.silas_data.npc_id)["flags"]
	flags[&"silas_following"] = true
	fish.companion_weakened = true
	story.on_first_companion_catch(fish)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(population.has_generated(), "First assisted catch triggers the once-only habitat population")
	var counts: Dictionary = {}
	var offscreen: bool = true
	var non_colliding: bool = true
	var visible_size: Vector2 = camera.get_viewport_rect().size / camera.zoom.abs()
	# Fish may swim a few pixels into the *hidden* spawn buffer between
	# generation and this assertion. Only entering the real viewport is a
	# visible pop-in, so test the screen bounds rather than its larger margin.
	var view: Rect2 = Rect2(camera.get_screen_center_position() - visible_size * 0.5,
		visible_size)
	var created: int = 0
	for candidate in sea.get("_wild_fish"):
		var wild: DivingWildFish = candidate as DivingWildFish
		if wild == null or original_ids.has(wild.get_instance_id()):
			continue
		created += 1
		counts[wild.fish_name] = int(counts.get(wild.fish_name, 0)) + 1
		if view.has_point(wild.global_position):
			offscreen = false
		if not sea.call("_is_open_water", wild.position):
			non_colliding = false
	_check(created >= 2, "Habitats create multiple ordinary fish after the catch")
	_check(int(counts.get(&"mullet", 0)) >= 1 and int(counts.get(&"porgy", 0)) >= 1,
		"First new population contains guaranteed remaining quota species")
	_check(offscreen and non_colliding, "Spawned fish start outside camera and spline solids")
	var far_population: bool = false
	var deep_population: bool = false
	for candidate in sea.get("_habitat_fish"):
		var wild: DivingWildFish = candidate as DivingWildFish
		if wild == null:
			continue
		far_population = far_population or wild.position.x < -1000.0
		deep_population = deep_population or wild.position.y > 535.0
	_check(far_population and deep_population,
		"Expanded offscreen areas generate fish for new horizontal and depth exploration")
	var count_before: int = (sea.get("_wild_fish") as Array).size()
	story.on_first_companion_catch(fish)
	await get_tree().process_frame
	_check((sea.get("_wild_fish") as Array).size() == count_before,
		"Repeated tutorial event never respawns a fresh population")

	# The same visual is reusable on any normal DivingWildFish and needs no
	# fishing-state or enemy-attack rewrite. Telegraphed strips follow true
	# attack duration rather than fixed animation FPS.
	var combat: DivingCombat = sea.get_node("Combat") as DivingCombat
	_check(combat.begin(fish, data, 40.0, 175.0, 0.5),
		"Ordinary FishingCombat starts without any visual ownership")
	var visual: SeaFishCombatVisual = VISUAL.instantiate() as SeaFishCombatVisual
	fish.add_child(visual)
	visual.bind_combat(combat)
	var phase_art: AnimatedSprite2D = visual.get_node("CombatPhase") as AnimatedSprite2D
	var feedback: AnimatedSprite2D = visual.get_node("ParryFlash") as AnimatedSprite2D
	var frames: SpriteFrames = phase_art.sprite_frames
	_check(frames.has_animation(&"prewindup") and frames.has_animation(&"windup")
		and frames.has_animation(&"splash") and frames.has_animation(&"miss")
		and frames.has_animation(&"perfect") and frames.has_animation(&"close"),
		"Fish-local animation pack reuses existing effects with authored new lead-ins")
	_check(frames.get_frame_count(&"prewindup") > 1
		and frames.get_frame_count(&"windup") > 1,
		"Both new lead-in images provide usable animation frames")
	combat.phase_time = combat.attack.pre_windup_duration * 0.2
	visual._process(0.0)
	_check(phase_art.visible and phase_art.animation == &"prewindup"
		and phase_art.frame > 0,
		"Prewindup art advances according to actual selected attack duration")
	combat._start_windup()
	combat.phase_time = combat.attack.windup_duration * 0.2
	visual._process(0.0)
	_check(phase_art.visible and phase_art.animation == &"windup"
		and phase_art.frame > 0,
		"Windup uses new animation frames and authored phase duration")
	combat.parried.emit(&"close")
	_check(feedback.visible and feedback.animation == &"close",
		"Close parry uses existing feedback sheet on the fish")
	combat.parried.emit(&"perfect")
	_check(feedback.visible and feedback.animation == &"perfect",
		"Perfect parry uses existing success flash on the fish")
	combat.release()
	visual._process(0.0)
	_check(not phase_art.visible and not feedback.visible,
		"Combat art clears when the ordinary combat state ends")

	# First return to shore advances the period. Next confirmed dive
	# must replace ONLY generated habitat fish, preserving tutorial actors.
	var previous_batch: Array = (sea.get("_habitat_fish") as Array).duplicate()
	var old_ids: Dictionary = {}
	for candidate in previous_batch:
		var wild: DivingWildFish = candidate as DivingWildFish
		if is_instance_valid(wild):
			old_ids[wild.get_instance_id()] = true
	_check(previous_batch.size() >= 2, "First period registered habitat fish separately")
	GameManager.rest()
	_check(not population.has_generated_for_current_period(),
		"After clock advances, a fresh habitat generation is needed")
	player.set_swimming(false)
	sea.enter_from_dock()
	await get_tree().process_frame
	_check(population.has_generated_for_current_period(),
		"Entering sea during afternoon refreshes habitat population")
	var second_batch: Array = sea.get("_habitat_fish")
	var second_ids: Dictionary = {}
	var new_mullet: int = 0
	var new_porgy: int = 0
	for candidate in second_batch:
		var wild: DivingWildFish = candidate as DivingWildFish
		if not is_instance_valid(wild):
			continue
		second_ids[wild.get_instance_id()] = true
		if wild.fish_name == &"mullet":
			new_mullet += 1
		elif wild.fish_name == &"porgy":
			new_porgy += 1
	_check(second_ids.size() >= 2 and new_mullet >= 1 and new_porgy >= 1,
		"Afternoon population has guaranteed quota species as well")
	var replaced: bool = true
	for old_id in old_ids:
		if second_ids.has(old_id):
			replaced = false
	_check(replaced, "New period replaces previous habitat actors")
	var scripted_preserved: bool = true
	for old_id in original_ids:
		var found: bool = false
		for candidate in sea.get("_wild_fish"):
			var wild: DivingWildFish = candidate as DivingWildFish
			if is_instance_valid(wild) and wild.get_instance_id() == old_id:
				found = true
				break
		if not found:
			scripted_preserved = false
	_check(scripted_preserved, "Scripted tutorial and Silas actors survive refresh")
	sea.enter_from_dock()
	var same_ids: Dictionary = {}
	for candidate in sea.get("_habitat_fish"):
		var wild: DivingWildFish = candidate as DivingWildFish
		if is_instance_valid(wild):
			same_ids[wild.get_instance_id()] = true
	_check(same_ids == second_ids,
		"Second entry in the same period never replenishes fish")
	_finish(main)


func _finish(main: Node) -> void:
	if is_instance_valid(main):
		main.queue_free()
	print("sea_population_and_visuals_test: PASS" if failures == 0 else
		"sea_population_and_visuals_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


# New art can be grouped arbitrarily; verify every nested spline is read.
func _count_sea_terrains(parent: Node) -> int:
	var result: int = 0
	for child in parent.get_children():
		if child is SeaTerrain:
			result += 1
		result += _count_sea_terrains(child)
	return result


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
