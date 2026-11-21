extends CanvasLayer
class_name SeaDebugPanel

# F7 diagnostics are deliberately outside the game SubViewport. The panel
# and Skip Dialogue button are authored in main.tscn, not recreated in code.
@onready var _panel: Panel = $Panel
@onready var _sea_debug_label: Label = $Panel/Diagnostics

var _main: Control
var _world_player: Player
var _sea: DivingWorld
var _bubble_host: SeaSpeechBubbleHost
var _sea_debug_elapsed: float = 0.0
var _sea_debug_last_transition: String = ""


func _ready() -> void:
	hide()
	($Panel/SkipDialogue as Button).pressed.connect(skip_dialogue)


func configure(main: Control, player: Player, sea: DivingWorld, host: SeaSpeechBubbleHost) -> void:
	_main = main
	_world_player = player
	_sea = sea
	_bubble_host = host


func handle_input(event: InputEvent) -> bool:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	if key.keycode == KEY_F7:
		visible = not visible
		_update_sea_debug()
		print("[SEA DEBUG] F7 diagnostics: %s" % str(visible))
		return true
	if key.keycode == KEY_B and visible:
		_force_test_bubble()
		return true
	return false


func is_pointer_over_panel(event: InputEvent) -> bool:
	if not visible or not event is InputEventMouseButton:
		return false
	return _panel.get_global_rect().has_point((event as InputEventMouseButton).position)


func refresh() -> void:
	_update_sea_debug()


# Read by DevPanel's Sea diagnostics tab; the old F7 overlay stays hidden.
func diagnostics_text() -> String:
	if _main == null:
		return "Sea diagnostics are not configured"
	_update_sea_debug()
	return _sea_debug_label.text


func test_bubble_from_menu() -> void:
	_force_test_bubble()
	hide()


func skip_dialogue() -> void:
	if not DialogueManager.is_active:
		print("[SEA DEBUG] Skip Dialogue: no active conversation")
		return
	var speaker_name: String = DialogueManager.current_npc.display_name \
		if DialogueManager.current_npc != null else "unknown speaker"
	print("[SEA DEBUG] Skipping current conversation with " + speaker_name)
	# Use the existing manager; its conversation_finished signal must
	# reach StoryDirector/Main and release movement locks as usual.
	# Debug skipping deliberately bypasses unchosen dialogue choices.
	DialogueManager.end_conversation()
	_update_sea_debug()

func _process(delta: float) -> void:
	if not bool(_main.get("_underwater")) and (not visible):
		return
	_sea_debug_elapsed += delta
	if _sea_debug_elapsed < 0.25:
		return
	_sea_debug_elapsed = 0.0
	_update_sea_debug()


func _update_sea_debug() -> void:
	var story: SeaStoryDirector = _sea.get_node_or_null("StoryDirector") as SeaStoryDirector
	var silas: Node2D = _sea.get_node_or_null("NPCs/Silas") as Node2D
	var raw_bubble: Node = _main.get_node_or_null("SeaSpeechBubble")
	var ui: SeaSpeechBubble = raw_bubble as SeaSpeechBubble
	var call: Control
	var events: Dictionary = {}
	var speaker: Node
	var display: Node
	if ui != null:
		call = ui.get_node_or_null("Call") as Control
		speaker = ui.get("_speaker") as Node
		display = ui.get("_display") as Node
	if story != null:
		events = story.get("_events") as Dictionary
	var distance: float = _world_player.global_position.distance_to(silas.global_position) if silas != null else INF
	var encounter: SeaEncounterSequence = _sea.get_node_or_null("EncounterSequence") as SeaEncounterSequence
	var proximity_range: float = encounter.silas_help_nearby_range if encounter != null else 108.0
	var near_silas: bool = distance <= proximity_range
	var escaped: bool = encounter.first_fish_escape_finished if encounter != null else false
	var follow_x: float = encounter.help_reveal_x if encounter != null else -INF
	var followed: bool = escaped and _world_player.position.x <= follow_x
	var line_broken: bool = bool(events.get(&"line_broken", false))
	var help_called: bool = bool(events.get(&"help_called", false))
	var bound: bool = story != null and ui != null and story.get("_speech_bubble") == ui
	var ready: bool = ui != null and ui.is_node_ready()
	var call_visible: bool = call != null and call.visible
	var call_on_tree: bool = call != null and call.is_visible_in_tree()
	var visible: bool = ui != null and ui.is_call_shown()
	var rect: Rect2 = call.get_global_rect() if call != null else Rect2()
	var battle: DivingCompanionBattle = _sea.get_node_or_null("NPCs/Silas/CompanionBattle") as DivingCompanionBattle
	var fish: DivingWildFish = battle.target if battle != null and battle.is_active() else null
	var actor: SeaNPC = silas as SeaNPC
	var combat: DivingCombat = _sea.get_node_or_null("Combat") as DivingCombat

	var lines: PackedStringArray = PackedStringArray()
	lines.append("SEA DEBUG | F7 show/hide | B: UI test | Skip Dialogue button below")
	lines.append("Swimming: %s   Main underwater: %s   UI parent: Main" % [
		str(_world_player.swimming), str(bool(_main.get("_underwater")))])
	lines.append("Player: %s   Silas: %s" % [
		str(_world_player.global_position.round()),
		str(silas.global_position.round()) if silas != null else "MISSING"])
	lines.append("Silas distance: %.1f / %.1f   proximity trigger: %s" % [
		distance, proximity_range, str(near_silas)])
	lines.append("Line broke: %s   fish escaped: %s   followed left: %s" % [
		str(line_broken), str(escaped), str(followed)])
	lines.append("Player x: %.1f   follow threshold x: %.1f" % [
		_world_player.position.x, follow_x])
	lines.append("Expected help trigger now: %s   help_called flag: %s" % [
		str(followed or near_silas), str(help_called)])
	lines.append("Help UI pending: %s" % [
		str(story.get("_help_ui_pending")) if story != null else "MISSING"])
	lines.append("Story: %s   UI bound: %s   UI ready: %s" % [
		str(story != null), str(bound), str(ready)])
	lines.append("UI node: %s   source: %s" % [
		raw_bubble.get_class() if raw_bubble != null else "MISSING",
		_bubble_host.source])
	lines.append("Call node visible: %s   in tree: %s   renderer says: %s" % [
		str(call_visible), str(call_on_tree), str(visible)])
	lines.append("Speaker valid: %s   display valid: %s" % [
		str(is_instance_valid(speaker)), str(is_instance_valid(display))])
	lines.append("Call screen rect: %s   viewport size: %s" % [
		str(rect), str(get_viewport().get_visible_rect().size)])
	if ui != null:
		lines.append("Bubble: %s   active=%s" % [
			ui.bubble_debug_state(), str(ui.is_call_active())])
	lines.append("Silas following: %s   NPC refs (player/battle): %s/%s" % [
		str(actor.following) if actor != null else "MISSING",
		str(is_instance_valid(actor.get("_player"))) if actor != null else "false",
		str(is_instance_valid(actor.get("_battle"))) if actor != null else "false"])
	lines.append("Battle: %s   can fight: %s   exhausted: %s" % [
		str(battle.is_active()) if battle != null else "MISSING",
		str(battle.can_fight()) if battle != null else "false",
		str(battle.exhausted) if battle != null else "MISSING"])
	lines.append("Target: %s   fish HP: %.1f/%.1f   Silas HP: %.1f" % [
		String(fish.fish_name) if fish != null else "none",
		fish.health if fish != null else 0.0,
		fish.max_health if fish != null else 0.0,
		battle.health if battle != null else 0.0])
	lines.append("Silas movement: %s" % [
		actor.battle_debug_state() if actor != null else "MISSING"])
	var net: DivingNetProjectile = _sea.get_node_or_null("NetProjectile") as DivingNetProjectile
	lines.append("Net lesson: %s   reels=%d   line tension=%.2f" % [
		str(encounter.reel_mode) if encounter != null else "MISSING",
		encounter.reel_scrolls if encounter != null else 0,
		net.line_tension if net != null else 0.0])
	lines.append("Penni reaction=%s   Silas met/freed=%s/%s" % [
		str(story.has_event(&"penni_fish_reaction")) if story != null else "MISSING",
		str(story.has_silas_flag(&"silas_met")) if story != null else "MISSING",
		str(story.has_silas_flag(&"silas_freed")) if story != null else "MISSING"])
	lines.append("Combat: %s   last command: %s" % [
		str(combat.is_active()) if combat != null else "MISSING",
		str(_sea.get("_combat_debug_status"))])
	lines.append("Dialogue active: %s   modal UI: %s" % [
		str(DialogueManager.is_active), str(GameManager.is_modal_ui_open())])
	if _sea_debug_label != null:
		_sea_debug_label.text = "\n".join(lines)

	# Print only when discrete trigger/UI state changes, not on every frame.
	var transition: String = (
		"swim=%s near=%s escape=%s follow=%s broken=%s help=%s bound=%s shown=%s battle=%s"
		% [str(_world_player.swimming), str(near_silas), str(escaped),
			str(followed), str(line_broken), str(help_called),
			str(bound), str(visible), str(battle.is_active()) if battle != null else "MISSING"]
	)
	if transition != _sea_debug_last_transition:
		_sea_debug_last_transition = transition
		print("[SEA DEBUG] " + transition)


func _force_test_bubble() -> void:
	var ui: SeaSpeechBubble = _main.get_node_or_null("SeaSpeechBubble") as SeaSpeechBubble
	if ui == null:
		ui = _bubble_host.ensure_bubble()
		var story: SeaStoryDirector = _sea.get_node_or_null("StoryDirector") as SeaStoryDirector
		if story != null:
			story.bind_speech_bubble(ui)
	if ui == null:
		push_error("[SEA DEBUG] B test failed: unable to create speech bubble")
		return
	ui.show_call("UI TEST: Help me!", false, 0.0)
	print("[SEA DEBUG] B test: ready=%s shown=%s Call rect=%s" % [
		str(ui.is_node_ready()), str(ui.is_call_shown()),
		str((ui.get_node("Call") as Control).get_global_rect())])
	show()
	_update_sea_debug()
