extends Node2D
class_name SeaPartyFollower

# Fish-form movement for members without a specialized combat actor.
@export_range(12.0, 48.0, 1.0) var sprite_width: float = 22.0
@export_range(35.0, 220.0, 1.0) var swim_speed: float = 105.0
var _player: Player
var _index: int
var _sprite: Sprite2D


func setup(npc: NPCData, player: Player, index: int) -> void:
	_player = player
	_index = index
	_sprite = Sprite2D.new()
	_sprite.name = "FishSprite"
	_sprite.z_index = 6
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = npc.underwater_sprite
	if _sprite.texture != null:
		var width: float = npc.sea_visuals.follower_width if npc.sea_visuals != null else sprite_width
		_sprite.scale = Vector2.ONE * (width / maxf(float(_sprite.texture.get_width()), 1.0))
	add_child(_sprite)


func _process(delta: float) -> void:
	if _player == null or not _player.swimming:
		return
	var side: float = -1.0 if _player.last_direction >= 0.0 else 1.0
	var target: Vector2 = _player.global_position + Vector2(
		side * (26.0 + 17.0 * _index), 10.0 + 9.0 * (_index % 2))
	var old_x: float = global_position.x
	global_position = global_position.move_toward(target, swim_speed * delta)
	if _sprite != null:
		if absf(global_position.x - old_x) > 0.01:
			_sprite.flip_h = global_position.x < old_x
		_sprite.rotation = sin(Time.get_ticks_msec() * 0.008 + _index) * 0.06
