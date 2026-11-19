extends Control
class_name SeaInputPrompt

# A small animated visual cue, separate from story dialogue.
# Drop in your own key/mouse PNGs in the Inspector whenever they're ready.
@export var movement_sprite: Texture2D
@export var cast_sprite: Texture2D
@export var reel_sprite: Texture2D

@onready var _artwork: Control = $Artwork
@onready var _sprite: TextureRect = $Artwork/Sprite
@onready var _placeholder: Label = $Artwork/Placeholder
@onready var _caption: Label = $Caption

var current_action: StringName = &""
var _t: float = 0.0
var _fade: Tween


func _ready() -> void:
	hide()
	set_process(true)


func show_action(action: StringName) -> void:
	if visible and current_action == action:
		return
	current_action = action
	var art: Texture2D
	match action:
		&"move":
			art = movement_sprite
			_placeholder.text = "  W\nA S D"
			_caption.text = "MOVE"
		&"cast":
			art = cast_sprite
			_placeholder.text = "LMB"
			_caption.text = "CAST NET"
		&"reel":
			art = reel_sprite
			_placeholder.text = "SCROLL"
			_caption.text = "DOWN TO REEL"
		_:
			hide_action()
			return

	_sprite.texture = art
	_sprite.visible = art != null
	_placeholder.visible = art == null
	_t = 0.0
	_artwork.position.y = 9.0
	if _fade != null and _fade.is_running():
		_fade.kill()
	show()
	modulate.a = 0.0
	_fade = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fade.tween_property(self, "modulate:a", 1.0, 0.27)


func hide_action() -> void:
	current_action = &""
	if not visible:
		return
	if _fade != null and _fade.is_running():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.16)
	_fade.tween_callback(hide)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	# The cue subtly bobs and pulses, without distracting from the fish.
	_artwork.position.y = 9.0 + sin(_t * 3.7) * 2.5
