extends Node

# One-button FIFO companion queue with simultaneous combat and no extra HUD.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
const MULLET: FishData = preload("res://resources/fish/mullet.tres")
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var player: Player = world.get_node("Player") as Player
	var commands: SeaPartyCommands = sea.get_node("PartyCommands") as SeaPartyCommands
	var transition: SeaDiveTransition = main.get_node("TransitionLayer") as SeaDiveTransition
	var party: DivingParty = transition.get_node("DivingParty") as DivingParty
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var flags: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)["flags"]
	flags[&"silas_surface_transformed"] = true
	flags[&"silas_following"] = true
	story.silas_surface_reveal_finished.emit()
	_check(party.invite(KUDA), "Kuda can join the existing two-fish DivingParty")
	transition.underwater = true
	player.set_swimming(true, sea._sea_bounds())
	sea.activate_diving_party(party.members())
	var silas_battle: DivingCompanionBattle = commands.battle_for(SILAS.npc_id)
	var kuda_battle: DivingCompanionBattle = commands.battle_for(KUDA.npc_id)
	var kuda_actor: SeaPartyFollower = sea.get_node_or_null(
		"NPCs/PartyFish_barracuda") as SeaPartyFollower
	_check(commands.party_order() == [SILAS.npc_id, KUDA.npc_id] and
		commands.available_ids() == [SILAS.npc_id, KUDA.npc_id],
		"Queue begins in party order: Silas then Kuda")
	_check(kuda_actor != null and kuda_battle != null and
		kuda_battle != silas_battle and kuda_actor.behavior is KudaCombatBehavior,
		"Kuda owns an independent battle and lethal behavior on his follower")
	if kuda_battle == null or silas_battle == null:
		_finish(main)
		return
	var f1: DivingWildFish = sea.call("_spawn_wild_fish", MULLET,
		player.position + Vector2(34.0, -16.0), 991, 0.0, 0.0, 0.0) as DivingWildFish
	var f2: DivingWildFish = sea.call("_spawn_wild_fish", MULLET,
		player.position + Vector2(85.0, 20.0), 992, 0.0, 0.0, 0.0) as DivingWildFish
	var f3: DivingWildFish = sea.call("_spawn_wild_fish", MULLET,
		player.position + Vector2(100.0, -40.0), 993, 0.0, 0.0, 0.0) as DivingWildFish
	_check(bool(sea.call("_try_companion_target", f1.position))
		and silas_battle.target == f1 and commands.next_available_id() == KUDA.npc_id,
		"First right-click sends Silas, leaving Kuda available")
	_check(bool(sea.call("_try_companion_target", f2.position))
		and silas_battle.target == f1 and kuda_battle.target == f2
		and commands.available_ids().is_empty(),
		"Second right-click sends Kuda to a DIFFERENT fish simultaneously")
	_check(not bool(sea.call("_try_companion_target", f3.position))
		and silas_battle.target == f1 and kuda_battle.target == f2,
		"No available companion means no new assignment or silent retarget")
	_check(bool(sea.call("_try_companion_target", f2.position))
		and not kuda_battle.is_active() and silas_battle.target == f1
		and commands.available_ids() == [KUDA.npc_id],
		"Right-clicking Kuda's assigned fish recalls only Kuda")
	_check(bool(sea.call("_try_companion_target", f3.position))
		and kuda_battle.target == f3 and silas_battle.target == f1,
		"Returned Kuda can be sent back out without recalling Silas")
	_check(bool(sea.call("_try_companion_target", f1.position))
		and not silas_battle.is_active() and kuda_battle.target == f3
		and commands.available_ids() == [SILAS.npc_id],
		"Recalling Silas leaves Kuda attacking a different target")
	_check(bool(sea.call("_try_companion_target", player.position + Vector2(0.0, 90.0)))
		and commands.available_ids() == [SILAS.npc_id, KUDA.npc_id]
		and not silas_battle.is_active() and not kuda_battle.is_active(),
		"Right-clicking empty water recalls all and restores party order")

	# Safety refusal: on_command emits its usual dialogue, not a queue pop.
	f1.health = MULLET.max_health * 0.25
	_check(bool(sea.call("_try_companion_target", f1.position))
		and not silas_battle.is_active()
		and commands.next_available_id() == SILAS.npc_id,
		"Silas refuses low-health prey without consuming his queue slot")
	_check(story.has_event(&"silas_nonlethal_explained")
		and DialogueManager.is_active and DialogueManager.current_npc == SILAS,
		"Silas explains his nonlethal limit only on the first manual refusal")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	# Verify the first automatic retreat teaches the same rule just once.
	# This resets ONLY the lesson flag inside this isolated smoke test.
	story.get("_events").erase(&"silas_nonlethal_explained")
	var speech: SeaSpeechBubble = story.call("_bubble") as SeaSpeechBubble
	story.on_silas_spared_fish(f1)
	_check(speech != null and speech.is_call_shown()
		and story.has_event(&"silas_nonlethal_explained"),
		"First automatic retreat explains why Silas spares a fish")
	if speech != null:
		speech.hide_call()
	story.on_silas_spared_fish(f1)
	_check(speech != null and not speech.is_call_shown(),
		"Later automatic retreats are silent")
	_check(bool(sea.call("_try_companion_target", f1.position))
		and DialogueManager.is_active
		and DialogueManager.current_npc == SILAS
		and commands.next_available_id() == SILAS.npc_id,
		"Manual refusal still opens Silas's dialogue after the automatic warning")
	var reminder_line: DialogueLineData = DialogueManager.get_current_line()
	_check(reminder_line != null and reminder_line.text == "Penni? N-no, not that one...",
		"Repeated deliberate orders retain his existing boundary conversation")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	# An intentional order is different from a silent automatic retreat.
	_check(bool(sea.call("_try_companion_target", f1.position))
		and DialogueManager.is_active
		and commands.next_available_id() == SILAS.npc_id,
		"Another direct order can reopen his conversation without attacking")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	f1.health = MULLET.max_health
	_check(bool(sea.call("_try_companion_target", f1.position)), "Silas can resume issuing orders")

	# Simulate Silas's strike: cannot kill and returns on the 50% cap.
	f1.health = MULLET.max_health * 0.51
	silas_battle.step(2.0, true)
	_check(f1.health >= MULLET.max_health * 0.5 and not silas_battle.is_active(),
		"Silas stops at 50% even when one full hit would be lethal")

	# FIFO on individual returns: Kuda comes back first, Silas second.
	_check(bool(sea.call("_try_companion_target", f2.position))
		and kuda_battle.target == f2,
		"Kuda receives the next order after Silas's automatic return")
	_check(bool(sea.call("_try_companion_target", f2.position))
		and commands.available_ids() == [SILAS.npc_id, KUDA.npc_id],
		"Automatic nonlethal return and manual recall rejoin the available queue")
	_check(bool(sea.call("_try_companion_target", f1.position))
		and not silas_battle.is_active()
		and commands.next_available_id() == SILAS.npc_id,
		"Refusals still preserve queue order")

	# Reset and verify Kuda is intentionally lethal, unlike Silas.
	commands.recall_all()
	commands.send_next(f3, MULLET)
	commands.send_next(f2, MULLET)
	_check(commands.owner_of_target(f3) == SILAS.npc_id
		and commands.owner_of_target(f2) == KUDA.npc_id,
		"Queue tracks independent ownership of two targets")
	f2.health = 1.0
	kuda_battle.step(2.0, true)
	_check(f2.health <= 0.0 and not kuda_battle.is_active()
		and commands.next_available_id() == KUDA.npc_id,
		"Kuda can kill prey and returns to the queue after a knockout")
	_check(silas_battle.is_active() and silas_battle.target == f3,
		"Kuda's knockout does not cancel Silas's separate battle")
	commands.recall_all()

	# Netting one target should not disrupt the other fish's party fight.
	# Restore this fish after the earlier test intentionally weakened it
	# below Silas's safety threshold.
	f1.health = MULLET.max_health
	commands.send_next(f1, MULLET)
	commands.send_next(f3, MULLET)
	_check(silas_battle.target == f1 and kuda_battle.target == f3,
		"Two targets can be assigned again after a full recall")
	sea.call("_on_fish_hit", f1)
	var fishing: DivingCombat = sea.get_node("Combat") as DivingCombat
	_check(fishing.is_active() and fishing.target == f1
		and not silas_battle.is_active() and kuda_battle.target == f3,
		"Netting one fish recalls only its assigned companion during reeling")
	fishing.release()
	_check(kuda_battle.target == f3,
		"Second companion keeps attacking throughout another fish's net combat")
	commands.recall_all()
	_finish(main)


func _finish(main: Control) -> void:
	main.queue_free()
	print("sea_party_commands_test: PASS" if failures == 0 else
		"sea_party_commands_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
