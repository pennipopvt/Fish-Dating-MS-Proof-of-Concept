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
	_sprite.scale = Vector2.ONE * (20.0 / maxf(float(chosen.get_width() / _sprite.hframes), 1.0)) if fish_mode else Vector2.ONE


func _process(delta: float) -> void:
	if _player == null:
		return
	_indicator.visible = _player.swimming and _story != null and _story.can_talk_to_silas() and position.distance_to(_player.position) < 48.0
	if following and _player.swimming:
		var target: Vector2 = _player.position + Vector2(-24.0 if _player.last_direction >= 0.0 else 24.0, 6.0)
		if position.distance_to(target) > 10.0:
			position = position.move_toward(target, 74.0 * delta)
		queue_redraw()


func _draw() -> void:
	if Engine.is_editor_hint() or _battle == null or not following:
		return
	if _battle.is_active() or _battle.health < _battle.stats.max_health:
		DivingCompanionBattle.draw_health_bar(self, Vector2(0.0, -17.0), _battle.health_ratio())
