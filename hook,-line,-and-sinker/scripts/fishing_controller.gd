extends Node

enum Fish_State
{
	NOT,
	WAITING,
	FISHING,
	CATCHING
}

var current_state: Fish_State = Fish_State.NOT
var hooked_fish: FishData = null

var casts: int = 0
var progress: float = 0
var bite_time: float = 0

var tension: float = 0
var state_timer: float = 0
var fish_esc_rate: float = 0
var recovery_timer: float = 0

# The chosen FishEscapeState owns the attack properties.
# Each encounter progresses through mutually exclusive combat states.
# PRE_WINDUP -> WINDUP -> ATTACK -> PRE_WINDUP
# Miss -> DASH -> PRE_WINDUP; perfect -> STUN -> PRE_WINDUP.
enum AttackPhase { PRE_WINDUP, WINDUP, ATTACK, DASH, STUN }

# Animation hooks: connect these to player/ripple effects without changing combat rules.
signal parry_resolved(result: StringName)  # &"miss", &"close", &"perfect"
signal reel_window_changed(is_open: bool, is_free: bool)
var attack_phase: AttackPhase = AttackPhase.PRE_WINDUP
var active_attack: FishEscapeState = null
var phase_time: float = 0.0
var attack_elapsed: float = 0.0
var counter_locked: bool = false
var reel_open: bool = false
var free_reel: bool = false
var scroll_streak: int = 0
var last_scroll_ms: int = -100000
@export_range(0.02, 0.3, 0.01) var scrolling_threshold: float = 0.12
@export_range(2, 6, 1) var strong_reel_scrolls: int = 3
@export_range(0.05, 0.3, 0.01) var strong_reel_interval: float = 0.15

# Dash settings live on FishData, so every species can behave differently.
var _miss_dash_tween: Tween

#band-aid fix to avoid accidentally requeueing interact when exiting since exit and interact are the same input
var press_delay: float = 0.10
var delay_time = 0

@export var reel_gain: float = 0.1
@export var starting_progress: float = 0.25
@export var bite_time_min: float = 1
@export var bite_time_max: float = 20

#maybe later these variables can be moved to the manager for shop items to influence dem
@export var tension_recovery: float = 0.2
##delay before recovery starts after reeling ends
@export var recovery_delay: float = 0.1

@export var npc_catch_pose_length: float = 0.1

@onready var fishing_progress: TextureProgressBar = $FishingProgress
@onready var tension_bar: TextureProgressBar = $TensionBar
@onready var fishing_line: Line2D = $FishingLine
# Assign AudioStream resources on these child players in the Inspector.
@onready var hook_sfx: AudioStreamPlayer = $HookSfx
@onready var windup_sfx: AudioStreamPlayer = $WindupSfx
@onready var attack_sfx: AudioStreamPlayer = $AttackSfx
@onready var counter_sfx: AudioStreamPlayer = $CounterSfx
@onready var reel_sfx: AudioStreamPlayer = $ReelSfx
@export_range(1, 16, 1) var reel_sound_polyphony: int = 6
@onready var catch_sfx: AudioStreamPlayer = $CatchSfx
@onready var land_sfx: AudioStreamPlayer = $LandSfx
@onready var lose_sfx: AudioStreamPlayer = $LoseSfx

func _ready() -> void:
	# Allow multiple short reel clicks to overlap rather than restarting one voice.
	reel_sfx.max_polyphony = reel_sound_polyphony

func play_fishing_sound(player: AudioStreamPlayer) -> void:
	if player.stream != null:
		player.play()

@onready var catch_landing_point: Marker2D = $CatchLandingPoint
@onready var npc_landing_point: Marker2D = $NpcLandingPoint
@onready var catch_fish_visual: Sprite2D = $CatchFishVisual
@onready var npc_poof: AnimatedSprite2D = $NpcPoof
@export_range(0.1, 2.0, 0.05) var catch_flight_duration: float = 0.65
@export_range(0.0, 0.5, 0.01) var catch_peak_hang: float = 0.08
@export_range(0.0, 150.0, 1.0) var catch_arc_height: float = 75.0
@export_range(0.0, 2.0, 0.05) var catch_landing_pause: float = 0.45
var catch_tween: Tween
var catch_start: Vector2
var catch_end: Vector2
var catch_start_rotation: float = 0.0
var catch_peak: Vector2

func begin_fishing() -> void:
	if(current_state == Fish_State.NOT && delay_time == 0):
		casts = 0
		#set busy first so exit_fishing can clear it if the cast fails right away
		get_parent().busy = true
		cast_rod()
	
func cast_rod() -> void:
	if(casts >= FishingManager.max_casts_per_session):
		exit_fishing()
		return
	casts += 1
	current_state = Fish_State.WAITING
	
	progress = starting_progress
	tension = 0
	fishing_line.set_tension(tension)
	#once a line is cast, set the time itll take for a fish to present itself!!
	bite_time = randf_range(bite_time_min,bite_time_max)
	#fish is decided on rod cast
	hooked_fish = FishingManager.get_random_catch()
	if(hooked_fish == null):
		#empty or malformed catch pool, nothing to hook
		push_warning("No catchable fish in FishingManager.possible_catches")
		exit_fishing()
		return
	fishing_line.send(starting_progress)
	print("Cast #", casts, " will be a ", hooked_fish.fish_id)

func _process(delta: float) -> void:
	if(current_state == Fish_State.WAITING):
		#tick down timer if we still awaiting a glorious fish
		bite_time -= delta
		#if we reach 0 then find a fish and start reelin for it
		if (bite_time <= 0):
			begin_reeling()
	
	elif(current_state == Fish_State.FISHING):
		#we are fishing now
		if(hooked_fish == null):
			#failsafe
			return
		# A close parry lets the player reel, but the fish keeps swimming
		# away at this attack's authored escape speed. No passive drift and
		# no movement while stunned or dashing.
		if reel_open and not free_reel and active_attack != null and (attack_phase == AttackPhase.ATTACK or attack_phase == AttackPhase.WINDUP):
			progress -= maxf(active_attack.escape_rate, 0.0) * delta
		progress = clampf(progress, 0.0, 1.0)

		# Locked phases preserve their tension. The player can only
		# recover it during an earned reel opening (including STUN).
		if reel_open:
			recover_tension(delta)
		if attack_phase != AttackPhase.DASH:
			update_attack_cycle(delta)
		if current_state != Fish_State.FISHING or hooked_fish == null:
			return

		tension = clamp(tension,0,1)
		fishing_line.set_tension(tension)
		fishing_progress.value = progress
		tension_bar.value = tension
		fishing_line.update_line_dist(progress)
		if fishing_line.fish_midpoint_above_water():
			start_catch_sequence()
			return
		# Finish the dash before checking loss at its destination.
		if progress <= 0.0 and attack_phase != AttackPhase.DASH:
			lose_fish()
	elif(current_state == Fish_State.NOT && delay_time != 0):
		delay_time -= delta
		delay_time = clamp(delay_time,0,1)

func begin_reeling() -> void:
	play_fishing_sound(hook_sfx)
	current_state = Fish_State.FISHING
	#reset progress when finding a fish
	progress = starting_progress
	fishing_progress.value = progress
	tension_bar.value = tension
	
	#once we actually get it, we will let the fishing manager know what fish we have
	FishingManager.hook_fish(hooked_fish)
	fishing_line.update_line_dist(progress)
	# Let the player see a short warning BEFORE the first windup.
	start_pre_windup()
	print("Found ", hooked_fish.fish_id)
	print("Fish behavior available: ", hooked_fish.states.size(), " states.")

func lose_fish() -> void:
	if(hooked_fish == null):
		return
	play_fishing_sound(lose_sfx)
	#inform the fishing manager
	print("Lost ", hooked_fish.fish_id)
	FishingManager.lose_fish(hooked_fish)
	finish_cast()
	
func start_catch_sequence() -> void:
	if current_state != Fish_State.FISHING or hooked_fish == null:
		return
	play_fishing_sound(catch_sfx)
	current_state = Fish_State.CATCHING
	catch_start = catch_fish_visual.get_parent().to_local(fishing_line.get_fish_global_position())
	
	if(hooked_fish.npc_data == null) :
		catch_end = catch_fish_visual.get_parent().to_local(catch_landing_point.global_position)
	else: 
		catch_end = catch_fish_visual.get_parent().to_local(npc_landing_point.global_position)
	
	# Peak above both the water exit and the landing spot.
	catch_peak = catch_start.lerp(catch_end, 0.48)
	catch_peak.y = minf(catch_start.y, catch_end.y) - catch_arc_height
	catch_fish_visual.texture = fishing_line.get_fish_texture()
	catch_fish_visual.scale = fishing_line.get_fish_global_scale()
	catch_fish_visual.position = catch_start
	catch_start_rotation = 0.0 # Horizontal at launch and at the apex of the full flip.
	catch_fish_visual.rotation = catch_start_rotation
	catch_fish_visual.z_index = 12
	catch_fish_visual.show()
	fishing_line.hide_fish_for_catch()
	if catch_tween != null and catch_tween.is_running():
		catch_tween.kill()
	catch_tween = create_tween()
	# An explosive upward launch that loses speed near the apex.
	catch_tween.tween_method(_update_catch_ascent, 0.0, 1.0, catch_flight_duration * 0.47).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	catch_tween.tween_interval(catch_peak_hang)
	# Start almost motionless at the apex, then accelerate toward the ground.
	catch_tween.tween_method(_update_catch_descent, 0.0, 1.0, catch_flight_duration * 0.53).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	catch_tween.tween_callback(_on_catch_landed)
	catch_tween.tween_interval(catch_landing_pause)
	catch_tween.tween_callback(_finish_catch_animation)

func _update_catch_ascent(t: float) -> void:
	# Curved ascent; the spin makes a full turn, slowing to a stop at the peak.
	var control := Vector2(lerpf(catch_start.x, catch_peak.x, 0.2), catch_peak.y)
	var a := catch_start.lerp(control, t)
	var b := control.lerp(catch_peak, t)
	catch_fish_visual.position = a.lerp(b, t)
	catch_fish_visual.rotation = catch_start_rotation + TAU * (1.0 - pow(1.0 - t, 3.0))

func _update_catch_descent(t: float) -> void:
	# The next Bezier starts tangent to the same peak, then curves down.
	var control := Vector2(lerpf(catch_peak.x, catch_end.x, 0.8), catch_peak.y)
	var a := catch_peak.lerp(control, t)
	var b := control.lerp(catch_end, t)
	catch_fish_visual.position = a.lerp(b, t)
	catch_fish_visual.rotation = catch_start_rotation + TAU + TAU * t

func _on_catch_landed() -> void:
	play_fishing_sound(land_sfx)
	catch_fish_visual.position = catch_end
	catch_fish_visual.rotation = 0.0
	catch_fish_visual.z_index = -1

func _finish_catch_animation() -> void:
	# Keep the caught fish visible for poof frame 1. It becomes the NPC
	# faceplant precisely when the poof advances to frame 2.
	if hooked_fish == null or hooked_fish.npc_data == null:
		catch_fish_visual.hide()
	catch_fish_visual.z_index = 12
	catch_fish_visual.rotation = 0.0
	
	# Every landed fish counts toward challenges and the Pokédex.
	# NPCs transform into characters rather than adding an item to storage.
	if hooked_fish.npc_data == null:
		catch_fish()
	else:
		FishingManager.catch_fish(hooked_fish, false)
		create_npc(hooked_fish.npc_data)

func catch_fish() -> void:
	if(hooked_fish == null):
		return
	
	print("Caught ", hooked_fish.fish_id)
	
	FishingManager.catch_fish(hooked_fish)
	finish_cast()
	
func finish_cast() -> void:
	reset_values()
	
	if(casts >= FishingManager.max_casts_per_session):
		exit_fishing()
	else:
		cast_rod()
	
func exit_fishing() -> void:
	if(current_state == Fish_State.FISHING && hooked_fish != null):
		FishingManager.lose_fish(hooked_fish)
	#reset everything upon exit
	reset_values()
	current_state = Fish_State.NOT
	casts = 0
	delay_time = press_delay
	print("finished fishing")
	get_parent().busy = false
	
func reset_values() -> void:
	if _miss_dash_tween != null and _miss_dash_tween.is_running():
		_miss_dash_tween.kill()
	if catch_tween != null and catch_tween.is_running():
		catch_tween.kill()
	catch_fish_visual.hide()
	npc_poof.stop()
	npc_poof.hide()
	progress = 0
	bite_time = 0
	fishing_progress.value = 0
	fishing_line.close()
	state_timer = 0
	fish_esc_rate = 0
	tension = 0
	tension_bar.value = tension
	fishing_line.set_tension(tension)
	hooked_fish = null
	recovery_timer = 0
	fishing_line.set_telegraph(0, 0.0)
	active_attack = null
	fishing_line.set_stunned(false)
	attack_phase = AttackPhase.PRE_WINDUP
	counter_locked = false
	scroll_streak = 0
	_set_reel_open(false, false)
	last_scroll_ms = -100000

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.is_modal_ui_open():
		return

	if event.is_action_pressed("Reel") and current_state == Fish_State.FISHING:
		# Pre-windup is only a warning; dash is a full input lock.
		# A parry is only possible during WINDUP / ATTACK.
		if attack_phase == AttackPhase.DASH or attack_phase == AttackPhase.PRE_WINDUP:
			return
		if reel_open:
			_reel_during_opening()
		elif attack_phase == AttackPhase.WINDUP or attack_phase == AttackPhase.ATTACK:
			attempt_counter()

	if event.is_action_pressed("Interact") and current_state != Fish_State.NOT and current_state != Fish_State.CATCHING:
		exit_fishing()


func _set_reel_open(enabled: bool, free: bool) -> void:
	if reel_open == enabled and free_reel == free:
		return
	reel_open = enabled
	free_reel = free
	reel_window_changed.emit(enabled, free)


func _reel_during_opening() -> void:
	if hooked_fish == null:
		return
	play_fishing_sound(reel_sfx)
	progress = clampf(progress + reel_gain * FishingManager.reel_strength_multiplier, 0.0, 1.0)
	if not free_reel:
		# Each species determines how much tension it generates per reel.
		# The existing attack multiplier applies while the fish is fighting.
		var multiplier: float = hooked_fish.attack_tension_multiplier if fish_esc_rate > 0.0 else 1.0
		tension = clampf(tension + hooked_fish.reel_tension_gain * multiplier * FishingManager.tension_gain_multiplier, 0.0, 1.0)
		fishing_line.set_tension(tension)
		recovery_timer = recovery_delay

	fishing_line.update_line_dist(progress)
	if fishing_line.fish_midpoint_above_water():
		start_catch_sequence()
	elif tension >= 1.0:
		lose_fish()


func recover_tension(delta: float) -> void:
	# Tension cannot dissipate during pre-windup, windup, or a missed dash.
	# Perfect STUN makes this a no-op because its tension is already zero.
	if not reel_open:
		return
	if recovery_timer <= 0.0:
		tension = maxf(0.0, tension - tension_recovery * delta)
	else:
		recovery_timer = maxf(0.0, recovery_timer - delta)


# Preserve the fish's authored state selection, using nonnegative weights.
func select_attack() -> FishEscapeState:
	if hooked_fish == null or hooked_fish.states.is_empty():
		return null
	var total: float = 0.0
	for state in hooked_fish.states:
		if state != null:
			total += maxf(0.0, state.state_probability)
	if total <= 0.0:
		return hooked_fish.states.pick_random()
	var roll: float = randf() * total
	for state in hooked_fish.states:
		if state == null:
			continue
		roll -= maxf(0.0, state.state_probability)
		if roll <= 0.0:
			return state
	return hooked_fish.states.back()

func start_pre_windup() -> void:
	# Warning the player is the hard cut-off for every reel opening.
	_set_reel_open(false, false)
	active_attack = select_attack()
	if active_attack == null:
		push_warning("Hooked fish has no usable attack states")
		lose_fish()
		return
	attack_phase = AttackPhase.PRE_WINDUP
	phase_time = maxf(active_attack.pre_windup_duration, 0.05)
	fish_esc_rate = 0.0
	counter_locked = false
	scroll_streak = 0
	last_scroll_ms = -100000
	fishing_line.set_stunned(false)
	fishing_line.set_telegraph(5, 0.0)


func start_windup() -> void:
	if active_attack == null:
		start_pre_windup()
		return
	play_fishing_sound(windup_sfx)
	attack_phase = AttackPhase.WINDUP
	phase_time = maxf(active_attack.windup_duration, 0.05)
	fishing_line.set_windup_duration(phase_time)
	# A failed parry never reaches this stage: it goes through DASH first.
	fish_esc_rate = 0.0
	print("Windup: ", active_attack.state_name)


func begin_attack() -> void:
	play_fishing_sound(attack_sfx)
	attack_phase = AttackPhase.ATTACK
	phase_time = maxf(active_attack.state_length, 0.05)
	attack_elapsed = 0.0
	fish_esc_rate = active_attack.escape_rate


func update_attack_cycle(delta: float) -> void:
	# The DASH tween owns that state and its timer, not this phase machine.
	if attack_phase == AttackPhase.DASH:
		return
	if active_attack == null:
		start_pre_windup()
		return

	# The parry is a TIME WINDOW, not the full-length attack animation.
	# Once the last close-parry grace moment passes, an uncountered fish
	# immediately dashes away even if the player hasn't scrolled.
	if attack_phase == AttackPhase.ATTACK:
		attack_elapsed += delta
		var parry_deadline: float = active_attack.counter_window + active_attack.close_late_window
		if not reel_open and attack_elapsed > parry_deadline:
			_fail_parry()
			return

	phase_time -= delta
	if phase_time <= 0.0:
		match attack_phase:
			AttackPhase.PRE_WINDUP:
				start_windup()
			AttackPhase.WINDUP:
				begin_attack()
			AttackPhase.ATTACK:
				# If no parry was landed by the time the attack ends,
				# that attack was missed too. Dash, then try again.
				if reel_open:
					start_pre_windup()
				else:
					_fail_parry()
			AttackPhase.STUN:
				start_pre_windup()

	if current_state != Fish_State.FISHING or active_attack == null:
		return
	# The selected animation follows the state; timing stays authoritative.
	match attack_phase:
		AttackPhase.PRE_WINDUP:
			fishing_line.set_telegraph(5, 1.0 - phase_time / maxf(active_attack.pre_windup_duration, 0.01))
		AttackPhase.WINDUP:
			var elapsed: float = active_attack.windup_duration - phase_time
			fishing_line.set_telegraph(2, clampf(elapsed / maxf(active_attack.windup_duration, 0.01), 0.0, 1.0))
		AttackPhase.ATTACK:
			fishing_line.set_telegraph(3, clampf(attack_elapsed / maxf(active_attack.state_length, 0.01), 0.0, 1.0))
		AttackPhase.STUN:
			fishing_line.set_telegraph(4, 0.0)
		AttackPhase.DASH:
			pass


func attempt_counter() -> bool:
	# True means the scroll was consumed as a parry attempt, regardless of
	# result; no reeling happens on the parry scroll itself.
	if hooked_fish == null or active_attack == null or counter_locked:
		return true
	# A pre-windup warning and a dash both ignore scrolls.
	if attack_phase == AttackPhase.PRE_WINDUP or attack_phase == AttackPhase.DASH:
		return true

	var perfect: bool = false
	var close: bool = false
	match attack_phase:
		AttackPhase.WINDUP:
			# The final moments before attack count as an early close parry.
			close = phase_time <= active_attack.close_early_window
		AttackPhase.ATTACK:
			perfect = attack_elapsed <= active_attack.counter_window
			close = not perfect and attack_elapsed <= active_attack.counter_window + active_attack.close_late_window
		_:
			pass

	if not perfect and not close:
		_fail_parry()
		return true

	var now: int = Time.get_ticks_msec()
	if scroll_streak > 0 and now - last_scroll_ms > int(strong_reel_interval * 1000.0):
		# A broken strong-reel sequence counts as an unsuccessful attempt.
		_fail_parry()
		return true
	last_scroll_ms = now
	scroll_streak += 1
	if scroll_streak < strong_reel_scrolls:
		return true

	counter_locked = true
	scroll_streak = 0
	if perfect:
		_perfect_parry()
	else:
		_close_parry()
	return true


func _perfect_parry() -> void:
	# A perfect parry clears ALL existing tension and lets the player
	# reel freely while the fish is stunned.
	tension = 0.0
	tension_bar.value = tension
	recovery_timer = 0.0
	fishing_line.set_tension(tension)
	fishing_line.flash_parry_result(&"perfect")
	play_fishing_sound(counter_sfx)
	attack_phase = AttackPhase.STUN
	fishing_line.set_stunned(true)
	phase_time = maxf(active_attack.stun_duration, 0.1)
	fish_esc_rate = 0.0
	_set_reel_open(true, true)
	parry_resolved.emit(&"perfect")
	FishingManager.parry_resolved.emit(&"perfect")
	print("PERFECT PARRY: ", active_attack.state_name)


func _close_parry() -> void:
	# The fish keeps pulling (and adding attack tension) during the opening.
	fishing_line.flash_parry_result(&"close")
	play_fishing_sound(counter_sfx)
	_set_reel_open(true, false)
	parry_resolved.emit(&"close")
	FishingManager.parry_resolved.emit(&"close")
	print("CLOSE PARRY: ", active_attack.state_name)


func _fail_parry() -> void:
	counter_locked = true
	scroll_streak = 0
	_set_reel_open(false, false)
	# One constant-speed burst: normal fish movement speed, boosted for
	# the dash, multiplied by the dash duration. This is in progress units.
	var dash_duration: float = hooked_fish.miss_dash_duration
	var dash_speed: float = maxf(active_attack.escape_rate, 0.0) * hooked_fish.miss_dash_speed_multiplier
	var dash_target: float = clampf(progress - dash_speed * dash_duration, 0.0, 1.0)
	# This fish's miss penalty builds over the dash, never upfront.
	var starting_tension: float = tension
	var ending_tension: float = clampf(starting_tension + hooked_fish.miss_tension_gain * hooked_fish.attack_tension_multiplier * FishingManager.tension_gain_multiplier, 0.0, 1.0)
	attack_phase = AttackPhase.DASH
	phase_time = dash_duration
	recovery_timer = recovery_delay
	fishing_line.set_tension(tension)
	fishing_line.flash_parry_result(&"miss")
	parry_resolved.emit(&"miss")
	FishingManager.parry_resolved.emit(&"miss")

	if _miss_dash_tween != null and _miss_dash_tween.is_running():
		_miss_dash_tween.kill()
	_miss_dash_tween = create_tween().set_trans(Tween.TRANS_LINEAR)
	_miss_dash_tween.tween_method(_update_miss_dash, progress, dash_target, dash_duration)
	_miss_dash_tween.parallel().tween_method(_update_miss_dash_tension, starting_tension, ending_tension, dash_duration)
	_miss_dash_tween.tween_callback(_on_miss_dash_finished)
	print("MISSED PARRY / DASH: ", active_attack.state_name)


# Tween the combat distance AND visual line together. With no per-frame
# escape drift there is no second movement to fight this animation.
func _update_miss_dash(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	fishing_line.update_line_dist(progress)
	fishing_progress.value = progress


func _update_miss_dash_tension(value: float) -> void:
	# Matches the dash position tween exactly; no recovery until it ends.
	tension = clampf(value, 0.0, 1.0)
	tension_bar.value = tension
	fishing_line.set_tension(tension)


func _on_miss_dash_finished() -> void:
	if current_state != Fish_State.FISHING or hooked_fish == null or attack_phase != AttackPhase.DASH:
		return
	# Finish the dash before checking whether the line is lost.
	if progress <= 0.0 or tension >= 1.0:
		lose_fish()
		return
	# The fish immediately starts its next attack sequence: warning,
	# windup, attack. The player cannot reel until a close/perfect parry.
	start_pre_windup()


func create_npc(npc: PackedScene) -> void:
	# Capture the fish BEFORE any awaits or exit_fishing(), which clears
	# hooked_fish. Recruitment is decided later by the NPC's conversation.
	var caught_fish: FishData = hooked_fish
	# The fish remains at the NPC landing spot on poof frame 1.
	npc_poof.position = npc_landing_point.position
	npc_poof.show()
	npc_poof.play(&"poof")

	# Wait for the start of the second frame before swapping the fish for
	# Ethan's existing faceplant ("on_caught") NPC sprite.
	await npc_poof.frame_changed
	var scene := npc.instantiate() as NPCInteractable
	var world: Node = get_parent().get_parent()
	world.add_child(scene)
	scene.global_position = npc_landing_point.global_position
	scene.z_index = 12
	var sprite: AnimatedSprite2D = scene.get_node("Sprite")
	sprite.play(&"on_caught")
	catch_fish_visual.hide()
	get_parent().animator.play(&"idle_r")

	# Let the full poof finish, then retain Ethan's faceplant beat
	# before restoring the NPC idle and starting dialogue.
	await npc_poof.animation_finished
	npc_poof.hide()
	await get_tree().create_timer(npc_catch_pose_length).timeout
	sprite.play(&"default")
	exit_fishing()
	# RecruitmentHandler only reacts to the first conversation after an NPC is caught.
	# Register this specific NPC before opening the conversation.
	RecruitmentHandler.engage_listen(scene, caught_fish)
	scene.interact(get_parent())
