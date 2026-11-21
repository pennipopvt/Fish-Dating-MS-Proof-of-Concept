@tool
extends Node2D
class_name SeaSunbeam

# An artist-placeable, non-collidable beam. Move/rotate the root Node2D
# directly in the editor; the child Polygon2D is generated automatically.
# WorldDayNight broadcasts sunlight using the existing game clock.
@export_group("Shape")
@export_range(16.0, 160.0, 1.0, "suffix:px") var beam_width: float = 72.0:
	set(value):
		beam_width = value
		_refresh()
@export_range(40.0, 600.0, 1.0, "suffix:px") var beam_length: float = 280.0:
	set(value):
		beam_length = value
		_refresh()

@export_group("Light")
@export_range(0.0, 1.0, 0.01) var strength: float = 0.26:
	set(value):
		strength = value
		_refresh()
@export var beam_color: Color = Color("#d9f5ff"):
	set(value):
		beam_color = value
		_refresh()
@export var follow_day_night: bool = true:
	set(value):
		follow_day_night = value
		_refresh()

@export_group("Movement")
@export_range(0.0, 12.0, 0.5, "suffix:px") var sway_pixels: float = 2.0:
	set(value):
		sway_pixels = value
		_refresh()
@export_range(0.0, 3.0, 0.1) var sway_speed: float = 0.5:
	set(value):
		sway_speed = value
		_refresh()

@onready var _beam: Polygon2D = $Beam
var _shader_material: ShaderMaterial
var _daylight_energy: float = 1.0
var _daylight_color: Color = Color.WHITE
var _surface_y: float = 140.0


func _ready() -> void:
	add_to_group(&"sea_sunbeams")
	# Each placed beam has independent shader uniforms, even if duplicated.
	_shader_material = (_beam.material as ShaderMaterial).duplicate() as ShaderMaterial
	_beam.material = _shader_material
	_refresh()


func set_environment_light(energy: float, color: Color, surface_y: float) -> void:
	# Called by WorldDayNight. Do not create a second day/night clock.
	if is_equal_approx(_daylight_energy, energy) and _daylight_color == color \
			and is_equal_approx(_surface_y, surface_y):
		return
	_daylight_energy = energy
	_daylight_color = color
	_surface_y = surface_y
	if is_node_ready():
		_apply_material()


func _refresh() -> void:
	if not is_node_ready():
		return
	var half: float = beam_width * 0.75
	_beam.polygon = PackedVector2Array([
		Vector2(-half, 0.0), Vector2(half, 0.0),
		Vector2(half, beam_length), Vector2(-half, beam_length)
	])
	_apply_material()


func _apply_material() -> void:
	if _shader_material == null:
		return
	_shader_material.set_shader_parameter("beam_width", beam_width)
	_shader_material.set_shader_parameter("beam_length", beam_length)
	_shader_material.set_shader_parameter("strength", strength)
	_shader_material.set_shader_parameter("beam_color", beam_color)
	_shader_material.set_shader_parameter("sway_pixels", sway_pixels)
	_shader_material.set_shader_parameter("sway_speed", sway_speed)
	_shader_material.set_shader_parameter(
		"daylight_strength", _daylight_energy if follow_day_night else 1.0)
	_shader_material.set_shader_parameter(
		"daylight_color", _daylight_color if follow_day_night else Color.WHITE)
	_shader_material.set_shader_parameter("surface_world_y", _surface_y)
