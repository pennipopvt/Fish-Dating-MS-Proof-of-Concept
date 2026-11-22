extends Node2D

# Visuals follow the existing action-based GameManager clock. No second clock:
# each of the three periods contains three visual steps (one per action).
# Sky artwork is viewport-anchored through World/SkyLayer. Only its
# visible height follows the world-space waterline; it never chases a camera.
@export_range(0.0, 4.0, 0.1) var transition_seconds: float = 1.6

# These are the real gameplay colors, not just shader defaults. Editing
# them on World changes both the surface and its opaque backdrop underwater.
@export_group("Water Colors")
@export var water_sunrise_color: Color = Color("#4e7c96")
@export var water_morning_color: Color = Color("#4a88a7")
@export var water_afternoon_color: Color = Color("#4289ac")
@export var water_late_afternoon_color: Color = Color("#3c7c9e")
@export var water_sunset_color: Color = Color("#58718f")
@export var water_night_color: Color = Color("#162c4b")


const AFTERNOON_START: float = 1.0 / 3.0
const SUNSET_START: float = 5.0 / 9.0
const NIGHT_START: float = 2.0 / 3.0
# 320x180 native sky pixels. Bodies travel BELOW the visible frame rather
# than becoming transparent while still up in the sky.
const MOON_RISE_START: float = SUNSET_START
const SKY_LEFT_X: float = 28.0
const SKY_RIGHT_X: float = 292.0
const SUN_BELOW_SCREEN_Y: float = 215.0
const SUN_ARC_HEIGHT: float = 205.0
const MOON_BELOW_SCREEN_Y: float = 240.0
const MOON_ARC_HEIGHT: float = 220.0
# The surface is the upper edge of the existing World/Water ColorRect.
const REFLECTION_AT_SURFACE: float = 0.477
const VIEWPORT_SKY_HEIGHT: float = 180.0

@onready var _sky: ColorRect = $Sky/SkyGradient
@onready var _stars: ColorRect = $Sky/NightStars
@onready var _sun: Sprite2D = $Sky/Sun
@onready var _sun_glow: ColorRect = $Sky/SunGlow
@onready var _moon: ColorRect = $Sky/Moon
@onready var _moon_glow: ColorRect = $Sky/MoonGlow
@onready var _sky_region: Control = $Sky
@onready var _clouds: Node2D = $Sky/Clouds
@onready var _camera: Camera2D = $CameraController/Camera2D
@onready var _ambient: CanvasModulate = $DayNightTint
@onready var _water: ColorRect = $Water
# Sea/Solids is optional now that the sea uses SeaTerrain colliders.
@onready var _sea_solids: TileMapLayer = get_node_or_null("Sea/Solids") as TileMapLayer
@onready var _diver: Player = $Player
@onready var _underwater_tint: ColorRect = get_node_or_null("CameraController/Camera2D/UnderwaterTint") as ColorRect

var _sky_mat: ShaderMaterial
var _stars_mat: ShaderMaterial
var _sun_glow_mat: ShaderMaterial
var _moon_mat: ShaderMaterial
var _moon_glow_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _underwater_background: ColorRect
var _sea_clip_mat: ShaderMaterial
var _tint_mat: ShaderMaterial
var _transition: Tween
var _target_progress: float = -1.0
# Clock progress the sun and moon are currently drawn at. Transitions tween
# this value, so the discs travel along their arcs instead of cutting a
# straight line between two points on them.
var _shown_progress: float = 0.0


func _ready() -> void:
	# The water shader is intentionally transparent while Penni swims.
	# Without a background, that alpha exposes the viewport's near-black
	# clear color. Add one flat backdrop behind the existing sea and sky;
	# it uses the SAME palette and day/night clock as the water surface.
	var underwater_layer := CanvasLayer.new()
	underwater_layer.name = "UnderwaterBackgroundLayer"
	underwater_layer.layer = -2
	add_child(underwater_layer)
	_underwater_background = ColorRect.new()
	_underwater_background.name = "UnderwaterBackground"
	_underwater_background.size = Vector2(320.0, 180.0)
	_underwater_background.color = water_afternoon_color
	_underwater_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater_layer.add_child(_underwater_background)

	# World/Sky remains a normal editable scene node. We move that SAME
	# hierarchy into a viewport-locked background layer at runtime so camera
	# smoothing cannot make the gradient, sun or moon shimmer. Clouds still
	# drift using their existing script; there is no duplicate sky.
	var sky_layer := CanvasLayer.new()
	sky_layer.name = "SkyLayer"
	sky_layer.layer = -1
	add_child(sky_layer)
	_sky_region.reparent(sky_layer, false)
	_sky_region.position = Vector2.ZERO
	_sky_region.size = Vector2(320.0, VIEWPORT_SKY_HEIGHT)
	# Scene shader subresources may be shared by instances; do not animate the
	# source assets or affect other World instances / editor previews.
	_sky_mat = _local_material(_sky)
	_stars_mat = _local_material(_stars)
	_sun_glow_mat = _local_material(_sun_glow)
	_moon_mat = _local_material(_moon)
	_moon_glow_mat = _local_material(_moon_glow)
	_water_mat = _local_material(_water)
	_sea_clip_mat = _local_material(_sea_solids)
	_tint_mat = _local_material(_underwater_tint)

	# A scene that failed to load used to crash at .material and then on
	# every subsequent shader update. Keep normal play available even if a
	# visual-only node is temporarily missing during an editor reload.
	if _sky_mat == null or _stars_mat == null or _sun_glow_mat == null \
			or _moon_mat == null or _moon_glow_mat == null or _water_mat == null:
		push_warning("World day/night materials are incomplete; skipping animated visuals.")
		set_process(false)
		return

	_target_progress = _clock_progress()
	_shown_progress = _target_progress
	_apply_immediately(_visual_state(_target_progress))
	set_process(true)

	# actions_changed fires for both action spending and rest/period changes.
	# time_changed is also observed for explicit save loads and future callers;
	# _refresh_target suppresses the duplicate callback on period boundaries.
	GameManager.actions_changed.connect(_on_actions_changed)
	GameManager.time_changed.connect(_on_time_changed)


func _process(_delta: float) -> void:
	# Camera limits can separate the actual screen center from the
	# Camera2D node's world position. The tint is a child of the world camera,
	# so compensate for that difference to keep its entire 320x180
	# rectangle attached to the visible game screen at sea boundaries.
	var visible_center: Vector2 = _camera.get_screen_center_position()
	if _underwater_tint != null:
		_underwater_tint.position = (
			visible_center - _camera.global_position
			- _underwater_tint.size * 0.5
		)
	# Reflection exists at the surface, but dissolves as the original player
	# swims below it. No second viewport, water clock or duplicate shader.
	var surface_y: float = _water.global_position.y
	var depth: float = maxf(0.0, _diver.global_position.y - surface_y)
	var submerged: float = smoothstep(0.0, 42.0, depth)
	_water_mat.set_shader_parameter(
		"reflection_strength", REFLECTION_AT_SURFACE * (1.0 - submerged)
	)
	var surface_screen_y: float = _water.get_global_transform_with_canvas().origin.y
	# The sky stays absolutely still in viewport pixels while the camera
	# smooths or pans. Only the clip bottom follows the true sea surface.
	_sky_region.size.y = clampf(ceilf(surface_screen_y), 0.0, VIEWPORT_SKY_HEIGHT)
	_water_mat.set_shader_parameter("waterline_y", surface_screen_y)
	_water_mat.set_shader_parameter("viewer_submersion", submerged)
	# The sea's above-surface visual clip and the reflection must use
	# the identical viewport-space waterline. Sea collision is unaffected.
	if _sea_clip_mat != null:
		_sea_clip_mat.set_shader_parameter("surface_screen_y", surface_screen_y)
	if _tint_mat != null:
		_tint_mat.set_shader_parameter("submersion", submerged)
		_tint_mat.set_shader_parameter("surface_y_uv", surface_screen_y / 180.0)
	_update_sunbeams()


# Uses the same shown clock progress that already animates water and sky.
# Each authored ray registers itself; none are required in the main scene.
func _update_sunbeams() -> void:
	var sunlight: float = 1.0 - smoothstep(SUNSET_START, NIGHT_START, _shown_progress)
	var morning_tint := Color("#ffe8bd")
	var afternoon_tint := Color("#d7f4ff")
	var sunset_tint := Color("#ffdab0")
	var light_color: Color = morning_tint.lerp(
		afternoon_tint, smoothstep(0.0, AFTERNOON_START, _shown_progress))
	light_color = light_color.lerp(
		sunset_tint, smoothstep(SUNSET_START, NIGHT_START, _shown_progress))
	for instance in get_tree().get_nodes_in_group(&"sea_sunbeams"):
		if instance.has_method("set_environment_light"):
			instance.set_environment_light(sunlight, light_color, _water.global_position.y)


func _local_material(item: CanvasItem) -> ShaderMaterial:
	if item == null:
		return null
	var source: ShaderMaterial = item.material as ShaderMaterial
	if source == null:
		return null
	var material: ShaderMaterial = source.duplicate() as ShaderMaterial
	item.material = material
	return material


func _on_actions_changed(_remaining: int) -> void:
	_refresh_target()


func _on_time_changed(_day: int, _period: GameManager.Times) -> void:
	_refresh_target()


func _clock_progress() -> float:
	# 0.0 = first morning; 1/3 = first afternoon; 2/3 = first night.
	# Spending actions advances the sun a little within each period.
	var fraction_used := 1.0 - float(GameManager.get_actions_left()) / float(GameManager.ACTIONS_PER_PERIOD)
	return clampf((float(GameManager.get_period()) + fraction_used) / 3.0, 0.0, 1.0)


func _refresh_target() -> void:
	var progress := _clock_progress()
	if is_equal_approx(progress, _target_progress):
		return

	var previous_target := _target_progress
	_target_progress = progress
	if _transition != null and _transition.is_running():
		_transition.kill()

	var state := _visual_state(progress)
	if transition_seconds <= 0.0 or GameManager.is_rest_clock_update():
		# Sleep already covers the world with black; don't animate skipped time.
		_shown_progress = progress
		_apply_immediately(state)
		return

	# Overnight starts a NEW sun cycle. The new sun rises in the east;
	# the previous moon must SET below the western edge before it resets.
	# The sleep fade hides the overnight jump of the new sun.
	var day_rollover := previous_target >= NIGHT_START and progress < AFTERNOON_START
	if day_rollover:
		_sun.position = state["sun_position"]
		_sun_glow.position = state["sun_glow_position"]
		_shown_progress = progress

	_transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_property(_sky_mat, "shader_parameter/top_color", state["top"], transition_seconds)
	_transition.tween_property(_sky_mat, "shader_parameter/horizon_color", state["horizon"], transition_seconds)
	_transition.tween_property(_ambient, "color", state["ambient"], transition_seconds)
	# The clouds now draw on a screen-space canvas and no longer inherit the
	# World CanvasModulate, so apply the SAME clock color here explicitly.
	_transition.tween_property(_clouds, "modulate", state["ambient"], transition_seconds)
	_transition.tween_property(_water_mat, "shader_parameter/water_color", state["water"], transition_seconds)
	_transition.tween_property(_underwater_background, "color", state["water"], transition_seconds)
	_transition.tween_property(_water_mat, "shader_parameter/highlight_color", state["water_highlight"], transition_seconds)
	_transition.tween_method(_show_discs_at.bind(not day_rollover), _shown_progress, progress, transition_seconds)
	_transition.tween_property(_sun_glow_mat, "shader_parameter/intensity", state["sun_glow"], transition_seconds)
	_transition.tween_property(_stars_mat, "shader_parameter/visibility", state["stars"], transition_seconds)
	if day_rollover:
		# Finish the moon's western descent, even if the player went to bed
		# before using every night action; never make it fade out in place.
		var moon_exit := Vector2(SKY_RIGHT_X, MOON_BELOW_SCREEN_Y)
		_transition.tween_property(_moon, "position", moon_exit - _moon.size * 0.5, transition_seconds)
		_transition.tween_property(_moon_glow, "position", moon_exit - _moon_glow.size * 0.5, transition_seconds)
	_transition.tween_property(_moon_glow_mat, "shader_parameter/intensity", state["moon_glow"], transition_seconds)
	if day_rollover:
		# Once offscreen, quietly reset to the eastern below-screen start.
		_transition.chain().tween_callback(_reset_moon_to.bind(state))


# Places the sun (and, unless the moon is doing its overnight exit, the
# moon) where they belong at clock `progress`, i.e. on their arcs.
func _show_discs_at(progress: float, move_moon: bool) -> void:
	_shown_progress = progress
	var state := _visual_state(progress)
	_sun.position = state["sun_position"]
	_sun_glow.position = state["sun_glow_position"]
	if move_moon:
		_moon.position = state["moon_position"]
		_moon_glow.position = state["moon_glow_position"]


func _reset_moon_to(state: Dictionary) -> void:
	_moon.position = state["moon_position"]
	_moon_glow.position = state["moon_glow_position"]


func _apply_immediately(state: Dictionary) -> void:
	_sky_mat.set_shader_parameter("top_color", state["top"])
	_sky_mat.set_shader_parameter("horizon_color", state["horizon"])
	_ambient.color = state["ambient"]
	_clouds.modulate = state["ambient"]
	_water_mat.set_shader_parameter("water_color", state["water"])
	_underwater_background.color = state["water"]
	_water_mat.set_shader_parameter("highlight_color", state["water_highlight"])
	_sun.position = state["sun_position"]
	_sun.modulate = Color.WHITE
	_sun_glow.position = state["sun_glow_position"]
	_sun_glow_mat.set_shader_parameter("intensity", state["sun_glow"])
	_stars_mat.set_shader_parameter("visibility", state["stars"])
	_moon.position = state["moon_position"]
	_moon_glow.position = state["moon_glow_position"]
	_moon_mat.set_shader_parameter("visibility", 1.0)
	_moon_glow_mat.set_shader_parameter("intensity", state["moon_glow"])


func _visual_state(progress: float) -> Dictionary:
	# The clock advances in nine action-sized steps. Dawn stays warm, both
	# afternoon steps remain clear blue, and the orange returns at the last
	# afternoon action before the dark night palette takes over.
	var top := _day_color(progress,
		Color("#466b9a"), Color("#7aafd5"), Color("#5299d4"),
		Color("#4f93ce"), Color("#796d9f"), Color("#0b1734"))
	var horizon := _day_color(progress,
		Color("#ffac78"), Color("#f7d6b1"), Color("#b9e4fa"),
		Color("#b2d9f0"), Color("#ff965d"), Color("#1b2c4f"))
	var ambient := _day_color(progress,
		Color("#ffe0bd"), Color("#fff0dd"), Color("#f2f8ff"),
		Color("#f1f6ff"), Color("#ffd0ab"), Color("#394f75"))
	var water := _day_color(progress,
		water_sunrise_color, water_morning_color, water_afternoon_color,
		water_late_afternoon_color, water_sunset_color, water_night_color)
	var water_highlight := _day_color(progress,
		Color("#f1b98b"), Color("#d9e4e5"), Color("#b9e6fb"),
		Color("#b2dbf1"), Color("#ffd0a2"), Color("#6489b7"))

	# The sun starts low at dawn, climbs high at midday, and physically
	# drops BELOW the 180px screen by the start of night.
	var daylight := clampf(progress / NIGHT_START, 0.0, 1.0)
	var sun_arc := lerpf(0.16, 1.0, daylight)
	var sun_position := Vector2(
		lerpf(SKY_LEFT_X, SKY_RIGHT_X, daylight),
		SUN_BELOW_SCREEN_Y - SUN_ARC_HEIGHT * sin(sun_arc * PI)
	)

	# The moon begins rising as sunset finishes. Its disc is below the
	# viewport during daylight; it rises in the east and sets to the west.
	var night_fraction := clampf((progress - MOON_RISE_START) / (1.0 - MOON_RISE_START), 0.0, 1.0)
	var moon_center := Vector2(
		lerpf(SKY_LEFT_X, SKY_RIGHT_X, night_fraction),
		MOON_BELOW_SCREEN_Y - MOON_ARC_HEIGHT * sin(night_fraction * PI)
	)

	# Ambient glows and stars may soften with twilight, but the actual
	# sun/moon discs stay fully opaque and only disappear by travelling offscreen.
	var sun_glow := 0.65 * (1.0 - smoothstep(SUNSET_START, NIGHT_START, progress))
	var moon_glow := 0.24 * smoothstep(SUNSET_START, NIGHT_START, progress)
	var stars_visible := smoothstep(SUNSET_START, NIGHT_START + 0.02, progress)

	return {
		"top": top,
		"horizon": horizon,
		"ambient": ambient,
		"water": water,
		"water_highlight": water_highlight,
		"sun_position": sun_position,
		# ColorRect.position uses its top-left while Sprite2D uses its center.
		"sun_glow_position": sun_position - _sun_glow.size * 0.5,
		"sun_glow": sun_glow,
		"moon_position": moon_center - _moon.size * 0.5,
		"moon_glow_position": moon_center - _moon_glow.size * 0.5,
		"moon_glow": moon_glow,
		"stars": stars_visible
	}


func _day_color(progress: float, sunrise: Color, morning: Color,
		afternoon: Color, late_afternoon: Color, sunset: Color, night: Color) -> Color:
	# Morning orange -> pale gold -> daytime blue -> late-afternoon blue ->
	# sunset orange -> night. Use separate stops rather than warming ALL
	# afternoon as the old palette did.
	var stops := [0.0, 1.0 / 9.0, AFTERNOON_START, 4.0 / 9.0, SUNSET_START, NIGHT_START]
	var colors := [sunrise, morning, afternoon, late_afternoon, sunset, night]
	for i in range(stops.size() - 1):
		if progress < stops[i + 1]:
			return colors[i].lerp(
				colors[i + 1],
				smoothstep(stops[i], stops[i + 1], progress)
			)
	return night
