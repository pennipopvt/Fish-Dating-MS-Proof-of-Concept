extends CanvasLayer
class_name WaterRenderDebug

# F8 is a visual-only diagnostic. None of these views change the sea's
# collisions, gameplay, scene hierarchy, or the production water shaders.
# Every temporary change is restored when F8 closes.
const MODE_NAMES: PackedStringArray = PackedStringArray([
	"NORMAL", "NO SEA", "NO LAND", "NO WATER", "SOLID WATER", "NO SEA CLIP"
])

@onready var _readout: Label = $Panel/Readout

var mode: int = 0
var _world: Node2D
var _viewport: SubViewport
var _water: ColorRect
var _sea: Node2D
var _solids: TileMapLayer
var _ground: CanvasItem
var _ground_front: CanvasItem
var _camera: Camera2D
var _player: Player
var _line: Line2D
var _original_water_material: Material
var _original_solids_material: Material
var _original_water_color: Color
var _initial_visibility: Dictionary = {}
var _tile_count: int = 0
var _tiles_above_surface: int = 0
var _last_capture: String = "none"
var _elapsed: float = 0.0


func _ready() -> void:
	hide()
	set_process(false)


func configure(world: Node2D, game_viewport: SubViewport, player: Player) -> void:
	_world = world
	_viewport = game_viewport
	_player = player
	_water = world.get_node_or_null("Water") as ColorRect
	_sea = world.get_node_or_null("Sea") as Node2D
	_ground = world.get_node_or_null("Ground") as CanvasItem
	_ground_front = world.get_node_or_null("GroundFront") as CanvasItem
	_camera = player.get_node_or_null("Camera2D") as Camera2D
	_solids = world.get_node_or_null("Sea/Solids") as TileMapLayer
	if _water == null or _solids == null or _sea == null or _camera == null:
		push_warning("[WATER DEBUG] Missing expected nodes; F8 diagnostics unavailable")
		return
	_original_water_material = _water.material
	_original_solids_material = _solids.material
	_original_water_color = _water.color
	_initial_visibility = {
		"water": _water.visible,
		"sea": _sea.visible,
		"ground": _ground.visible if _ground != null else false,
		"ground_front": _ground_front.visible if _ground_front != null else false
	}
	_tile_count = _solids.get_used_cells().size()
	for cell: Vector2i in _solids.get_used_cells():
		if _solids.to_global(_solids.map_to_local(cell)).y < _water.global_position.y:
			_tiles_above_surface += 1
	_line = Line2D.new()
	_line.name = "WaterDebugSurfaceLine"
	_line.width = 1.0
	_line.default_color = Color(1.0, 0.18, 0.32, 1.0)
	_line.z_as_relative = false
	_line.z_index = 120
	_line.visible = false
	_world.add_child(_line)


func handle_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	if key.keycode == KEY_F8:
		if visible:
			_close()
		else:
			_open()
		return true
	if not visible:
		return false
	if key.keycode >= KEY_1 and key.keycode <= KEY_6:
		_set_mode(key.keycode - KEY_1)
		return true
	if key.keycode == KEY_F9:
		_capture()
		return true
	if key.keycode == KEY_C:
		DisplayServer.clipboard_set(_report())
		print("[WATER DEBUG] Copied diagnostics to clipboard")
		return true
	return false


func _open() -> void:
	if _water == null:
		return
	show()
	set_process(true)
	_line.visible = true
	_set_mode(0)


func _close() -> void:
	if _water != null:
		_restore()
	mode = 0
	if _line != null:
		_line.visible = false
	hide()
	set_process(false)
	print("[WATER DEBUG] F8 closed; all visual overrides restored")


func _set_mode(next_mode: int) -> void:
	if _water == null:
		return
	_restore()
	mode = next_mode
	match mode:
		1:
			_sea.hide()
		2:
			if _ground != null:
				_ground.hide()
			if _ground_front != null:
				_ground_front.hide()
		3:
			_water.hide()
		4:
			# Explicit opaque diagnostic rectangle; no reflection shader.
			_water.material = null
			_water.color = Color(1.0, 0.0, 1.0, 1.0)
		5:
			# Reveal whether the tile clip itself is responsible for leakage.
			_solids.material = null
	_update_line()
	_update_readout()
	print("[WATER DEBUG] Mode %d %s" % [mode + 1, MODE_NAMES[mode]])


func _restore() -> void:
	_water.material = _original_water_material
	_water.color = _original_water_color
	_solids.material = _original_solids_material
	_water.visible = bool(_initial_visibility.get("water", true))
	_sea.visible = bool(_initial_visibility.get("sea", true))
	if _ground != null:
		_ground.visible = bool(_initial_visibility.get("ground", true))
	if _ground_front != null:
		_ground_front.visible = bool(_initial_visibility.get("ground_front", true))


func _process(delta: float) -> void:
	if _water == null:
		return
	_update_line()
	_elapsed += delta
	if _elapsed > 0.25:
		_elapsed = 0.0
		_update_readout()


func _update_line() -> void:
	if _line == null or _camera == null or _viewport == null:
		return
	var half_width: float = float(_viewport.size.x) / maxf(_camera.zoom.x, 0.01) * 0.5
	var center_x: float = _camera.get_screen_center_position().x
	var y: float = _water.global_position.y
	_line.points = PackedVector2Array([
		_world.to_local(Vector2(center_x - half_width, y)),
		_world.to_local(Vector2(center_x + half_width, y))
	])


func _shader_parameter(material: Material, name: String) -> String:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return "NO SHADER"
	return str(shader_material.get_shader_parameter(name))


func _report() -> String:
	if _water == null or _viewport == null:
		return "Water debug is missing scene references"
	var water_screen: Vector2 = _water.get_global_transform_with_canvas().origin
	var water_end: Vector2 = _water.get_global_transform_with_canvas() * _water.size
	var sea_clip: String = "ON" if _solids.material != null else "OFF"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("WATER RENDER DEBUG | F8 close | 1-6 views | F9 save PNG | C copy")
	lines.append("1 Normal  2 No Sea  3 No Land  4 No Water  5 Solid Magenta Water  6 No Sea Clip")
	lines.append("MODE: %d %s | red line = actual World/Water surface" % [mode + 1, MODE_NAMES[mode]])
	lines.append("Water: visible=%s  z=%d  shader=%s" % [
		str(_water.visible), _water.z_index, str(_water.material != null)])
	lines.append("Water world: pos=%s size=%s" % [str(_water.global_position.round()), str(_water.size.round())])
	lines.append("Water screen: left=%.1f right=%.1f top=%.1f  viewport=%s" % [
		water_screen.x, water_end.x, water_screen.y, str(_viewport.size)])
	lines.append("Water shader: waterline_y=%s  submersion=%s  reflection=%s" % [
		_shader_parameter(_original_water_material, "waterline_y"),
		_shader_parameter(_original_water_material, "viewer_submersion"),
		_shader_parameter(_original_water_material, "reflection_strength")])
	lines.append("Sea: visible=%s  Solids visible=%s  z=%d  clip=%s" % [
		str(_sea.visible), str(_solids.visible), _solids.z_index, sea_clip])
	lines.append("Sea clip screen Y=%s  tiles=%d  tile centers ABOVE water=%d" % [
		_shader_parameter(_original_solids_material, "surface_screen_y"), _tile_count, _tiles_above_surface])
	lines.append("Land: Ground=%s (z=%d)  GroundFront=%s (z=%d)" % [
		str(_ground.visible) if _ground != null else "missing",
		_ground.z_index if _ground != null else -1,
		str(_ground_front.visible) if _ground_front != null else "missing",
		_ground_front.z_index if _ground_front != null else -1])
	lines.append("Camera center=%s  Player Y=%.1f  Swimming=%s" % [
		str(_camera.get_screen_center_position().round()),
		_player.global_position.y, str(_player.swimming)])
	lines.append("Waterline mismatch = %.2f px (water shader - sea clip)" % [
		float((_original_water_material as ShaderMaterial).get_shader_parameter("waterline_y"))
		- float((_original_solids_material as ShaderMaterial).get_shader_parameter("surface_screen_y"))
		if _original_water_material is ShaderMaterial and _original_solids_material is ShaderMaterial else 0.0])
	lines.append("F9 last screenshot: " + _last_capture)
	return "\n".join(lines)


func _update_readout() -> void:
	_readout.text = _report()


func _capture() -> void:
	if _viewport == null:
		return
	# Wait for the selected diagnostic mode to finish drawing.
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_warning("[WATER DEBUG] Could not capture SubViewport")
		return
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var filename: String = "water_probe_%s_%s.png" % [MODE_NAMES[mode].to_lower().replace(" ", "_"), stamp]
	var path: String = "user://" + filename
	var error: Error = image.save_png(path)
	if error != OK:
		push_warning("[WATER DEBUG] Screenshot failed: %s" % str(error))
		return
	_last_capture = ProjectSettings.globalize_path(path)
	_update_readout()
	print("[WATER DEBUG] Saved viewport screenshot: " + _last_capture)
