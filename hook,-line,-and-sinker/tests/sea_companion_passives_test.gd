extends Node

# Run: godot --headless --path . res://tests/sea_companion_passives_test.tscn
# Romance-unlocked passive gating, quota display, and initial-net stun.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
const MULLET: FishData = preload("res://resources/fish/mullet.tres")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	await get_tree().process_frame
	var sea: DivingWorld = main.get_node("SubViewportContainer/SubViewport/World/Sea") as DivingWorld
	var perks: SeaCompanionPassives = sea.get_node("CompanionPassives") as SeaCompanionPassives
	var bag: SeaDiveInventory = sea.get_node("SeaDiveInventory") as SeaDiveInventory
	var combat: DivingCombat = sea.get_node("Combat") as DivingCombat
	var species: DivingWildFish = sea.call("_spawn_wild_fish",
		MULLET, Vector2(-490, 260), 410, 0.0, 0.0, 0.0) as DivingWildFish
	species.battling = true
	var silas_flags: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)["flags"]
	var kuda_flags: Dictionary = NPCManager.get_npc_state(KUDA.npc_id)["flags"]
	silas_flags.erase(&"romance_complete")
	kuda_flags.erase(&"romance_complete")
	silas_flags.erase(SILAS.romance_complete_flag)
	kuda_flags.erase(KUDA.romance_complete_flag)
	sea.activate_diving_party([SILAS, KUDA])
	_check(not perks.has_passive(SILAS.npc_id) and not perks.has_passive(KUDA.npc_id),
		"Recruitment and joining the dive cannot grant overnight romance passives")
	_check(species.get_node_or_null("Identification") == null,
		"Without Silas's romance there are no identification labels")
	_check(combat.begin(species, MULLET, 40.0, 110.0, 0.5),
		"Initial net combat begins using the existing combat state machine")
	perks.on_initial_net(combat)
	_check(combat.phase == DivingCombat.Phase.WARNING,
		"Without Kuda's romance, netted fish does not start stunned")
	combat.target = null

	silas_flags[&"romance_complete"] = true
	sea.activate_diving_party([SILAS])
	_check(perks.has_passive(SILAS.npc_id) and not perks.has_passive(KUDA.npc_id),
		"Only a romanced, accompanying companion provides a passive")
	var label: Label = species.get_node("Identification") as Label
	_check(label.visible and label.text.contains("???") and label.text.begins_with("★"),
		"Silas displays unknown quota fish as ??? with a needed-quota star")
	FishingManager.catch_fish(MULLET, false)
	_check(label.text.contains("Mullet") and label.text.begins_with("★"),
		"Already caught fish become identifiable above the health bar")
	bag.record_fish(MULLET)
	FishingManager.add_to_storage(MULLET.item_data)
	_check(not label.text.begins_with("★"),
		"Quota star disappears when bag plus storage already cover remaining quota")
	perks.remove_member(SILAS.npc_id)
	_check(not label.visible,
		"Silas's identification turns off when he leaves the active party")

	kuda_flags[&"romance_complete"] = true
	sea.activate_diving_party([KUDA])
	_check(perks.has_passive(KUDA.npc_id) and not perks.has_passive(SILAS.npc_id),
		"Kuda's passive works independently from Silas's")
	_check(combat.begin(species, MULLET, 40.0, 110.0, 0.5),
		"Second net initializes an ordinary encounter")
	var usual_stun: float = maxf(combat.attack.stun_duration, 0.2)
	perks.on_initial_net(combat)
	_check(combat.phase == DivingCombat.Phase.STUN
		and is_equal_approx(combat.phase_time, usual_stun * 0.5)
		and combat.reel_open and combat.free_reel,
		"Kuda starts the existing stun phase for exactly half the normal stun")
	var remaining: float = combat.phase_time
	perks.on_initial_net(combat)
	_check(is_equal_approx(combat.phase_time, remaining),
		"Repeating an initial-net hook cannot stack or restart Kuda's stun")
	combat.target = null
	perks.clear_party()
	_check(not perks.has_passive(KUDA.npc_id),
		"Passives clear at the end of a diving party")
	main.queue_free()
	await get_tree().process_frame
	print("sea_companion_passives_test: PASS" if failures == 0 else
		"sea_companion_passives_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, description: String) -> void:
	if ok:
		print("  ok   ", description)
	else:
		failures += 1
		push_error("  FAIL " + description)
