class_name BaitBox3DView
extends Control

# EXPERIMENT (jerry-baitboxtest): a low-poly 3D tackle box, rendered at a low
# resolution and scaled up with nearest filtering so it reads as pixel art.
# Plays a short animation: front view, closed -> latches flip, lid opens, the
# single cantilever tray swings up and back -> camera tilts to a top-down view.
# Built from box/cylinder primitives in code; colors come from tackle_box.png.
# A post-process pass (shaders/pixel_post.gdshader) adds outlines and snaps
# colors to PALETTE. Not connected to the bait menu yet.

signal open_finished
signal close_finished

## Screen pixels per rendered pixel. 3 = the UI grid (640x360), 6 = world pixels.
@export_range(1, 8) var pixel_scale: int = 3:
	set(value):
		pixel_scale = value
		if _container != null:
			_container.stretch_shrink = value
@export var open_duration: float = 2.4
@export var use_outline: bool = true:
	set(value):
		use_outline = value
		if _post != null:
			_post.set_shader_parameter(&"use_outline", value)
@export var use_palette: bool = true:
	set(value):
		use_palette = value
		if _post != null:
			_post.set_shader_parameter(&"use_palette", value)

@export_group("Colors (from tackle_box.png)")
@export var lid_color := Color("37552c")
@export var lid_trim_color := Color("284120")
@export var lid_liner_color := Color("a6a6a6")
@export var body_color := Color("8e8e8e")
@export var body_trim_color := Color("7d7d7d")
@export var body_liner_color := Color("a6a6a6")
@export var body_lip_color := Color("a6a6a6")
@export var metal_color := Color("525551")
@export var tray_color := Color("76aa62")
@export var tray_inner_color := Color("5e8a4c")
@export var rust_color := Color("c66141")
@export var rust_light_color := Color("d7785a")
@export var scuff_color := Color("cecece")

# Palette the post-process snaps to: tackle_box.png's 10 colors, plus an
# outline ink, two in-between shades (tray shadow, deep metal) and a
# highlight green so the lit tray doesn't snap to grey.
const PALETTE: Array[String] = [
	"1c2318",
	"284120", "37552c", "5e8a4c", "76aa62", "9cc982",
	"3e413c", "525551", "7d7d7d", "8e8e8e", "a6a6a6", "cecece",
	"c66141", "d7785a",
]
const POST_SHADER: Shader = preload("res://shaders/pixel_post.gdshader")

# Dimensions in meters-ish. X = width, Y = up, Z = toward the front.
const W := 3.2          # box width
const DB := 1.6         # base depth
const HB := 1.0         # base height
const HL := 0.45        # lid height
const T := 0.08         # wall thickness
const BEVEL := 0.05     # corner bevel on outer shapes
const WT := 3.0         # tray width
const DT := 1.3         # tray depth (front-back; up-down in the top view)
const HT := 0.3         # tray height
const DIVIDER := 0.05
const ARM_LENGTH := 0.5
const ARM_SPACING := 0.38
const LATCH_X := 1.0
const HINGE_X := 0.95
const LID_OPEN_DEG := 180.0
const TRAY_OPEN_DEG := 120.0
const LATCH_OPEN_DEG := 150.0

# Camera framing: front (closed) and top-down (open).
const FRONT_PITCH_DEG := -10.0
const FRONT_TARGET := Vector3(0, 0.75, 0)
const FRONT_SIZE := 2.5
const TOP_PITCH_DEG := -90.0
const TOP_TARGET := Vector3(0, HB, -0.8)
const TOP_SIZE := 3.7
const CAMERA_DISTANCE := 10.0

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_apply_progress()

var _container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _post: ShaderMaterial
var _noise: NoiseTexture2D
var _lid_hinge: Node3D
var _latches: Array[Node3D] = []
var _tray: Node3D
var _arms: Array[Node3D] = []
var _arm_pivots: Array[Vector3] = []  # base-side pivot of each arm
var _tray_offset := Vector3.ZERO      # from the arm tips' midpoint to the tray origin
var _tween: Tween


func _ready() -> void:
	_build_noise()
	_build_viewport()
	_build_lights()
	_build_base()
	_build_lid()
	_build_tray_and_arms()
	_apply_progress()


func play_open() -> void:
	_play_to(1.0, open_finished)


func play_close() -> void:
	_play_to(0.0, close_finished)


func _play_to(target: float, done: Signal) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "progress", target, open_duration * absf(target - progress))
	_tween.tween_callback(done.emit)


# ---- Animation -----------------------------------------------------------

func _apply_progress() -> void:
	if _camera == null:
		return
	var latch_t: float = smoothstep(0.0, 0.12, progress)
	var lid_t: float = smoothstep(0.12, 0.6, progress)
	var tray_t: float = smoothstep(0.35, 0.8, progress)
	var cam_t: float = smoothstep(0.12, 0.95, progress)  # starts with the lid

	for latch in _latches:
		latch.rotation.x = deg_to_rad(LATCH_OPEN_DEG * latch_t)
	_lid_hinge.rotation.x = -deg_to_rad(LID_OPEN_DEG * lid_t)
	_set_tray_angle(deg_to_rad(TRAY_OPEN_DEG * tray_t))

	var pitch: float = deg_to_rad(lerpf(FRONT_PITCH_DEG, TOP_PITCH_DEG, cam_t))
	var target: Vector3 = FRONT_TARGET.lerp(TOP_TARGET, cam_t)
	_camera.basis = Basis.from_euler(Vector3(pitch, 0, 0))
	_camera.position = target + _camera.basis.z * CAMERA_DISTANCE
	_camera.size = lerpf(FRONT_SIZE, TOP_SIZE, cam_t)


# Parallelogram linkage: every arm turns by the same angle, so the tray only
# translates and stays level. 0 = arms point forward (tray inside the box).
func _set_tray_angle(angle: float) -> void:
	var direction := Vector3(0, sin(angle), cos(angle))
	var tip_sum := Vector3.ZERO
	for i in _arms.size():
		var pivot: Vector3 = _arm_pivots[i]
		var tip: Vector3 = pivot + direction * ARM_LENGTH
		_arms[i].position = (pivot + tip) * 0.5
		_arms[i].rotation.x = -angle
		tip_sum += tip
	var tip_mid: Vector3 = tip_sum / float(_arms.size())
	_tray.position = Vector3(0, tip_mid.y, tip_mid.z) + _tray_offset


# ---- Scene setup ---------------------------------------------------------

func _build_noise() -> void:
	# Subtle surface variation; after palette snapping it reads as light dither.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.09
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.94, 0.94, 0.94))
	ramp.set_color(1, Color(1, 1, 1))
	_noise = NoiseTexture2D.new()
	_noise.width = 64
	_noise.height = 64
	_noise.seamless = true
	_noise.noise = noise
	_noise.color_ramp = ramp


func _build_viewport() -> void:
	_container = SubViewportContainer.new()
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.stretch_shrink = pixel_scale
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	_container.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.05
	_camera.far = 50.0
	_viewport.add_child(_camera)

	# Full-screen post-process quad (outlines + palette).
	_post = ShaderMaterial.new()
	_post.shader = POST_SHADER
	var palette := PackedVector3Array()
	for hex in PALETTE:
		var c := Color(hex)
		palette.append(Vector3(c.r, c.g, c.b))
	_post.set_shader_parameter(&"palette", palette)
	_post.set_shader_parameter(&"palette_size", palette.size())
	var ink := Color(PALETTE[0])
	_post.set_shader_parameter(&"outline_color", Vector3(ink.r, ink.g, ink.b))
	_post.set_shader_parameter(&"use_outline", use_outline)
	_post.set_shader_parameter(&"use_palette", use_palette)
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var post := MeshInstance3D.new()
	post.mesh = quad
	post.material_override = _post
	post.extra_cull_margin = 16384.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post.position = Vector3(0, 0, -1)
	_camera.add_child(post)


func _build_lights() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8c8d8")
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	# Key light: warm, from the upper front-left, with shadows.
	var key := DirectionalLight3D.new()
	key.light_color = Color("fff1dc")
	key.light_energy = 1.25
	key.shadow_enabled = true
	key.shadow_opacity = 0.65
	key.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-30), 0)
	_viewport.add_child(key)

	# Cool rim light from behind-right, no shadows.
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("9fc4ff")
	rim.light_energy = 0.35
	rim.rotation = Vector3(deg_to_rad(-30), deg_to_rad(150), 0)
	_viewport.add_child(rim)


func _build_base() -> void:
	var base := Node3D.new()
	base.name = "Base"
	_viewport.add_child(base)
	var body := _material(body_color)
	var trim := _material(body_trim_color)
	var metal := _material(metal_color)
	_box(base, Vector3(W - 2.0 * BEVEL, T, DB - 2.0 * BEVEL), Vector3(0, T * 0.5, 0), trim)  # floor
	# Walls stop short of the corners, leaving a notch that reads as a bevel.
	for side in [-1.0, 1.0]:
		_box(base, Vector3(W - 2.0 * BEVEL, HB, T), Vector3(0, HB * 0.5, side * (DB * 0.5 - T * 0.5)), body)
		_box(base, Vector3(T, HB, DB - 2.0 * BEVEL), Vector3(side * (W * 0.5 - T * 0.5), HB * 0.5, 0), body)
	# Inside floor liner; sits above the solid foot band (top at 0.12).
	_box(base, Vector3(W - 2.0 * T, 0.02, DB - 2.0 * T), Vector3(0, 0.135, 0), _material(body_liner_color, false))
	# Foot band and a lip around the top edge.
	_bevel_box(base, Vector3(W + 0.02, 0.12, DB + 0.02), Vector3(0, 0.06, 0), trim)
	var lip := _material(body_lip_color, false)
	for side in [-1.0, 1.0]:
		_bevel_box(base, Vector3(W + 0.04, 0.08, 0.06), Vector3(0, HB - 0.05, side * (DB * 0.5 + 0.01)), lip, 0.02)
		_bevel_box(base, Vector3(0.06, 0.08, DB + 0.04), Vector3(side * (W * 0.5 + 0.01), HB - 0.05, 0), lip, 0.02)
	# Front latches: a plate on the base and a clasp that flips forward.
	for side in [-1.0, 1.0]:
		_bevel_box(base, Vector3(0.26, 0.2, 0.04), Vector3(side * LATCH_X, HB - 0.22, DB * 0.5 + 0.03), metal, 0.02)
		var latch := Node3D.new()
		latch.position = Vector3(side * LATCH_X, HB - 0.2, DB * 0.5 + 0.06)
		base.add_child(latch)
		_bevel_box(latch, Vector3(0.18, 0.3, 0.03), Vector3(0, 0.15, 0.0), metal, 0.015)
		_latches.append(latch)
	# Hinge barrels and leaves at the back.
	for side in [-1.0, 1.0]:
		_cylinder_x(base, 0.055, 0.36, Vector3(side * HINGE_X, HB, -DB * 0.5 - 0.03), metal)
		_box(base, Vector3(0.36, 0.14, 0.02), Vector3(side * HINGE_X, HB - 0.08, -DB * 0.5 - 0.01), metal)
	# Wear: rust where the sprite has its orange marks, and a few scuffs.
	var rust := _material(rust_color)
	var rust_light := _material(rust_light_color)
	_box(base, Vector3(0.16, 0.2, 0.012), Vector3(-LATCH_X - 0.04, HB - 0.42, DB * 0.5 + 0.006), rust)
	_box(base, Vector3(0.08, 0.1, 0.014), Vector3(-LATCH_X + 0.02, HB - 0.38, DB * 0.5 + 0.007), rust_light)
	_box(base, Vector3(0.06, 0.16, 0.012), Vector3(-LATCH_X - 0.1, HB - 0.58, DB * 0.5 + 0.006), rust)
	_box(base, Vector3(0.1, 0.06, 0.012), Vector3(1.3, 0.3, DB * 0.5 + 0.006), rust)
	var scuff := _material(scuff_color)
	_box(base, Vector3(0.5, 0.025, 0.012), Vector3(0.35, 0.2, DB * 0.5 + 0.006), scuff)
	_box(base, Vector3(0.012, 0.25, 0.2), Vector3(W * 0.5 + 0.006, 0.45, 0.4), scuff)


func _build_lid() -> void:
	# Hinged at the back top edge of the base. Lid geometry is in hinge space:
	# z from 0 (back) to DB (front), y from 0 to HL.
	_lid_hinge = Node3D.new()
	_lid_hinge.name = "LidHinge"
	_lid_hinge.position = Vector3(0, HB, -DB * 0.5)
	_viewport.add_child(_lid_hinge)
	var lid := _material(lid_color)
	var lid_trim := _material(lid_trim_color)
	var metal := _material(metal_color)
	_bevel_box(_lid_hinge, Vector3(W, T + 0.04, DB), Vector3(0, HL - (T + 0.04) * 0.5, DB * 0.5), lid)  # top
	for side in [-1.0, 1.0]:
		var z: float = DB - T * 0.5 if side > 0.0 else T * 0.5
		_box(_lid_hinge, Vector3(W - 2.0 * BEVEL, HL, T), Vector3(0, HL * 0.5, z), lid_trim)
		_box(_lid_hinge, Vector3(T, HL, DB - 2.0 * BEVEL), Vector3(side * (W * 0.5 - T * 0.5), HL * 0.5, DB * 0.5), lid_trim)
	# Raised panel with ribs, a light liner inside (faces up once open).
	_bevel_box(_lid_hinge, Vector3(W - 0.4, 0.06, DB - 0.4), Vector3(0, HL + 0.03, DB * 0.5), lid, 0.03)
	for x in [-1.2, -0.95, 0.95, 1.2]:
		_bevel_box(_lid_hinge, Vector3(0.1, 0.05, DB - 0.55), Vector3(x, HL + 0.085, DB * 0.5), lid_trim, 0.02)
	_box(_lid_hinge, Vector3(W - 2.0 * T, 0.02, DB - 2.0 * T), Vector3(0, HL - T - 0.05, DB * 0.5), _material(lid_liner_color, false))
	# Molded handle: posts, bar and a round grip.
	for side in [-1.0, 1.0]:
		_bevel_box(_lid_hinge, Vector3(0.12, 0.24, 0.14), Vector3(side * 0.5, HL + 0.15, DB * 0.5), metal, 0.03)
	_bevel_box(_lid_hinge, Vector3(1.12, 0.08, 0.12), Vector3(0, HL + 0.27, DB * 0.5), metal, 0.03)
	_cylinder_x(_lid_hinge, 0.075, 0.6, Vector3(0, HL + 0.27, DB * 0.5), lid_trim)
	# Catches the latches hook onto, and the lid's hinge leaves.
	for side in [-1.0, 1.0]:
		_box(_lid_hinge, Vector3(0.22, 0.06, 0.04), Vector3(side * LATCH_X, 0.12, DB + 0.02), metal)
		_box(_lid_hinge, Vector3(0.36, 0.14, 0.02), Vector3(side * HINGE_X, 0.08, -0.01), metal)
	# Wear on the lid.
	_box(_lid_hinge, Vector3(0.12, 0.1, 0.012), Vector3(-1.35, HL - 0.15, DB + 0.006), _material(rust_color))
	_box(_lid_hinge, Vector3(0.3, 0.012, 0.03), Vector3(1.1, HL + 0.066, DB - 0.3), _material(scuff_color))


func _build_tray_and_arms() -> void:
	_tray = Node3D.new()
	_tray.name = "Tray"
	_viewport.add_child(_tray)
	var tray := _material(tray_color, false)
	var inner := _material(tray_inner_color, false)
	# Tray origin = center of its bottom.
	_box(_tray, Vector3(WT, T, DT), Vector3(0, T * 0.5, 0), inner)
	for side in [-1.0, 1.0]:
		_box(_tray, Vector3(WT, HT, T), Vector3(0, HT * 0.5, side * (DT * 0.5 - T * 0.5)), tray)
		_box(_tray, Vector3(T, HT, DT - 2.0 * T), Vector3(side * (WT * 0.5 - T * 0.5), HT * 0.5, 0), tray)
		# Thick rim that sticks out a little.
		_bevel_box(_tray, Vector3(WT + 0.06, 0.08, T + 0.06), Vector3(0, HT - 0.04, side * (DT * 0.5 - T * 0.5)), tray, 0.02)
		_bevel_box(_tray, Vector3(T + 0.06, 0.08, DT + 0.06), Vector3(side * (WT * 0.5 - T * 0.5), HT - 0.04, 0), tray, 0.02)
	# Slanted fillets where the floor meets the front and back walls, so the
	# compartment bottoms read as rounded.
	var inner_width: float = WT - 2.0 * T
	var inner_depth: float = DT - 2.0 * T
	for side in [-1.0, 1.0]:
		var fillet := _box(_tray, Vector3(inner_width, 0.09, 0.09), Vector3(0, T, side * (inner_depth * 0.5)), inner)
		fillet.rotation.x = deg_to_rad(45)
	# 6 compartments: 5 thin tall ones, then a square one on the right.
	var square: float = inner_depth
	var thin: float = (inner_width - square - 5.0 * DIVIDER) / 5.0
	var x: float = -inner_width * 0.5
	for i in 5:
		x += thin
		_box(_tray, Vector3(DIVIDER, HT - 0.03, inner_depth), Vector3(x + DIVIDER * 0.5, (HT - 0.03) * 0.5, 0), tray)
		x += DIVIDER

	# Two parallel arms per side, pivoting on the outside of the base's back.
	var metal := _material(metal_color)
	var pin := _material(metal_color.darkened(0.2))
	var arm_x: float = W * 0.5 + 0.06
	var back_pivot := Vector3(0, HB - 0.08, -DB * 0.5 + 0.12)
	for side in [-1.0, 1.0]:
		for j in 2:
			var pivot := back_pivot + Vector3(side * arm_x, 0, j * ARM_SPACING)
			_arm_pivots.append(pivot)
			var arm := Node3D.new()
			_viewport.add_child(arm)
			_bevel_box(arm, Vector3(0.06, 0.08, ARM_LENGTH + 0.1), Vector3.ZERO, metal, 0.02)
			_arms.append(arm)
			_cylinder_x(_viewport, 0.04, 0.12, pivot + Vector3(side * 0.02, 0, 0), pin)  # pin at the base end

	# Closed: tray sits in the base, top flush with the rim.
	var closed_tray := Vector3(0, HB - HT, -DB * 0.5 + T + DT * 0.5)
	var closed_tip_mid := back_pivot + Vector3(0, 0, ARM_SPACING * 0.5 + ARM_LENGTH)
	_tray_offset = closed_tray - Vector3(0, closed_tip_mid.y, closed_tip_mid.z)
	# Brackets from the tray sides out to the arm tips, with pins (fixed in tray space).
	for side in [-1.0, 1.0]:
		for j in 2:
			var tip := back_pivot + Vector3(0, 0, j * ARM_SPACING + ARM_LENGTH)
			var local: Vector3 = Vector3(0, tip.y, tip.z) - closed_tray
			var width: float = arm_x - WT * 0.5
			_box(_tray, Vector3(width, 0.07, 0.1), Vector3(side * (WT * 0.5 + width * 0.5), local.y, local.z), metal)
			_cylinder_x(_tray, 0.04, 0.12, Vector3(side * (arm_x + 0.02), local.y, local.z), pin)


# ---- Helpers -------------------------------------------------------------

# noisy = subtle surface noise (exterior wear). Off for big flat insides,
# where palette snapping would turn it into blotches.
func _material(color: Color, noisy: bool = true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if noisy:
		material.albedo_texture = _noise
		material.uv1_triplanar = true
		material.uv1_scale = Vector3(1.5, 1.5, 1.5)
	material.roughness = 1.0
	# Banded (toon) shading reads better as pixel art than smooth gradients.
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


func _box(parent: Node, size: Vector3, position_: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_
	parent.add_child(instance)
	return instance


# Three overlapping boxes, each shrunk on two axes: a cheap chamfer that reads
# as a rounded edge at pixel scale.
func _bevel_box(parent: Node, size: Vector3, position_: Vector3, material: Material, bevel: float = BEVEL) -> Node3D:
	var node := Node3D.new()
	node.position = position_
	parent.add_child(node)
	if bevel <= 0.0 or minf(size.x, minf(size.y, size.z)) <= 2.0 * bevel:
		_box(node, size, Vector3.ZERO, material)
		return node
	var b2: float = 2.0 * bevel
	_box(node, Vector3(size.x, size.y - b2, size.z - b2), Vector3.ZERO, material)
	_box(node, Vector3(size.x - b2, size.y, size.z - b2), Vector3.ZERO, material)
	_box(node, Vector3(size.x - b2, size.y - b2, size.z), Vector3.ZERO, material)
	return node


func _cylinder_x(parent: Node, radius: float, length: float, position_: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 12
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position_
	instance.rotation.z = PI * 0.5
	parent.add_child(instance)
	return instance
