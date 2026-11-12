extends Node2D

# Visuals follow the existing action-based GameManager clock. No second clock:
# each of the three periods contains three visual steps (one per action).
# The world stays camera-relative, so fishing camera pans do not move the sky.
@export_range(0.0, 4.0, 0.1) var transition_seconds: float = 1.6

const AFTERNOON_START: float = 1.0 / 3.0
const SUNSET_START: float = 5.0 / 9.0
const NIGHT_START: float = 2.0 / 3.0

@onready var _sky: ColorRect = $Player/Camera2D/Sky/SkyGradient
@onready var _stars: ColorRect = $Player/Camera2D/Sky/NightStars
@onready var _sun: Sprite2D = $Player/Camera2D/Sky/Sun
@onready var _sun_glow: ColorRect = $Player/Camera2D/Sky/SunGlow
@onready var _moon: ColorRect = $Player/Camera2D/Sky/Moon
@onready var _moon_glow: ColorRect = $Player/Camera2D/Sky/MoonGlow
@onready var _ambient: CanvasModulate = $DayNightTint
@onready var _water: ColorRect = $Water

var _sky_mat: ShaderMaterial
var _stars_mat: ShaderMaterial
var _sun_glow_mat: ShaderMaterial
var _moon_mat: ShaderMaterial
var _moon_glow_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _transition: Tween
var _target_progress: float = -1.0


func _ready() -> void:
    # Scene shader subresources may be shared by instances; do not animate the
    # source assets or affect other World instances / editor previews.
    _sky_mat = _local_material(_sky)
    _stars_mat = _local_material(_stars)
    _sun_glow_mat = _local_material(_sun_glow)
    _moon_mat = _local_material(_moon)
    _moon_glow_mat = _local_material(_moon_glow)
    _water_mat = _local_material(_water)

    _target_progress = _clock_progress()
    _apply_immediately(_visual_state(_target_progress))

    # actions_changed fires for both action spending and rest/period changes.
    # time_changed is also observed for explicit save loads and future callers;
    # _refresh_target suppresses the duplicate callback on period boundaries.
    GameManager.actions_changed.connect(_on_actions_changed)
    GameManager.time_changed.connect(_on_time_changed)


func _local_material(item: CanvasItem) -> ShaderMaterial:
    var material := (item.material as ShaderMaterial).duplicate() as ShaderMaterial
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
    if transition_seconds <= 0.0:
        _apply_immediately(state)
        return

    # Going to bed at night starts a NEW day: bring the invisible sun straight
    # back to the sunrise position before fading it in. Don't fly it backwards
    # across the entire sky during the night -> morning color transition.
    var day_rollover := previous_target >= NIGHT_START and progress < AFTERNOON_START
    if day_rollover:
        _sun.position = state["sun_position"]
        _sun_glow.position = state["sun_glow_position"]
    # At dawn, let the old moon fade at the western horizon. Reposition it
    # in the east only AFTER it has disappeared, ready for the next night.

    _transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    _transition.tween_property(_sky_mat, "shader_parameter/top_color", state["top"], transition_seconds)
    _transition.tween_property(_sky_mat, "shader_parameter/horizon_color", state["horizon"], transition_seconds)
    _transition.tween_property(_ambient, "color", state["ambient"], transition_seconds)
    _transition.tween_property(_water_mat, "shader_parameter/water_color", state["water"], transition_seconds)
    _transition.tween_property(_water_mat, "shader_parameter/highlight_color", state["water_highlight"], transition_seconds)
    _transition.tween_property(_sun, "position", state["sun_position"], transition_seconds)
    _transition.tween_property(_sun, "modulate", Color(1, 1, 1, state["sun_visible"]), transition_seconds)
    _transition.tween_property(_sun_glow, "position", state["sun_glow_position"], transition_seconds)
    _transition.tween_property(_sun_glow_mat, "shader_parameter/intensity", state["sun_glow"], transition_seconds)
    _transition.tween_property(_stars_mat, "shader_parameter/visibility", state["stars"], transition_seconds)
    if not day_rollover:
        _transition.tween_property(_moon, "position", state["moon_position"], transition_seconds)
        _transition.tween_property(_moon_glow, "position", state["moon_glow_position"], transition_seconds)
    _transition.tween_property(_moon_mat, "shader_parameter/visibility", state["moon_visible"], transition_seconds)
    _transition.tween_property(_moon_glow_mat, "shader_parameter/intensity", state["moon_glow"], transition_seconds)
    if day_rollover:
        _transition.chain().tween_callback(_reset_moon_to.bind(state))


func _reset_moon_to(state: Dictionary) -> void:
    _moon.position = state["moon_position"]
    _moon_glow.position = state["moon_glow_position"]


func _apply_immediately(state: Dictionary) -> void:
    _sky_mat.set_shader_parameter("top_color", state["top"])
    _sky_mat.set_shader_parameter("horizon_color", state["horizon"])
    _ambient.color = state["ambient"]
    _water_mat.set_shader_parameter("water_color", state["water"])
    _water_mat.set_shader_parameter("highlight_color", state["water_highlight"])
    _sun.position = state["sun_position"]
    _sun.modulate = Color(1, 1, 1, state["sun_visible"])
    _sun_glow.position = state["sun_glow_position"]
    _sun_glow_mat.set_shader_parameter("intensity", state["sun_glow"])
    _stars_mat.set_shader_parameter("visibility", state["stars"])
    _moon.position = state["moon_position"]
    _moon_glow.position = state["moon_glow_position"]
    _moon_mat.set_shader_parameter("visibility", state["moon_visible"])
    _moon_glow_mat.set_shader_parameter("intensity", state["moon_glow"])


func _visual_state(progress: float) -> Dictionary:
    # The four color stops line up with morning, afternoon, sunset, and night.
    # This keeps the pixel-art sky/water cohesive while the 2D world darkens.
    var top := _day_color(progress, Color("#8dafe5"), Color("#5484c3"), Color("#433a70"), Color("#0b1734"))
    var horizon := _day_color(progress, Color("#d4d4df"), Color("#e6b39a"), Color("#e8885f"), Color("#1b2c4f"))
    var ambient := _day_color(progress, Color("#eff3ff"), Color("#ffe9cf"), Color("#9c7898"), Color("#394f75"))
    var water := _day_color(progress, Color("#1e517a"), Color("#1b4d72"), Color("#323352"), Color("#0b203e"))
    var water_highlight := _day_color(progress, Color("#bedff5"), Color("#ffe8ce"), Color("#d3a4ac"), Color("#6489b7"))

    var daylight := clampf(progress / NIGHT_START, 0.0, 1.0)
    var sun_position := Vector2(
        lerpf(36.0, 285.0, daylight),
        70.0 - 57.0 * sin(daylight * PI)
    )
    var sun_visible := 1.0 - smoothstep(SUNSET_START, NIGHT_START, progress)

    var night_fraction := clampf((progress - NIGHT_START) / (1.0 - NIGHT_START), 0.0, 1.0)
    # A full moon rises in the east at about sunset, follows the same
    # east-to-west arc as the sun, and sets around sunrise.
    var moon_center := Vector2(
        lerpf(36.0, 285.0, night_fraction),
        70.0 - 57.0 * sin(night_fraction * PI)
    )
    var moon_visible := smoothstep(0.60, NIGHT_START, progress)
    var stars_visible := smoothstep(SUNSET_START, NIGHT_START + 0.02, progress)

    return {
        "top": top,
        "horizon": horizon,
        "ambient": ambient,
        "water": water,
        "water_highlight": water_highlight,
        "sun_position": sun_position,
        # ColorRect.position is its TOP-LEFT corner; Sprite2D.position is
        # its CENTER. Use half the rectangle size so glow tracks sun exactly.
        "sun_glow_position": sun_position - _sun_glow.size * 0.5,
        "sun_visible": sun_visible,
        "sun_glow": 0.65 * sun_visible,
        "moon_position": moon_center - _moon.size * 0.5,
        "moon_glow_position": moon_center - _moon_glow.size * 0.5,
        "moon_visible": moon_visible,
        "moon_glow": 0.20 * moon_visible,
        "stars": stars_visible
    }


func _day_color(progress: float, morning: Color, afternoon: Color, sunset: Color, night: Color) -> Color:
    if progress < AFTERNOON_START:
        return morning.lerp(afternoon, smoothstep(0.0, AFTERNOON_START, progress))
    if progress < SUNSET_START:
        return afternoon.lerp(sunset, smoothstep(AFTERNOON_START, SUNSET_START, progress))
    return sunset.lerp(night, smoothstep(SUNSET_START, NIGHT_START, progress))
