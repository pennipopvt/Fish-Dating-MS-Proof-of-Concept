extends Node

# Run: godot --headless --path . res://tests/sea_oxygen_test.tscn
# Tests the oxygen resource, screen warning, held-catch banking/loss, and
# the actual blackout return without changing the shared storage inventory.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const MULLET: FishData = preload("res://resources/fish/mullet.tres")
const PORGY_ITEM: ItemData = preload("res://resources/items/porgy.tres")
var failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	GameManager.reset_clock()
	FishingManager.current_storage.clear()
	FishingManager.storage_changed.emit()

	var oxygen := SeaOxygen.new()
	add_child(oxygen)
	oxygen.capacity_seconds = 20.0
	oxygen.warning_fraction = 0.25
	var hud := SeaOxygenHud.new()
	add_child(hud)
	oxygen.oxygen_changed.connect(
		func(ratio: float, active: bool) -> void:
			hud.show_oxygen(ratio, active, oxygen.warning_fraction)
	)
	oxygen.begin_dive(false)
	_check(not oxygen.enabled and not hud.visible,
		"Before first Silas-assisted catch no oxygen timer or meter is shown")
	oxygen.step(40.0)
	_check(is_equal_approx(oxygen.remaining_seconds, 20.0),
		"First tutorial swimming has no oxygen cost")
	oxygen.activate()
	_check(oxygen.enabled and hud.visible and is_equal_approx(oxygen.ratio(), 1.0),
		"Unlock starts with a full visible tank")
	oxygen.step(16.0)
	_check(oxygen.ratio() <= 0.21 and oxygen.ratio() >= 0.19,
		"Oxygen decreases at normal rate near the surface")
	_check(is_equal_approx(oxygen.drain_multiplier_at_depth(154.0), 1.0)
		and is_equal_approx(oxygen.drain_multiplier_at_depth(394.0), 1.4)
		and is_equal_approx(oxygen.drain_multiplier_at_depth(634.0), 1.8)
		and is_equal_approx(oxygen.drain_multiplier_at_depth(900.0), 1.8),
		"Depth drain smoothly grows from 1x to 1.8x and caps at deeper levels")
	var vignette: ColorRect = hud.get_node("LowOxygenVignette") as ColorRect
	var intensity: float = (vignette.material as ShaderMaterial).get_shader_parameter(
		"warning_strength")
	_check(intensity > 0.0 and intensity < 1.0,
		"Low oxygen applies a gradual red edge vignette")
	oxygen.pause()
	oxygen.step(10.0)
	_check(is_equal_approx(oxygen.remaining_seconds, 4.0),
		"Pausing oxygen during the return prevents unfair exhaustion")
	oxygen.end_dive()
	_check(not oxygen.enabled and not hud.visible and is_equal_approx(oxygen.ratio(), 1.0),
		"Surface exit hides the meter and refills the next expedition")
	oxygen.begin_dive(true)
	oxygen.step(5.0, 634.0)
	_check(is_equal_approx(oxygen.remaining_seconds, 11.0),
		"At deep water, 5 real seconds consume 9 seconds worth of oxygen")
	oxygen.end_dive()
	hud.queue_free()
	oxygen.queue_free()

	var bag := SeaDiveInventory.new()
	add_child(bag)
	bag.begin_dive()
	bag.record_fish(MULLET)
	_check(bag.count_species(&"mullet") == 1
		and FishingManager.count_in_storage(&"mullet") == 0,
		"Underwater fish stay in the carried bag until surfacing")
	bag.secure_catch()
	_check(bag.count_carried() == 0 and FishingManager.count_in_storage(&"mullet") == 1,
		"Safe return lands carried fish without duplicating them")
	bag.secure_catch()
	_check(FishingManager.count_in_storage(&"mullet") == 1,
		"Repeating the deposit cannot duplicate caught fish")
	bag.record_fish(MULLET)
	bag.lose_catch()
	_check(FishingManager.count_in_storage(&"mullet") == 1
		and bag.count_carried() == 0,
		"Losing a dive never erases fish banked on an earlier expedition")
	bag.queue_free()

	# Exercise the actual Sea -> Transition oxygen failure connection using
	# the one persistent World and Camera, not a mocked surface handler.
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var sea: DivingWorld = main.get_node("SubViewportContainer/SubViewport/World/Sea") as DivingWorld
	var real_hud: SeaOxygenHud = sea.get_node("SeaOxygenHud") as SeaOxygenHud
	var camera: Camera2D = sea.get_parent().get_node("Player/Camera2D") as Camera2D
	_check(real_hud.get_parent() == sea and not camera.is_ancestor_of(real_hud)
		and not real_hud.follow_viewport_enabled,
		"HUD belongs to the sea UI canvas, not the moving player camera")
	_check(real_hud.get_node("LowOxygenVignette").get_rect().position == Vector2.ZERO
		and real_hud.get_node("MeterTrack").position == Vector2(10.0, 10.0),
		"Vignette fills the viewport and meter is anchored inside its top-left corner")
	var player: Player = sea.get_parent().get_node("Player") as Player
	var transition: SeaDiveTransition = main.get_node("TransitionLayer") as SeaDiveTransition
	var sea_bag: SeaDiveInventory = sea.get_node("SeaDiveInventory") as SeaDiveInventory
	var sea_o2: SeaOxygen = sea.get_node("SeaOxygen") as SeaOxygen
	_check(sea_o2.depth_ramp_pixels == 480.0
		and is_equal_approx(sea_o2.deepest_drain_multiplier, 1.8),
		"Sea scene exposes depth-drain tuning on the existing oxygen node")
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	story.get("_events")[&"first_companion_catch"] = true
	NPCManager.get_npc_state(story.silas_data.npc_id)["flags"][&"silas_surface_transformed"] = true
	_check(GameManager.begin_dive_period(), "Morning expedition reserves its time slot")
	GameManager.diving_session_active = true
	transition.underwater = true
	player.set_swimming(true, sea.call("_sea_bounds"))
	sea_bag.begin_dive()
	sea_bag.record_fish(MULLET)
	FishingManager.add_to_storage(PORGY_ITEM)
	var before_porgy: int = FishingManager.count_in_storage(&"porgy")
	sea_o2.begin_dive(true)
	sea_o2.step(sea_o2.capacity_seconds)
	_check(transition.transitioning and sea_bag.count_carried() == 1,
		"Empty oxygen immediately triggers an in-progress blackout, not a free catch")
	await get_tree().create_timer(1.35).timeout
	_check(not transition.underwater and not transition.transitioning
		and not player.swimming,
		"Blackout returns Penni to the same shore world")
	_check(sea_bag.count_carried() == 0
		and FishingManager.count_in_storage(&"porgy") == before_porgy
		and FishingManager.count_in_storage(&"mullet") == 1,
		"Blackout loses only current dive catches, preserving earlier stored inventory")
	_check(GameManager.get_period() == GameManager.Times.AFTERNOON
		and not GameManager.diving_session_active,
		"Failed morning dive still advances the clock to afternoon")
	_check(not sea_o2.enabled,
		"Blackout hides oxygen until Penni enters the water again")
	_check(not DialogueManager.is_active,
		"An unaccompanied blackout does not invent fish dialogue")
	main.queue_free()
	print("sea_oxygen_test: PASS" if failures == 0 else
		"sea_oxygen_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
