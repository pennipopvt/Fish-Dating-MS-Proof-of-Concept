class_name FishingRod
extends Node2D

# Visual fishing rod held by the player. Purely cosmetic: it listens to the
# FishingController's state_changed signal and never changes the fishing rules.
#  - whips out when fishing starts, flicks back and forward on every cast
#  - throws the equipped bait on the end of the line along a parabola to where
#    the controller's bobber floats, then sinks it along the underwater line
#  - spins the reel while the player scrolls to reel
#  - keeps a line from the rod tip to the fish while it flies out of the water
#  - turns the player to face the water and holds the idle pose
# The rod sits at the player's hand; Pivot's origin is the grip.

const FishingControllerScript = preload("res://scripts/fishing_controller.gd")
const FishState = FishingControllerScript.Fish_State

@export var fishing_controller_path: NodePath = ^"../FishingController"

@export_group("Animation timing")
@export_range(0.0, 1.0, 0.01) var whip_out_duration: float = 0.15
@export_range(0.05, 1.0, 0.01) var backswing_duration: float = 0.25
@export_range(0.02, 0.5, 0.01) var flick_duration: float = 0.12
@export_range(0.05, 1.0, 0.01) var settle_duration: float = 0.2
@export_range(0.1, 2.0, 0.05) var cast_flight_duration: float = 0.5
## Time for the bait to sink from the bobber to the end of the line.
@export_range(0.0, 5.0, 0.05) var bait_sink_duration: float = 1.5
@export_range(0.0, 0.5, 0.01) var put_away_duration: float = 0.1

@export_group("Poses (degrees, positive = clockwise)")
## How far the rod swings back over the shoulder before the cast.
@export_range(0.0, 150.0, 1.0) var backswing_angle: float = 70.0
## How far past rest the forward flick goes.
@export_range(0.0, 90.0, 1.0) var flick_angle: float = 25.0
## Upward jerk while the fish flies out of the water.
@export_range(0.0, 90.0, 1.0) var catch_jerk_angle: float = 35.0

@export_group("Cast")
## Extra height of the cast's parabola above the straight line to the water.
@export_range(0.0, 150.0, 1.0) var cast_arc_height: float = 30.0
## Slack in the line while the cast flies.
@export_range(0.0, 20.0, 0.5) var line_sag: float = 4.0

@export_group("Bait")
@export_range(0.1, 2.0, 0.05) var bait_scale: float = 0.5

@export_group("Reel")
@export_range(1.0, 60.0, 1.0) var reel_fps: float = 16.0
## How long the reel keeps spinning after one scroll tick.
@export_range(0.05, 1.0, 0.01) var reel_spin_hold: float = 0.15

@onready var pivot: Node2D = $Pivot
@onready var sprite: Sprite2D = $Pivot/Sprite
@onready var tip: Marker2D = $Pivot/Tip
@onready var cast_line: Line2D = $CastLine
@onready var bait: Sprite2D = $Bait

var controller: FishingControllerScript
var fishing_line: Line2D
var player: Player

var _rod_tween: Tween
var _flight_tween: Tween
var _flying: bool = false
var _flight_start: Vector2
var _flight_end: Vector2
var _flight_pos: Vector2
var _flight_t: float = 0.0
var _sink_tween: Tween
var _reel_time_left: float = 0.0
var _reel_frame_time: float = 0.0
var _catch_line_tween: Tween


func _ready() -> void:
	controller = get_node_or_null(fishing_controller_path) as FishingControllerScript
	player = get_parent() as Player
	if controller == null:
		push_warning("FishingRod: no FishingController at %s" % fishing_controller_path)
		set_process(false)
		set_process_input(false)
		return
	fishing_line = controller.fishing_line

	cast_line.top_level = true
	cast_line.clear_points()
	cast_line.width = fishing_line.width
	cast_line.width_curve = fishing_line.width_curve
	bait.top_level = true
	bait.scale = Vector2.ONE * bait_scale
	# Match the draw order of the controller's own line.
	cast_line.z_as_relative = false
	cast_line.z_index = _absolute_z(fishing_line)

	FishingManager.bait_changed.connect(_on_bait_changed)
	_on_bait_changed(FishingManager.equipped_bait)
	# Deferred: the controller sets bite_time, the line and the catch path
	# right AFTER changing state; react once that function has finished.
	controller.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)

	_hide_all()
	_attach_line_to_tip.call_deferred()


# The controller's line starts at a fixed point; move that point to the rod
# tip in its resting pose so the reeling line comes out of the rod.
func _attach_line_to_tip() -> void:
	fishing_line.set_point_position(0, fishing_line.to_local(tip.global_position))


func _process(delta: float) -> void:
	_update_reel(delta)


func _input(event: InputEvent) -> void:
	if controller.current_state == FishState.FISHING and event.is_action_pressed("Reel"):
		_reel_time_left = reel_spin_hold


func _on_state_changed(from: int, to: int) -> void:
	match to:
		FishState.WAITING:
			if from == FishState.NOT:
				_face_water()
			_cast(from == FishState.NOT)
		FishState.FISHING:
			# A bite during the throw: drop the throw and show the real line.
			_end_flight()
			fishing_line.show()
			_hide_bait()
		FishState.CATCHING:
			_hide_bait()
			_play_catch_jerk()
			_start_catch_line()
		FishState.NOT:
			_put_away()


func _cast(whip_out: bool) -> void:
	_end_flight()
	_hide_bait()
	# Hide the controller's line until the cast has landed, and push the
	# bite back by the length of the throw so a fish can't bite mid-air.
	fishing_line.hide()
	var cast_time: float = backswing_duration + flick_duration + cast_flight_duration + bait_sink_duration
	if whip_out:
		cast_time += whip_out_duration
	controller.bite_time += cast_time

	_kill_rod_tween()
	_rod_tween = create_tween()
	if whip_out:
		show()
		pivot.scale = Vector2(0.0, 0.0)
		pivot.rotation = deg_to_rad(-40.0)
		_rod_tween.set_parallel(true)
		_rod_tween.tween_property(pivot, "scale", Vector2.ONE, whip_out_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_rod_tween.tween_property(pivot, "rotation", 0.0, whip_out_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_rod_tween.set_parallel(false)
	_rod_tween.tween_property(pivot, "rotation", deg_to_rad(backswing_angle), backswing_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rod_tween.tween_property(pivot, "rotation", deg_to_rad(-flick_angle), flick_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_rod_tween.tween_callback(_release_cast)
	# Settle via a method so the flying line's start follows the tip.
	_rod_tween.tween_method(_settle_rod, deg_to_rad(-flick_angle), 0.0, settle_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _settle_rod(angle: float) -> void:
	pivot.rotation = angle
	if _flying:
		_draw_line_between(tip.global_position, _flight_pos, line_sag * (1.0 - _flight_t))


func _release_cast() -> void:
	if controller.current_state != FishState.WAITING:
		return
	_flying = true
	_flight_start = tip.global_position
	# Land where the controller's bobber will float.
	_flight_end = fishing_line.to_global(fishing_line.bobber_water_position)
	cast_line.default_color = fishing_line.default_color
	# Draw the first frame now so the line never shows stale points.
	_update_flight(0.0)
	cast_line.show()
	if _flight_tween != null and _flight_tween.is_running():
		_flight_tween.kill()
	_flight_tween = create_tween()
	_flight_tween.tween_method(_update_flight, 0.0, 1.0, cast_flight_duration)
	_flight_tween.tween_callback(_land_cast)


func _update_flight(t: float) -> void:
	# Straight-line travel plus a symmetric bump = a parabola from tip to water.
	var p: Vector2 = _flight_start.lerp(_flight_end, t)
	p.y -= cast_arc_height * 4.0 * t * (1.0 - t)
	_flight_pos = p if t < 1.0 else _flight_end
	_flight_t = t
	# Drawn from the tween itself: Line2D rebuilds on a deferred call, which
	# still lands before this frame renders.
	_draw_line_between(tip.global_position, _flight_pos, line_sag * (1.0 - t))
	_place_bait(_flight_pos)


func _land_cast() -> void:
	_end_flight()
	if controller.current_state == FishState.WAITING:
		# Hang the line nearly straight down from the bobber for the sink.
		fishing_line.set_slack_drop()
		fishing_line.show()
		_sink_bait()


# The bait follows the controller's line from the surface down to its end.
func _sink_bait() -> void:
	var from: Vector2 = _flight_end
	var to: Vector2 = _line_end()
	_place_bait(from)
	_sink_tween = create_tween()
	_sink_tween.tween_method(func(t: float) -> void: _place_bait(from.lerp(to, t)), 0.0, 1.0, bait_sink_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _end_flight() -> void:
	_flying = false
	if _flight_tween != null and _flight_tween.is_running():
		_flight_tween.kill()
	if _catch_line_tween != null and _catch_line_tween.is_running():
		_catch_line_tween.kill()
	if _sink_tween != null and _sink_tween.is_running():
		_sink_tween.kill()
	cast_line.hide()


func _play_catch_jerk() -> void:
	_kill_rod_tween()
	_rod_tween = create_tween()
	_rod_tween.tween_property(pivot, "rotation", deg_to_rad(catch_jerk_angle), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_rod_tween.tween_property(pivot, "rotation", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


# Tweens run in creation order, so this one updates after the controller's
# catch tween has moved the fish, and the line end stays on the fish.
func _start_catch_line() -> void:
	if _catch_line_tween != null and _catch_line_tween.is_running():
		_catch_line_tween.kill()
	cast_line.default_color = fishing_line.calm_line_color
	_update_catch_line(0.0)
	cast_line.show()
	var flight_time: float = controller.catch_flight_duration + controller.catch_peak_hang
	_catch_line_tween = create_tween()
	_catch_line_tween.tween_method(_update_catch_line, 0.0, 1.0, flight_time)
	_catch_line_tween.tween_callback(cast_line.hide)


func _update_catch_line(_t: float) -> void:
	if not controller.catch_fish_visual.visible:
		cast_line.hide()
		return
	_draw_line_between(tip.global_position, controller.catch_fish_visual.global_position, 0.0)


func _put_away() -> void:
	_end_flight()
	_hide_bait()
	_kill_rod_tween()
	_reel_time_left = 0.0
	sprite.frame = 0
	if not visible:
		return
	_rod_tween = create_tween()
	_rod_tween.tween_property(pivot, "scale", Vector2.ZERO, put_away_duration)
	_rod_tween.tween_callback(hide)


func _face_water() -> void:
	# The water is to the left of every dock. Holds idle until a fishing
	# animation exists; Player skips its own animation while busy.
	if player == null:
		return
	player.last_direction = -1.0
	player.animator.play("idle_carry_l" if player.held_item != null else "idle_l")


func _update_reel(delta: float) -> void:
	if _reel_time_left <= 0.0:
		return
	_reel_time_left -= delta
	_reel_frame_time += delta
	var step: float = 1.0 / reel_fps
	while _reel_frame_time >= step:
		_reel_frame_time -= step
		sprite.frame = (sprite.frame + 1) % maxi(sprite.hframes, 1)
	if _reel_time_left <= 0.0:
		_reel_frame_time = 0.0


func _draw_line_between(from: Vector2, to: Vector2, sag: float) -> void:
	cast_line.clear_points()
	const SEGMENTS := 8
	for i in range(SEGMENTS + 1):
		var s: float = float(i) / SEGMENTS
		var p: Vector2 = from.lerp(to, s)
		p.y += sag * sin(PI * s)
		cast_line.add_point(p)


func _place_bait(hang_point: Vector2) -> void:
	if bait.texture == null:
		_hide_bait()
		return
	bait.global_position = hang_point.round()
	# Draw at the hooked fish's layer so the water treats the bait the same way.
	bait.z_as_relative = false
	bait.z_index = _absolute_z(fishing_line.fish)
	bait.show()


func _hide_bait() -> void:
	bait.hide()


func _hide_all() -> void:
	hide()
	_end_flight()
	_hide_bait()
	pivot.rotation = 0.0
	sprite.frame = 0


func _kill_rod_tween() -> void:
	if _rod_tween != null and _rod_tween.is_running():
		_rod_tween.kill()
	pivot.scale = Vector2.ONE


# Where the controller's line ends: the hidden fish's spot underwater.
func _line_end() -> Vector2:
	return fishing_line.to_global(fishing_line.get_point_position(fishing_line.get_point_count() - 1))


func _on_bait_changed(data: BaitData) -> void:
	bait.texture = data.icon if data != null else null


static func _absolute_z(node: CanvasItem) -> int:
	var z: int = 0
	var current: Node = node
	while current is CanvasItem:
		var item := current as CanvasItem
		z += item.z_index
		if not item.z_as_relative:
			break
		current = current.get_parent()
	return z
