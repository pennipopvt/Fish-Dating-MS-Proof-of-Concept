extends Sprite2D
class_name SeaTutorialCue

# One screen-space cue attached to the existing camera. Each texture is a
# row-major sprite sheet of 32x32 cells (a single cell is also supported).
# All cue artwork is assigned in world.tscn, not painted with draw calls.
@export var movement_sprite: Texture2D
@export var cast_sprite: Texture2D
@export var reel_sprite: Texture2D
@export var right_click_sprite: Texture2D
@export_range(1.0, 24.0, 0.5) var animation_fps: float = 8.0
@export var frame_size: Vector2i = Vector2i(32, 32)

var current_action: StringName = &""
var _fade: Tween
var _frame_count: int = 1
var _frame_index: int = 0
var _frame_elapsed: float = 0.0
var _columns: int = 1

func _ready() -> void:
	set_process(false)
	hide()


func _process(delta: float) -> void:
	if _frame_count <= 1 or not visible or texture == null:
		return
	_frame_elapsed += delta
	var step: float = 1.0 / maxf(1.0, animation_fps)
	while _frame_elapsed >= step:
		_frame_elapsed -= step
		_frame_index = (_frame_index + 1) % _frame_count
		_set_frame_region()


func _set_frame_region() -> void:
	if texture == null:
		return
	var width: int = maxi(1, frame_size.x)
	var height: int = maxi(1, frame_size.y)
	var column: int = _frame_index % _columns
	var row: int = _frame_index / _columns
	region_rect = Rect2(column * width, row * height, width, height)


func _set_action_texture(selected: Texture2D) -> void:
	texture = selected
	_frame_index = 0
	_frame_elapsed = 0.0
	_columns = 1
	_frame_count = 1
	region_enabled = false
	if selected != null:
		var width: int = maxi(1, frame_size.x)
		var height: int = maxi(1, frame_size.y)
		_columns = maxi(1, selected.get_width() / width)
		var rows: int = maxi(1, selected.get_height() / height)
		_frame_count = _columns * rows
		region_enabled = true
		_set_frame_region()
	set_process(selected != null and _frame_count > 1)


func show_action(action: StringName) -> bool:
	if action != &"move" and action != &"cast" and action != &"reel" and action != &"command":
		return false
	if action == current_action and is_visible_in_tree():
		return true
	if _fade != null and _fade.is_running():
		_fade.kill()
	current_action = action
	var selected: Texture2D
	match action:
		&"move": selected = movement_sprite
		&"cast": selected = cast_sprite
		&"reel": selected = reel_sprite
		&"command": selected = right_click_sprite
	if selected == null:
		push_warning("Tutorial cue texture missing for action: %s" % action)
		return false
	_set_action_texture(selected)
	modulate.a = 0.0
	show()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.3)
	return is_visible_in_tree()


func hide_action() -> void:
	if _fade != null and _fade.is_running():
		_fade.kill()
	if not visible:
		current_action = &""
		return
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.16)
	_fade.tween_callback(_finish_hide)


func _finish_hide() -> void:
	hide()
	set_process(false)
	current_action = &""
