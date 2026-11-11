extends Control

# EXPERIMENT tool (jerry-baitboxtest): exports BaitBox3DView frames as PNGs
# with a transparent background, at native pixel size (one pixel per art pixel).
# Run (not headless; it needs the GPU):
#   godot --path . res://scenes/bait_box_3d_capture.tscn -- --out=<folder> [--fps=3]
# Frames are sampled backwards from the end so the last frame is the finished
# pose; frames where the box is still off-screen are skipped.

var _view: BaitBox3DView


func _ready() -> void:
	var out_dir := OS.get_user_data_dir().path_join("bait_box_frames")
	var fps: float = 3.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--fps="):
			fps = float(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(out_dir)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view = BaitBox3DView.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	await _settle()

	var total: float = _view.drop_duration + _view.open_duration
	var times: Array[float] = []
	var t: float = total
	while t >= 0.0:
		times.push_front(t)
		t -= 1.0 / fps
	var index := 0
	for time in times:
		var drop_t: float = clampf(time / _view.drop_duration, 0.0, 1.0)
		var open_t: float = clampf((time - _view.drop_duration) / _view.open_duration, 0.0, 1.0)
		_view.set_pose(drop_t, open_t)
		await _settle()
		var image := _view.capture_image()
		if image.get_used_rect().size == Vector2i.ZERO:
			continue  # box not on screen yet
		image.save_png(out_dir.path_join("frame_%02d.png" % index))
		print("frame %02d  t=%.2fs  drop=%.2f open=%.2f" % [index, time, drop_t, open_t])
		index += 1
	print("Saved %d frames at %.1f fps to %s" % [index, fps, out_dir])
	get_tree().quit()


func _settle() -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
