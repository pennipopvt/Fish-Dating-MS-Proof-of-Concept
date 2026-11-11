extends Node

# EXPERIMENT preview for BaitBox3DView (jerry-baitboxtest). Run this scene (F6):
# the game world with the player at the bait box, the bait menu's 50% dim, and
# the 3D box playing its open animation.
#   R  replay    P  switch pixel size 3x / 6x    O  outlines + palette on/off
# Uses a separate save file so previewing never changes the real clock save.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

@export var auto_play_delay: float = 0.6

var _view: BaitBox3DView


func _ready() -> void:
	GameManager.save_path = "user://preview_save.cfg"
	add_child(MAIN_SCENE.instantiate())
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)
	_view = BaitBox3DView.new()
	# Command line: godot ... res://scenes/bait_box_3d_preview.tscn -- --pixel=6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pixel="):
			_view.pixel_scale = int(arg.get_slice("=", 1))
		elif arg == "--no-post":
			_view.use_outline = false
			_view.use_palette = false
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_view)

	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player != null:
		player.global_position.x = 118
		player.set("busy", true)  # keep the player still under the preview
	await get_tree().create_timer(auto_play_delay).timeout
	_view.play_open()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			_view.progress = 0.0
			_view.play_open()
		KEY_P:
			_view.pixel_scale = 6 if _view.pixel_scale == 3 else 3
		KEY_O:
			_view.use_outline = not _view.use_outline
			_view.use_palette = _view.use_outline
