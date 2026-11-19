@tool
extends Node2D
class_name SeaNPC

# An NPC scene references its existing NPCData, which owns dialogue/flags and
# both portraits. Only its world appearance and movement live in this script.
@export var npc: NPCData:
	set(value):
		npc = value
		if is_node_ready():
			_refresh_sprite()
@export_enum("Auto", "Fish", "Human") var form: int = 0:
	set(value):
		form = value
		if is_node_ready():
			_refresh_sprite()
# Match main's physical chase and 140px/s combat approach.
@export_range(40.0, 250.0, 1.0) var combat_swim_speed: float = 140.0
@export_range(8.0, 30.0, 1.0) var combat_attack_range: float = 18.0

# Visual size only. Do not change SeaNPC.scale, interaction range, or
# the separate invisible net/combat target. Set per NPC in the Inspector.
@export_range(12.0, 64.0, 1.0) var fish_sprite_width: float = 20.0:
	set(value):
		fish_sprite_width = value
		if is_node_ready():
			_refresh_sprite()

@export var human_world_sprite: Texture2D:
	set(value):
		human_world_sprite = value
		if is_node_ready():
			_refresh_sprite()

@onready var _sprite: Sprite2D = $Sprite
@onready var _indicator: Label = $InteractIndicator

var following: bool = false
var _player: Player
var _story: SeaStoryDirector
var _battle: DivingCompanionBattle
var _lunge_time: float = 0.0
var _hurt_time: float = 0.0
var _last_swim_state: StringName = &"idle"


func _ready() -> void:
	_refresh_sprite()
	_indicator.hide()
	if Engine.is_editor_hint():
		set_process(false)
		return
	_player = get_node_or_null("../../../Player") as Player
	_story = get_node_or_null("../../StoryDirector") as SeaStoryDirector
	_battle = get_node_or_null("../../CompanionBattle") as DivingCompanionBattle


func _refresh_sprite() -> void:
	if _sprite == null or npc == null:
		return
	var fish_mode: bool = form != 2
	var chosen: Texture2D = npc.underwater_sprite if fish_mode else human_world_sprite
	if chosen == null:
		return
	_sprite.texture = chosen
	_sprite.hframes = 1 if fish_mode else 2
	_sprite.scale = Vector2.ONE * (fish_sprite_width / maxf(float(chosen.get_width() / _sprite.hframes), 1.0)) if fish_mode else Vector2.ONE


func _process(delta: float) -> void:
	if _player == null:
		return
	_indicator.visible = _player.swimming and _story != null and _story.can_talk_to_silas() and position.distance_to(_player.position) < 48.0
	_lunge_time = maxf(0.0, _lunge_time - delta)
	_hurt_time = maxf(0.0, _hurt_time - delta)
	_sprite.modulate = Color(1.0, 0.55, 0.5) if _hurt_time > 0.0 else Color.WHITE
	if not following or not _player.swimming:
		return
	var before: Vector2 = position
	var destination: Vector2
	var speed: float
	if _battle != null and _battle.is_active():
		var fish: DivingWildFish = _battle.target
		var side: Vector2 = (_player.position - fish.position).normalized()
		if side.length_squared() < 0.01:
			side = Vector2.LEFT
		# The same hit lunge as main, now on the actual SeaNPC actor.
		var lunge: float = 7.0 * (_lunge_time / 0.15)
		destination = fish.position + side * (22.0 - lunge)
		speed = combat_swim_speed
		_last_swim_state = &"approach" if position.distance_to(destination) > combat_attack_range else &"engaged"
	else:
		destination = _player.position + Vector2(-24.0 if _player.last_direction >= 0.0 else 24.0, 6.0)
		speed = 114.0 if position.distance_to(destination) > 95.0 else 74.0
		_last_swim_state = &"returning"
	if position.distance_to(destination) > 1.0:
		position = position.move_toward(destination, speed * delta)
	# Preserve the last facing direction when stopped or moving vertically.
	# A boolean assignment every frame used to force Silas facing right.
	var horizontal_motion: float = position.x - before.x
	if horizontal_motion < -0.01:
		_sprite.flip_h = true
	elif horizontal_motion > 0.01:
		_sprite.flip_h = false
	_sprite.rotation = sin(Time.get_ticks_msec() * 0.009) * (0.12 if _battle != null and _battle.is_active() else 0.07)
	queue_redraw()


func can_strike_target() -> bool:
	return following and _battle != null and _battle.is_active() \
		and position.distance_to(_battle.target.position) <= combat_attack_range + 4.0


func on_battle_hit(on_fish: bool) -> void:
	if on_fish:
		_lunge_time = 0.15
	else:
		_hurt_time = 0.12


func battle_debug_state() -> String:
	var distance: float = position.distance_to(_battle.target.position) \
		if _battle != null and _battle.is_active() else -1.0
	return "%s distance=%.1f strike=%s" % [
		String(_last_swim_state), distance, str(can_strike_target())]


func _draw() -> void:
	if Engine.is_editor_hint() or _battle == null or not following:
		return
	if _battle.is_active() or _battle.health < _battle.stats.max_health:
		DivingCompanionBattle.draw_health_bar(self, Vector2(0.0, -17.0), _battle.health_ratio())
