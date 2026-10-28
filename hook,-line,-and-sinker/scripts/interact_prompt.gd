class_name InteractPrompt
extends Node2D

# Small key bubble that pops up above an Interactable.

const POP_TIME := 0.15

@export var action: StringName = &"Interact"

@onready var _key_label: Label = %KeyLabel

var _shown := false
var _tween: Tween


func _ready() -> void:
	hide()
	scale = Vector2.ZERO


func pop_in() -> void:
	if _shown:
		return

	_shown = true
	_key_label.text = _get_key_text()
	show()
	_animate(Vector2.ONE, Tween.EASE_OUT)


func pop_out() -> void:
	if not _shown:
		return

	_shown = false
	_animate(Vector2.ZERO, Tween.EASE_IN).tween_callback(hide)


func _animate(target: Vector2, ease_type: Tween.EaseType) -> Tween:
	if _tween != null:
		_tween.kill()

	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(ease_type)
	_tween.tween_property(self, "scale", target, POP_TIME)
	return _tween


func _get_key_text() -> String:
	return get_action_key_text(action)


# Read the bound key from the InputMap so UI text follows rebinds.
static func get_action_key_text(action_name: StringName) -> String:
	for event in InputMap.action_get_events(action_name):
		var key := event as InputEventKey

		if key == null:
			continue

		var keycode := key.keycode

		if keycode == KEY_NONE:
			keycode = DisplayServer.keyboard_get_keycode_from_physical(
				key.physical_keycode
			)

		return OS.get_keycode_string(keycode)

	return "?"
