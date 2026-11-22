extends Node

# Run: godot --headless --path . res://tests/diving_party_test.tscn
# Covers party, ephemeral dock cast, transformation and sea follower lifecycle.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
var failures: int = 0


func _ready() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var transition: SeaDiveTransition = main.get_node("TransitionLayer") as SeaDiveTransition
	var party: DivingParty = transition.get_node("DivingParty") as DivingParty
	var entrance: SeaPartyEntrance = transition.get_node("PartyEntrance") as SeaPartyEntrance
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var player: Player = world.get_node("Player") as Player
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var dock: Node2D = world.get_node("Dock") as Node2D
	var flags: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)["flags"]
	_check(party.members().is_empty(), "Tutorial begins without selected companions")
	flags[&"silas_surface_transformed"] = true
	story.silas_surface_reveal_finished.emit()
	_check(party.members().size() == 1 and party.has_companion(SILAS.npc_id),
		"First return automatically selects Silas")
	_check(main.call("invite_diving_companion", KUDA) and party.invite(KUDA)
		and party.members().size() == 2,
		"Party selection is separate from all townhouse actors")
	var third := NPCData.new()
	third.npc_id = &"third"
	third.portrait = KUDA.portrait
	third.underwater_sprite = KUDA.underwater_sprite
	_check(party.invite(third), "Party allows three members")
	var fourth := NPCData.new()
	fourth.npc_id = &"fourth"
	_check(not party.invite(fourth) and party.members().size() == 3,
		"Fourth member is refused with Penni's thought")
	_check(party.dismiss(&"third") and party.members().size() == 2,
		"Companions can leave the school without moving any actor")
	var approach: Marker2D = sea.get_node("Points/SilasSurfaceApproach") as Marker2D
	var dock_wait: Marker2D = sea.get_node("Points/SilasDockWait") as Marker2D
	_check(approach.position.y >= DivingWorld.SEA_TOP + 50.0,
		"Returning fish begin the jump deep underwater rather than pausing at the surface")
	_check(entrance.surface_approach_position(approach.global_position, 0)
		== approach.global_position
		and entrance.surface_approach_position(approach.global_position, 2).x
		< entrance.surface_approach_position(approach.global_position, 1).x
		and entrance.surface_approach_position(approach.global_position, 2).y
		> entrance.surface_approach_position(approach.global_position, 1).y,
		"Each additional companion starts surfacing farther back and deeper")
	_check(entrance.surface_dock_position(dock_wait.global_position, 1).x
		> entrance.surface_dock_position(dock_wait.global_position, 0).x
		and entrance.surface_dock_position(dock_wait.global_position, 2).x
		> entrance.surface_dock_position(dock_wait.global_position, 1).x,
		"Three-person landing slots spread out across the dock")
	await entrance.call_party_to_dock(party.members(), dock)
	_check(entrance._staged.size() == 2
		and world.get_node_or_null("DiveGuest_test_npc") != null
		and world.get_node_or_null("DiveGuest_barracuda") != null,
		"Diving call brings only selected guests onto the dock")
	await entrance.jump_party_in(dock, func(_at: Vector2) -> void: pass)
	_check(entrance._staged.is_empty() and entrance._fish_visuals.size() == 2,
		"Both guests jump, poof and switch to fish sprites")
	if entrance._fish_visuals.size() == 2:
		var kuda_art: Sprite2D = entrance._fish_visuals[1]
		_check(is_equal_approx(float(kuda_art.texture.get_width()) * kuda_art.scale.x,
			KUDA.sea_visuals.follower_width),
			"Kuda's dock-entry fish uses the same per-NPC world sprite size")
	player.set_swimming(true, sea._sea_bounds())
	sea.activate_diving_party(party.members())
	var silas: SeaNPC = sea.get_node("NPCs/Silas") as SeaNPC
	_check(silas.visible and silas.following and story.has_silas_flag(&"silas_following"),
		"Silas resumes his existing combat-capable underwater actor")
	_check(sea.get_node_or_null("NPCs/PartyFish_barracuda") != null,
		"Additional school members follow underwater in fish form")
	entrance.clear()
	sea.end_diving_party()
	await get_tree().process_frame
	_check(not silas.following and not silas.visible
		and not story.has_silas_flag(&"silas_following")
		and sea.get_node_or_null("NPCs/PartyFish_barracuda") == null,
		"Surfacing removes temporary sea actors")
	_check(party.members().size() == 2 and party.has_companion(SILAS.npc_id),
		"School selection remains for the next dive")
	# Now exercise the real confirmed-dive entrypoint, not just isolated steps.
	# The original first-dive cinematic is not replayed on this return dive.
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	player.set_swimming(false)
	GameManager.reset_clock()
	transition.start_confirmed_dive(dock)
	await get_tree().create_timer(4.2).timeout
	_check(transition.underwater and not transition.transitioning
		and player.swimming and silas.following
		and sea.get_node_or_null("NPCs/PartyFish_barracuda") != null,
		"Confirmed dock dive independently summons the school and resumes swimming")
	var deeper_entry: Marker2D = sea.get_node("Points/Entry") as Marker2D
	print("[DIVE ENTRY] actual=", player.global_position, " marker=", deeper_entry.global_position, " dock=", dock.global_position)
	_check(deeper_entry.position.y >= DivingWorld.SEA_TOP + 96.0
		and player.global_position.y >= DivingWorld.SEA_TOP + 80.0
		and player.global_position.x < dock.global_position.x - 24.0,
		"After splash, Penni and her fish descend well below the waterline and away from the dock")
	sea.call("_return_to_surface")
	await get_tree().create_timer(1.15).timeout
	var first_human: Node2D = world.get_node_or_null("SurfaceGuest_test_npc") as Node2D
	_check(not transition.underwater and transition.transitioning and player.busy
		and first_human != null and not first_human.visible
		and silas.visible,
		"On regular return, live fish stay until they reach the dock and transform")
	_check(player.animator.animation == &"idle_r" and player.last_direction > 0.0,
		"Penni faces inland after surfacing, away from the sea")
	if first_human != null:
		var visual: AnimatedSprite2D = first_human.get_node_or_null("Sprite") as AnimatedSprite2D
		if visual != null:
			_check(visual.global_position.x
				== dock_wait.global_position.x,
				"First human lands exactly at the authored dock slot")
	await get_tree().create_timer(5.2).timeout
	_check(not transition.underwater and not transition.transitioning
		and not player.swimming and not player.busy and not silas.following
		and world.get_node_or_null("SurfaceGuest_test_npc") == null
		and world.get_node_or_null("SurfaceGuest_barracuda") == null
		and sea.get_node_or_null("NPCs/PartyFish_barracuda") == null
		and party.has_companion(SILAS.npc_id),
		"After staggered poofs and fade, fish and human actors clean up but roster remains")
	main.queue_free()
	print("diving_party_test: PASS" if failures == 0 else
		"diving_party_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
