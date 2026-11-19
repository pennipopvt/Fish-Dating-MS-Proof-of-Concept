extends Sprite2D
class_name SeaTutorialCue

# One screen-space sprite attached to the existing 320x180 game camera.
# The placeholder is drawn directly on the Sprite2D when no art is assigned.
# Replace these exported textures with your finished sprites any time.
@export var movement_sprite: Texture2D
@export var cast_sprite: Texture2D
@export var reel_sprite: Texture2D

var current_action: StringName = &""
var _fade: Tween

const KEY_LETTERS: Dictionary = {
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"]
}


func _ready() -> void:
	hide()


func show_action(action: StringName) -> bool:
	if action != &"move" and action != &"cast" and action != &"reel":
		return false
	if action == current_action and is_visible_in_tree():
		return true
	if _fade != null and _fade.is_running():
		_fade.kill()
	current_action = action
	match action:
		&"move": texture = movement_sprite
		&"cast": texture = cast_sprite
		&"reel": texture = reel_sprite
	modulate.a = 0.0
	show()
	queue_redraw()
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
	current_action = &""
	queue_redraw()


func _draw() -> void:
	if texture != null:
		return
	match current_action:
		&"move":
			_draw_key(Vector2(-5, -16), "W")
			_draw_key(Vector2(-17, -4), "A")
			_draw_key(Vector2(-5, -4), "S")
			_draw_key(Vector2(7, -4), "D")
		&"cast":
			_draw_mouse(false)
		&"reel":
			_draw_mouse(true)


func _draw_key(at: Vector2, letter: String) -> void:
	draw_rect(Rect2(at, Vector2(11, 11)), Color("#93e5f2"))
	draw_rect(Rect2(at + Vector2.ONE, Vector2(9, 9)), Color("#123b50"))
	var rows: Array = KEY_LETTERS[letter]
	for y in range(rows.size()):
		var row: String = str(rows[y])
		for x in range(row.length()):
			if row.substr(x, 1) == "1":
				draw_rect(Rect2(at + Vector2(3 + x, 2 + y), Vector2.ONE),
					Color("#ffffff"))


func _draw_mouse(scroll: bool) -> void:
	draw_rect(Rect2(-9, -15, 18, 30), Color("#e8fbff"))
	draw_rect(Rect2(-7, -13, 14, 26), Color("#14394d"))
	draw_rect(Rect2(-1, -13, 2, 11), Color("#e8fbff"))
	draw_rect(Rect2(-7, -2, 14, 2), Color("#e8fbff"))
	if scroll:
		draw_rect(Rect2(-2, -10, 4, 7), Color("#91e2f2"))
		draw_rect(Rect2(-1, 3, 2, 7), Color("#91e2f2"))
		draw_rect(Rect2(-4, 8, 8, 2), Color("#91e2f2"))
	else:
		draw_rect(Rect2(-7, -13, 6, 11), Color("#91e2f2"))
