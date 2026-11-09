extends Line2D

## Horizontal distance at zero reel progress (pixels left from rod).
@export_range(1.0, 600.0, 1.0) var max_horizontal_distance: float = 340.0
## Distance from rod when the fish breaches the surface.
@export_range(0.0, 300.0, 1.0) var catch_horizontal_distance: float = 75.0
## Depth below water at zero reel progress, independent of horizontal reach.
@export_range(1.0, 250.0, 1.0) var max_depth: float = 65.0
@onready var fish: Sprite2D = $Fish
var _default_fish_scale: Vector2 = Vector2.ONE
var line_dist : float = 0
var pos: Vector2

@export var water_surface_y: float = 44.0
var tell_phase: int = 0
var tell_progress: float = 0.0
@onready var ripple_tell: AnimatedSprite2D = $RippleTell
@onready var bobber: Sprite2D = $Bobber
@export_range(0.0, 2.0, 0.25) var bobber_float_amplitude: float = 1.0
@export_range(0.1, 5.0, 0.1) var bobber_float_speed: float = 1.5
var bobber_float_time: float = 0.0
var bobber_water_position: Vector2 = Vector2.ZERO

func _process(delta: float) -> void:
	if bobber.visible and visible:
		bobber_float_time += delta
		bobber.position = (bobber_water_position + Vector2(0, sin(bobber_float_time * TAU * bobber_float_speed) * bobber_float_amplitude)).round()

var current_ripple_animation: StringName = &""
var counter_flash_time: float = 0.0
var current_telegraph_phase: int = 0
var attack_start_pending: bool = false
var windup_playback_scale: float = 1.0

# Match the authored windup frames to the selected fish attack duration.
func set_windup_duration(seconds: float) -> void:
	var frames: SpriteFrames = ripple_tell.sprite_frames
	if frames == null or not frames.has_animation(&"windup"):
		windup_playback_scale = 1.0
		return
	var native_duration: float = 0.0
	for index in range(frames.get_frame_count(&"windup")):
		native_duration += frames.get_frame_duration(&"windup", index)
	native_duration /= maxf(frames.get_animation_speed(&"windup"), 0.01)
	windup_playback_scale = native_duration / maxf(seconds, 0.01)


@export var stunned_line_color: Color = Color("#ffe55c")
@export var stun_glow_color: Color = Color(1.0, 0.83, 0.18, 0.32)
var stunned_line: bool = false
var stun_glow: Line2D

func set_stunned(value: bool) -> void:
	stunned_line = value
	if stun_glow != null:
		stun_glow.visible = value and visible
	set_tension(0.0 if value else current_tension)

var current_tension: float = 0.0


# Calm -> strained -> near-breaking. Editable in the Inspector.
@export var calm_line_color: Color = Color("#d8e6e4")
@export var strained_line_color: Color = Color("#efb65a")
@export var danger_line_color: Color = Color("#ee514d")
@export_range(0.0, 1.0) var strained_threshold: float = 0.55

func set_tension(amount: float) -> void:
	current_tension = amount
	if stunned_line:
		default_color = stunned_line_color
		return
	var normalized: float = clampf(amount, 0.0, 1.0)
	if normalized <= strained_threshold:
		default_color = calm_line_color.lerp(strained_line_color, normalized / maxf(strained_threshold, 0.001))
	else:
		default_color = strained_line_color.lerp(danger_line_color, (normalized - strained_threshold) / maxf(1.0 - strained_threshold, 0.001))



func _ready() -> void:
	_default_fish_scale = fish.scale
	FishingManager.fish_hooked.connect(hook)
	set_tension(0.0)
	# Separate broad translucent line creates a visible glow without a shader.
	stun_glow = Line2D.new()
	stun_glow.name = "StunGlow"
	stun_glow.width = 7.0
	stun_glow.default_color = stun_glow_color
	stun_glow.antialiased = false
	stun_glow.z_index = -1
	stun_glow.visible = false
	add_child(stun_glow)
	stun_glow.points = points
	BobberManager.equipped_changed.connect(_on_bobber_equipped)
	_on_bobber_equipped(BobberManager.get_equipped_bobber())
	ripple_tell.animation_finished.connect(_on_ripple_animation_finished)
	ripple_tell.hide()
	bobber.hide()
	hide()

func _on_bobber_equipped(data: BobberData) -> void:
	bobber.texture = data.sprite if data != null else null


func send(initial_progress: float = 0.0) -> void:
	#later i wanna add an animation of it being sent into da water
	pos = get_point_position(0)
	# Position both the line tip and hidden fish at the same starting point.
	update_line_dist(initial_progress)
	show()
	update_ripple_position()
	bobber_float_time = 0.0
	bobber.position = bobber_water_position
	bobber.show()
	if stun_glow != null:
		stun_glow.visible = stunned_line
	fish.hide()

#idk how to listen for signals in godot tbh but this would trigger by signal ill adjust later
func hook(item: FishData) -> void:
	# The bite pulls the bobber under immediately; keep telegraphs clear.
	bobber.hide()
	if item == null or item.item_data == null:
		fish.hide()
		return
	fish.texture = item.item_data.sprite
	# Keep other fish at the editor-authored scale; custom fish art can
	# specify a world-space width to avoid looking microscopic.
	fish.scale = _default_fish_scale
	if fish.texture != null and item.hooked_sprite_width > 0.0:
		fish.scale = Vector2.ONE * (item.hooked_sprite_width / float(fish.texture.get_width()))
	fish.show() # Let the scene's water layer determine visibility.

func get_fish_global_position() -> Vector2:
	return fish.global_position

func get_fish_global_scale() -> Vector2:
	return fish.global_scale

func get_fish_global_rotation() -> float:
	return fish.global_rotation

func get_fish_texture() -> Texture2D:
	return fish.texture

func hide_fish_for_catch() -> void:
	bobber.hide()
	fish.hide()
	ripple_tell.hide()
	# Hide the line itself during the airborne catch sequence.
	hide()

func close() -> void:
	bobber.hide()
	set_stunned(false)
	ripple_tell.hide()
	current_ripple_animation = &""
	current_telegraph_phase = 0
	attack_start_pending = false
	counter_flash_time = 0.0
	hide()
	fish.hide()

## While waiting for a bite the line bends at the bobber and hangs almost straight
## down. 0 = straight below the bobber, 1 = the old diagonal toward the fish spot.
@export_range(0.0, 1.0, 0.05) var slack_drop_drift: float = 0.15

# Bend the line at the bobber so the underwater part hangs nearly vertical.
# The next update_line_dist() (the bite) straightens it again.
func set_slack_drop() -> void:
	var surface: Vector2 = bobber_water_position
	var drop_end := Vector2(lerpf(surface.x, fish.position.x, slack_drop_drift), fish.position.y)
	points = PackedVector2Array([get_point_position(0), surface, drop_end])
	if stun_glow != null:
		stun_glow.points = points

func update_line_dist(dist_perc: float) -> void:
	# Collapse a slack (bent) waiting line back to a straight rod-to-fish line.
	while get_point_count() > 2:
		remove_point(get_point_count() - 1)
	#okey so this simple i think
	#basically it just gonna take the progress of the fish encounter
	#then subtract it from one, because u wanna be further from the max distance the more u reel
	var progress: float = clampf(dist_perc, 0.0, 1.0)
	line_dist = lerpf(max_horizontal_distance, catch_horizontal_distance, progress)
	var endpos := Vector2(
		pos.x - line_dist,
		lerpf(water_surface_y + max_depth, water_surface_y, progress)
	)
	fish.position = endpos
	var fishrot: float = atan2((pos.y - endpos.y),(pos.x - endpos.x))
	fish.rotation = fishrot
	set_point_position(1,endpos)
	if stun_glow != null:
		stun_glow.points = points
	update_ripple_position()

# The ripple is anchored to the visible waterline, never the submerged fish.
func update_ripple_position() -> void:
	var start: Vector2 = get_point_position(0)
	var tip: Vector2 = get_point_position(1)
	var difference: float = tip.y - start.y
	var fraction: float = 1.0
	if absf(difference) > 0.001:
		fraction = clampf((water_surface_y - start.y) / difference, 0.0, 1.0)
	var surface_position: Vector2 = start.lerp(tip, fraction).round()
	ripple_tell.position = surface_position
	bobber_water_position = surface_position
	if bobber.visible:
		bobber.position = (surface_position + Vector2(0, sin(bobber_float_time * TAU * bobber_float_speed) * bobber_float_amplitude)).round()

# Fish sprite is centered: its position marks its midpoint.
# Catch as soon as that midpoint reaches the ripple's water surface.
func fish_midpoint_above_water() -> bool:
	return fish.position.y <= water_surface_y

func play_ripple(animation: StringName) -> void:
	if ripple_tell.sprite_frames == null or not ripple_tell.sprite_frames.has_animation(animation):
		ripple_tell.hide()
		return
	if animation != current_ripple_animation:
		current_ripple_animation = animation
		ripple_tell.speed_scale = windup_playback_scale if animation == &"windup" else 1.0
		# Show the authored frames without applying a tint.
		ripple_tell.modulate = Color.WHITE
		ripple_tell.play(animation)
	ripple_tell.show()

func set_telegraph(phase: int, amount: float) -> void:
	tell_progress = amount
	var entering_attack: bool = phase == 3 and current_telegraph_phase != 3
	current_telegraph_phase = phase
	if entering_attack:
		attack_start_pending = true
	elif phase != 3:
		attack_start_pending = false
	update_ripple_position()
	# A new warning must start the instant the miss dash ends, even if
	# counter_fail still has a fraction of a second of animation left.
	if phase == 5 and current_ripple_animation == &"counter_fail":
		ripple_tell.stop()
		current_ripple_animation = &""
		counter_flash_time = 0.0
	# Don't restart a close/miss/perfect flash while combat continues.
	if current_ripple_animation in [&"counter_success", &"counter_close", &"counter_fail"]:
		return
	match phase:
		0:
			ripple_tell.hide()
			current_ripple_animation = &""
		1:
			play_ripple(&"idle")
		2:
			# The gameplay timer is authoritative. Pick the frame from the
			# windup's normalized progress, so it cannot finish early and stall.
			if ripple_tell.sprite_frames != null and ripple_tell.sprite_frames.has_animation(&"windup"):
				var count: int = ripple_tell.sprite_frames.get_frame_count(&"windup")
				if count > 0:
					if current_ripple_animation != &"windup":
						play_ripple(&"windup")
					ripple_tell.pause()
					ripple_tell.set_frame_and_progress(mini(int(clampf(amount, 0.0, 0.99999) * count), count - 1), 0.0)
		3:
			if attack_start_pending:
				attack_start_pending = false
				play_ripple(&"start_attack")
			elif current_ripple_animation != &"start_attack":
				play_ripple(&"attacking")
		4:
			play_ripple(&"stun")
		5:
			play_ripple(&"pre_windup")
		_:
			ripple_tell.hide()

func _on_ripple_animation_finished() -> void:
	# A counter flash should immediately hand control back to the active
	# telegraph instead of holding its last frame.
	if current_ripple_animation in [&"counter_success", &"counter_close", &"counter_fail"]:
		counter_flash_time = 0.0
		current_ripple_animation = &""
		attack_start_pending = false
		set_telegraph(current_telegraph_phase, tell_progress)
		return
	# A one-shot splash marks attack onset; the sustained pull then loops.
	if current_ripple_animation == &"start_attack" and current_telegraph_phase == 3 and counter_flash_time <= 0.0:
		play_ripple(&"attacking")

# Named result hooks keep all feedback art editable in RippleTell's
# SpriteFrames resource (fishing_controller.tscn).
func flash_parry_result(result: StringName) -> void:
	var animation: StringName
	match result:
		&"perfect": animation = &"counter_success"
		&"close": animation = &"counter_close"
		&"miss": animation = &"counter_fail"
		_: return

	attack_start_pending = false
	counter_flash_time = 1.0
	ripple_tell.stop()
	current_ripple_animation = &""
	play_ripple(animation)


# Backwards-compatible name for other callers.
func flash_counter(success: bool) -> void:
	if success:
		flash_parry_result(&"perfect")
