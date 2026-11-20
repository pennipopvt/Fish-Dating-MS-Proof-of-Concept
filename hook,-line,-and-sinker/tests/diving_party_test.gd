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
	await entrance.call_party_to_dock(party.members(), dock)
	_check(entrance._staged.size() == 2
		and world.get_node_or_null("DiveGuest_test_npc") != null
		and world.get_node_or_null("DiveGuest_barracuda") != null,
		"Diving call brings only selected guests onto the dock")
	await entrance.jump_party_in(dock, func(_at: Vector2) -> void: pass)
	_check(entrance._staged.is_empty() and entrance._fish_visuals.size() == 2,
		"Both guests jump, poof and switch to fish sprites")
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
	main.queue_free()
	print("diving_party_test: PASS" if failures == 0 else
		"diving_party_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
