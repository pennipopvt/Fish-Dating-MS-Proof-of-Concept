extends Camera2D
## Island camera on the Player. It follows Penni exactly, except on the beach:
## once she is off the stairs and on the sand, the camera holds one height and
## only Penni moves up and down (sand bumps, the end slope).
##
## Only `offset` is written here. Other scripts keep moving `position`
## (fishing locks x, the dive tweens position), so nothing is fought over.

## World x where the stairs end and the beach sand starts.
@export var beach_start_x: float = 682.0
## World x where the beach ends (the sand meets the water).
@export var beach_end_x: float = 976.0

var _player: Player = null
var _locked: bool = false
var _locked_y: float = 0.0


func _ready() -> void:
	_player = get_parent() as Player


func _process(_delta: float) -> void:
	if _player == null:
		return
	var x: float = _player.global_position.x
	var on_beach: bool = x >= beach_start_x and x <= beach_end_x \
		and not _player.swimming and not _player.busy
	if not on_beach:
		_locked = false
		offset.y = 0.0
		return
	if not _locked:
		# Hold the height Penni had when she stepped onto the sand, so the
		# switch from following to holding never jumps.
		_locked = true
		_locked_y = _player.global_position.y
	offset.y = _locked_y - _player.global_position.y
