extends Camera2D
## Island camera on the Player. X follows Penni exactly; on land the height
## follows lazily so the small bumps in the beach sand don't shake the view.
##
## Only `offset` is written here. Other scripts keep moving `position`
## (fishing locks x, the dive tweens position), so nothing is fought over.

## Height changes smaller than this (px) don't move the camera at all.
@export var vertical_dead_zone: float = 6.0
## How fast the camera catches up once Penni leaves the dead zone (1/s).
@export var vertical_follow_rate: float = 3.0
## Slow drift back to centered inside the dead zone (1/s). Keep it low so
## 1-2px sand bumps stay invisible.
@export var recenter_rate: float = 0.5
## The camera never lags further behind than this (px).
@export var max_vertical_lag: float = 12.0
## A height jump larger than this in one frame is a teleport: snap.
@export var teleport_distance: float = 32.0
## While swimming or in a scripted scene the lag fades out this fast (1/s).
@export var release_rate: float = 10.0

var _player: Player = null
var _anchor_y: float = 0.0


func _ready() -> void:
	_player = get_parent() as Player
	if _player != null:
		_anchor_y = _player.global_position.y


func _process(delta: float) -> void:
	if _player == null:
		return
	var player_y: float = _player.global_position.y
	if _player.swimming or _player.busy:
		# Scripted moves and swimming own the camera: let the lag fade out.
		offset.y = move_toward(offset.y, 0.0, maxf(absf(offset.y), 1.0) * release_rate * delta)
		_anchor_y = player_y + offset.y
		return
	if absf(player_y - _anchor_y) > teleport_distance + max_vertical_lag:
		_anchor_y = player_y
	var target: float = _anchor_y
	if player_y - _anchor_y > vertical_dead_zone:
		target = player_y - vertical_dead_zone
	elif _anchor_y - player_y > vertical_dead_zone:
		target = player_y + vertical_dead_zone
	_anchor_y = lerpf(_anchor_y, target, 1.0 - exp(-vertical_follow_rate * delta))
	# Slowly drift back to centered so the view doesn't stay off by the dead zone.
	_anchor_y = lerpf(_anchor_y, player_y, 1.0 - exp(-recenter_rate * delta))
	_anchor_y = clampf(_anchor_y, player_y - max_vertical_lag, player_y + max_vertical_lag)
	offset.y = _anchor_y - player_y
