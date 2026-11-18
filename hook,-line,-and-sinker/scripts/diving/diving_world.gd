extends Node2D
class_name DivingWorld

# A blank sea in the ORIGINAL World: no duplicate player or combat systems.
signal surface_requested

const SURFACE_REACH: float = 44.0
const SEA_TOP: float = 154.0

@onready var _guide: SeaEditorGuide = $EditorGuide
@onready var _surface_exit: Marker2D = $Points/SurfaceExit

var _world_player: Player
var _camera: Camera2D


func _ready() -> void:
	_world_player = get_parent().get_node_or_null("Player") as Player
	if _world_player != null:
		_camera = _world_player.get_node_or_null("Camera2D") as Camera2D


func enter_from_dock() -> void:
	if _world_player == null:
		push_warning("Sea needs the original World/Player to begin a dive.")
		return
	_set_camera_bounds(true)
	_world_player.set_swimming(true, _sea_bounds())


func _sea_bounds() -> Rect2:
	var size: Vector2 = _guide.map_size
	return Rect2(
		Vector2(16.0, SEA_TOP),
		Vector2(maxf(32.0, size.x - 32.0), maxf(32.0, size.y - SEA_TOP - 16.0))
	)


func _set_camera_bounds(in_sea: bool) -> void:
	if _camera == null:
		return
	if in_sea:
		_camera.limit_left = -160
		_camera.limit_top = -90
		_camera.limit_right = roundi(_guide.map_size.x)
		_camera.limit_bottom = roundi(_guide.map_size.y)
	else:
		_camera.limit_left = -10000000
		_camera.limit_top = -10000000
		_camera.limit_right = 10000000
		_camera.limit_bottom = 10000000


# World/Player's existing CharacterBody2D handles movement and wall collision.
# Return via E/Space while near the editable surface marker.
func _unhandled_input(event: InputEvent) -> void:
	if _world_player == null or not _world_player.swimming:
		return
	if DialogueManager.is_active or GameManager.is_modal_ui_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.keycode == KEY_SPACE:
			if _world_player.global_position.distance_to(_surface_exit.global_position) <= SURFACE_REACH:
				_return_to_surface()
				get_viewport().set_input_as_handled()


func _return_to_surface() -> void:
	if _world_player != null and _world_player.swimming:
		surface_requested.emit()
