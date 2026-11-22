class_name WorldCameraController
extends Node2D

# Owns the one World camera. Follow smoothing is independent of Player
# animation, sprite rotation and the diving motion paths.
@export_range(0.5, 30.0, 0.5) var follow_speed: float = 7.0
@export_range(0.5, 30.0, 0.5) var offset_speed: float = 7.0
@export var land_offset: Vector2 = Vector2(0.0, -22.0)
@export var underwater_offset: Vector2 = Vector2.ZERO

@onready var camera: Camera2D = $Camera2D

var _player: Player
var _following: bool = true
var _wanted_offset: Vector2 = Vector2(0.0, -22.0)
var _pan: Tween


func _ready() -> void:
	_player = get_parent().get_node_or_null("Player") as Player
	_wanted_offset = land_offset
	camera.position = land_offset
	if is_instance_valid(_player):
		global_position = _player.global_position
	set_process(true)


func _process(delta: float) -> void:
	if _following and is_instance_valid(_player):
		var weight: float = 1.0 - exp(-follow_speed * delta)
		global_position = global_position.lerp(_player.global_position, weight)
	var offset_weight: float = 1.0 - exp(-offset_speed * delta)
	camera.position = camera.position.lerp(_wanted_offset, offset_weight)


func set_underwater_mode(enabled: bool) -> void:
	_wanted_offset = underwater_offset if enabled else land_offset


# Immediate relocation for scene changes, debug skips and blackout returns.
func snap_to_player() -> void:
	if not is_instance_valid(_player):
		return
	_stop_pan()
	_following = true
	global_position = _player.global_position
	_wanted_offset = underwater_offset if _player.swimming else land_offset
	camera.position = _wanted_offset
	camera.reset_smoothing()
	camera.force_update_scroll()


# Center on a fixed world location, ignoring Penni until follow resumes.
func snap_to(at: Vector2) -> void:
	_stop_pan()
	_following = false
	global_position = at - camera.position
	camera.reset_smoothing()
	camera.force_update_scroll()


# Only a camera move. StoryDirector is responsible for locking and unlocking
# Penni's controls around a pan, so this class stays presentation-only.
func pan_to(at: Vector2, seconds: float = 0.8) -> void:
	_stop_pan()
	_following = false
	if seconds <= 0.0:
		snap_to(at)
		return
	var tween: Tween = create_tween()
	_pan = tween
	tween.tween_property(self, "global_position", at - _wanted_offset, seconds).set_trans(
		Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if _pan == tween:
		_pan = null


func return_to_player(seconds: float = 0.8) -> void:
	if not is_instance_valid(_player):
		return
	_stop_pan()
	_following = false
	if seconds <= 0.0:
		snap_to_player()
		return
	var tween: Tween = create_tween()
	_pan = tween
	tween.tween_property(self, "global_position", _player.global_position, seconds).set_trans(
		Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	if _pan == tween:
		_pan = null
		_following = true


func set_sea_limits(in_sea: bool, origin: Vector2, extent: Vector2) -> void:
	if in_sea:
		camera.limit_left = roundi(origin.x)
		camera.limit_top = -90
		camera.limit_right = roundi(origin.x + extent.x + 64.0)
		camera.limit_bottom = roundi(extent.y)
	else:
		camera.limit_left = -10000000
		camera.limit_top = -10000000
		camera.limit_right = 10000000
		camera.limit_bottom = 10000000


func _stop_pan() -> void:
	if _pan != null and _pan.is_running():
		_pan.kill()
	_pan = null
