extends Node2D

# Decorative rising bubbles in the dive. Purely visual; nothing collides with
# them. Four sources, all only around the camera view:
#   - Vents: short streams from random spots on the sea floor and rocks
#     (found with a downward ray against the terrain collision, so background
#     walls without collision never vent).
#   - Drift: loose single bubbles rising across the whole view.
#   - Breath: small clusters from Penni's head while she swims (more often
#     while she's moving).
#   - Splash: a burst around Penni when she goes under the surface.
# Big bubbles play their pop animation at the surface, and some pop early
# mid-water. Small and mid bubbles fade out at the surface.
# Everything is drawn by this one node (_draw), so many bubbles stay cheap.

enum Kind { SMALL, MID, BIG }

@export_group("Art")
@export var small_texture: Texture2D = preload("res://sprites/environment/oceanJerry/bubbleSmall.png")
@export var mid_texture: Texture2D = preload("res://sprites/environment/oceanJerry/bubbleMid.png")
## Frame 0 is the bubble, frames 1+ are the pop, all the same width.
@export var big_sheet: Texture2D = preload("res://sprites/environment/oceanJerry/bubbleBig-Sheet.png")
@export var big_frames: int = 4
@export var pop_frame_time: float = 0.08
@export_range(0.0, 1.0) var opacity: float = 0.75

@export_group("Motion")
## Rise speed range in pixels per second, per size (small, mid, big).
@export var small_rise: Vector2 = Vector2(9.0, 14.0)
@export var mid_rise: Vector2 = Vector2(12.0, 18.0)
@export var big_rise: Vector2 = Vector2(16.0, 24.0)
## Side-to-side wobble amplitude in pixels.
@export var wobble: Vector2 = Vector2(0.6, 1.8)
## Chance that a big bubble pops early somewhere mid-water.
@export_range(0.0, 1.0) var early_pop_chance: float = 0.3
## Small/mid bubbles fade over this many pixels under the surface.
@export var surface_fade: float = 6.0

@export_group("Vents (floor and rocks)")
## Seconds between new vent streams somewhere in view.
@export var vent_interval: Vector2 = Vector2(1.2, 2.8)
@export var vent_stream_size: Vector2i = Vector2i(3, 7)
@export var vent_bubble_gap: float = 0.18

@export_group("Drift")
@export var drift_interval: Vector2 = Vector2(0.7, 1.8)

@export_group("Breath")
## Seconds between breath clusters while still, and while swimming.
@export var breath_interval_idle: Vector2 = Vector2(5.0, 8.0)
@export var breath_interval_moving: Vector2 = Vector2(2.2, 3.6)
@export var breath_cluster: Vector2i = Vector2i(2, 4)
## Head position relative to Penni's origin (feet), facing right.
@export var head_offset: Vector2 = Vector2(3.0, -26.0)

@export_group("Splash")
@export var splash_count: Vector2i = Vector2i(7, 10)
@export var splash_spread: Vector2 = Vector2(14.0, 10.0)

## Visible water surface y in the parent's space, used only when the World's
## `Water` node isn't found (same rule as the backdrop).
@export var surface_y: float = 140.0
@export var max_bubbles: int = 160
@export var random_seed: int = 9001

var _rng := RandomNumberGenerator.new()
var _bubbles: Array[Dictionary] = []
var _streams: Array[Dictionary] = []
var _vent_timer: float = 0.0
var _drift_timer: float = 0.0
var _breath_timer: float = 0.0
var _player: Node2D
var _player_was_under: bool = false
var _view: Rect2 = Rect2()
var _surface: float = 140.0


func _ready() -> void:
	_rng.seed = random_seed
	_vent_timer = _rng.randf_range(vent_interval.x, vent_interval.y)
	_drift_timer = _rng.randf_range(drift_interval.x, drift_interval.y)
	_breath_timer = _rng.randf_range(breath_interval_idle.x, breath_interval_idle.y)


func _physics_process(delta: float) -> void:
	# Vent spots need the physics space for the floor ray.
	if not _update_view():
		return
	_vent_timer -= delta
	if _vent_timer <= 0.0:
		_vent_timer = _rng.randf_range(vent_interval.x, vent_interval.y)
		_start_vent_stream()


func _process(delta: float) -> void:
	var in_view: bool = _update_view()
	_update_player(delta, in_view)
	if in_view:
		_drift_timer -= delta
		if _drift_timer <= 0.0:
			_drift_timer = _rng.randf_range(drift_interval.x, drift_interval.y)
			var x: float = _rng.randf_range(_view.position.x, _view.end.x)
			var y: float = _rng.randf_range(maxf(_view.position.y, _surface + 20.0), _view.end.y + 10.0)
			_spawn(Vector2(x, y), _random_kind(0.55, 0.3))
	for stream in _streams:
		stream.timer -= delta
		if stream.timer <= 0.0 and stream.left > 0:
			stream.timer = vent_bubble_gap * _rng.randf_range(0.7, 1.3)
			stream.left -= 1
			_spawn(stream.pos + Vector2(_rng.randf_range(-1.5, 1.5), 0.0), _random_kind(0.5, 0.35))
	_streams = _streams.filter(func(s: Dictionary) -> bool: return s.left > 0)
	_step_bubbles(delta)
	queue_redraw()


func _draw() -> void:
	var big_w: float = float(big_sheet.get_width()) / maxf(float(big_frames), 1.0)
	var big_h: float = float(big_sheet.get_height())
	for b in _bubbles:
		var x: float = b.pos.x + sin(b.time * b.freq + b.phase) * b.amp
		var color := Color(1.0, 1.0, 1.0, opacity * b.alpha)
		if b.kind == Kind.BIG:
			var frame: int = 0 if b.pop_time < 0.0 \
					else mini(1 + int(b.pop_time / pop_frame_time), big_frames - 1)
			var at := Vector2(roundf(x - big_w * 0.5), roundf(b.pos.y - big_h * 0.5))
			draw_texture_rect_region(big_sheet, Rect2(at, Vector2(big_w, big_h)),
					Rect2(big_w * frame, 0.0, big_w, big_h), color)
		else:
			var tex: Texture2D = small_texture if b.kind == Kind.SMALL else mid_texture
			var at := Vector2(roundf(x - tex.get_width() * 0.5), roundf(b.pos.y - tex.get_height() * 0.5))
			draw_texture(tex, at, color)


func _step_bubbles(delta: float) -> void:
	var big_pop_length: float = pop_frame_time * float(big_frames - 1)
	for b in _bubbles:
		b.time += delta
		if b.pop_time >= 0.0:
			b.pop_time += delta
			if b.pop_time >= big_pop_length:
				b.dead = true
			continue
		b.pos.y -= b.rise * delta
		var depth: float = b.pos.y - _surface
		if b.kind == Kind.BIG:
			if depth <= 1.0 or (b.pop_at > 0.0 and b.time >= b.pop_at):
				b.pop_time = 0.0
		else:
			b.alpha = clampf(depth / maxf(surface_fade, 1.0), 0.0, 1.0)
			if depth <= 0.0:
				b.dead = true
		# Far out of view (camera moved away): drop it.
		if b.pos.y < _view.position.y - 40.0 or absf(b.pos.x - _view.get_center().x) > _view.size.x:
			b.dead = true
	_bubbles = _bubbles.filter(func(b: Dictionary) -> bool: return not b.dead)


func _spawn(at: Vector2, kind: int) -> void:
	if _bubbles.size() >= max_bubbles or at.y <= _surface + 2.0:
		return
	var rise_range: Vector2 = small_rise if kind == Kind.SMALL \
			else (mid_rise if kind == Kind.MID else big_rise)
	var pop_at: float = -1.0
	if kind == Kind.BIG and _rng.randf() < early_pop_chance:
		pop_at = _rng.randf_range(1.0, 4.0)
	_bubbles.append({
		"pos": at,
		"kind": kind,
		"rise": _rng.randf_range(rise_range.x, rise_range.y),
		"amp": _rng.randf_range(wobble.x, wobble.y),
		"freq": _rng.randf_range(1.5, 3.0),
		"phase": _rng.randf_range(0.0, TAU),
		"time": 0.0,
		"alpha": 1.0,
		"pop_at": pop_at,
		"pop_time": -1.0,
		"dead": false,
	})


func _random_kind(small_share: float, mid_share: float) -> int:
	var r: float = _rng.randf()
	if r < small_share:
		return Kind.SMALL
	if r < small_share + mid_share:
		return Kind.MID
	return Kind.BIG


# A short stream from the first solid ground under a random x in view.
func _start_vent_stream() -> void:
	var x: float = _rng.randf_range(_view.position.x + 8.0, _view.end.x - 8.0)
	var from_y: float = maxf(_view.position.y, _surface + 4.0)
	var from := to_global(Vector2(x, from_y))
	var to := to_global(Vector2(x, _view.end.y + 60.0))
	var query := PhysicsRayQueryParameters2D.create(from, to)
	if _player is CollisionObject2D:
		query.exclude = [(_player as CollisionObject2D).get_rid()]
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var ground: Vector2 = to_local(hit.position)
	if ground.y > _view.end.y + 4.0:
		return
	_streams.append({
		"pos": ground + Vector2(0.0, -2.0),
		"left": _rng.randi_range(vent_stream_size.x, vent_stream_size.y),
		"timer": 0.0,
	})


func _update_player(delta: float, in_view: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
	var feet: Vector2 = to_local(_player.global_position)
	var under: bool = feet.y > _surface + 2.0
	# Splash: the moment Penni goes under the surface.
	if under and not _player_was_under:
		var n: int = _rng.randi_range(splash_count.x, splash_count.y)
		for i in n:
			var spot := feet + Vector2(_rng.randf_range(-splash_spread.x, splash_spread.x),
					_rng.randf_range(-splash_spread.y * 2.0, 0.0))
			_spawn(spot, _random_kind(0.4, 0.35))
	_player_was_under = under
	var swimming: bool = bool(_player.get("swimming")) if "swimming" in _player else under
	if not (under and swimming and in_view):
		return
	_breath_timer -= delta
	if _breath_timer > 0.0:
		return
	var moving: bool = false
	if _player is CharacterBody2D:
		moving = (_player as CharacterBody2D).velocity.length() > 8.0
	var range_s: Vector2 = breath_interval_moving if moving else breath_interval_idle
	_breath_timer = _rng.randf_range(range_s.x, range_s.y)
	var facing: float = -1.0 if _facing_left() else 1.0
	var head := feet + Vector2(head_offset.x * facing, head_offset.y)
	var n: int = _rng.randi_range(breath_cluster.x, breath_cluster.y)
	for i in n:
		_spawn(head + Vector2(_rng.randf_range(-1.5, 1.5), -float(i) * 3.0),
				_random_kind(0.6, 0.35))


func _facing_left() -> bool:
	var sprite: Node = _player.get_node_or_null("AnimatedSprite2D")
	return sprite != null and bool(sprite.get("flip_h"))


# Camera view in this node's space; false when no camera or the view is
# entirely above the water (on land nothing needs bubbles).
func _update_view() -> bool:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return false
	var size: Vector2 = get_viewport_rect().size / camera.zoom.abs()
	var top_left: Vector2 = to_local(camera.get_screen_center_position() - size * 0.5)
	_view = Rect2(top_left, size)
	_surface = _surface_local_y()
	return _view.end.y > _surface + 4.0


func _surface_local_y() -> float:
	var sea: Node = get_parent()
	var world: Node = sea.get_parent() if sea != null else null
	var water: CanvasItem = world.get_node_or_null("Water") as CanvasItem if world != null else null
	if water != null:
		return to_local(water.get_global_transform().origin).y
	if sea is Node2D:
		return to_local((sea as Node2D).to_global(Vector2(0.0, surface_y))).y
	return surface_y
