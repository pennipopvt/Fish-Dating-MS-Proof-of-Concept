extends Line2D

#this is kinda temporary im figuring out line2D
#also idk if ur gonna make like, a manually animated fishing rod or not
#so im not putting too much stock into this

@export var max_dist: float
@export var y_line_offset: float
@onready var fish: Sprite2D = $Fish
var line_dist : float = 0
var pos: Vector2

@export var water_surface_y: float = 44.0
var tell_phase: int = 0
var tell_progress: float = 0.0
@onready var ripple_tell: AnimatedSprite2D = $RippleTell
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
	ripple_tell.animation_finished.connect(_on_ripple_animation_finished)
	ripple_tell.hide()
	hide()

func send(initial_progress: float = 0.0) -> void:
	#later i wanna add an animation of it being sent into da water
	pos = get_point_position(0)
	# Position both the line tip and hidden fish at the same starting point.
	update_line_dist(initial_progress)
	show()
	update_ripple_position()
	if stun_glow != null:
		stun_glow.visible = stunned_line
	fish.hide()

#idk how to listen for signals in godot tbh but this would trigger by signal ill adjust later
func hook(item: FishData) -> void:
	fish.texture = item.item_data.sprite
	fish.show() # Let the scene's water layer determine visibility.

func close() -> void:
	set_stunned(false)
	ripple_tell.hide()
	current_ripple_animation = &""
	current_telegraph_phase = 0
	attack_start_pending = false
	counter_flash_time = 0.0
	hide()
	fish.hide()

func update_line_dist(dist_perc: float) -> void:
	#okey so this simple i think
	#basically it just gonna take the progress of the fish encounter
	#then subtract it from one, because u wanna be further from the max distance the more u reel
	line_dist = max_dist * (1 - dist_perc)
	line_dist = clamp(line_dist,0,max_dist)
	var endpos = pos
	endpos.x -= line_dist
	#slight offset to keep the fish in what would be the water
	endpos.y += (line_dist + y_line_offset)
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
	ripple_tell.position = start.lerp(tip, fraction).round()

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
		ripple_tell.play(animation)
	ripple_tell.show()

func set_telegraph(phase: int, amount: float) -> void:
	var entering_attack: bool = phase == 3 and current_telegraph_phase != 3
	current_telegraph_phase = phase
	if entering_attack:
		attack_start_pending = true
	elif phase != 3:
		attack_start_pending = false
	update_ripple_position()
	if counter_flash_time > 0.0:
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
		_:
			ripple_tell.hide()

func _on_ripple_animation_finished() -> void:
	# A one-shot splash marks attack onset; the sustained pull then loops.
	if current_ripple_animation == &"start_attack" and current_telegraph_phase == 3 and counter_flash_time <= 0.0:
		play_ripple(&"attacking")

func flash_counter(success: bool) -> void:
	# Only successful counters have a feedback animation.
	# A miss lets windup / start_attack / attacking play uninterrupted.
	if not success:
		return
	counter_flash_time = 0.35
	play_ripple(&"counter_success")

func _process(delta: float) -> void:
	if counter_flash_time > 0.0:
		counter_flash_time = maxf(0.0, counter_flash_time - delta)
