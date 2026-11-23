extends Node

# Check the actual imported idle-swim sprite sheets, direction changes,
# floating without input, paused/swimming transitions, and land restoration.
const PLAYER: PackedScene = preload("res://prefabs/player.tscn")

var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player: Player = PLAYER.instantiate() as Player
	add_child(player)
	await get_tree().process_frame
	# Regression: do not let the Player script undo settings in child nodes.
	var step_timer: Timer = player.get_node("StepTimer") as Timer
	var swim_sound: AudioStreamPlayer = player.get_node("SwimSound") as AudioStreamPlayer
	step_timer.wait_time = 0.93
	swim_sound.volume_db = -1.5
	swim_sound.pitch_scale = 0.65
	player._update_step_audio(true)
	_check(is_equal_approx(step_timer.wait_time, 0.93) and not step_timer.is_stopped(),
		"Walking uses the editor-authored StepTimer Wait Time without overwriting it")
	player._stop_step_audio()
	# The 2s WAV has a very short impact and a long silent tail. A new
	# step must still trigger even if the preceding audio is still playing.
	# Use the actual editor-timer timeout callback with an active walk.
	player.velocity = Vector2(100.0, 0.0)
	player._play_step()
	_check((player.get_node("StepSound") as AudioStreamPlayer).playing,
		"Footstep starts before the next timer tick")
	player._on_step_timer_timeout()
	_check((player.get_node("StepSound") as AudioStreamPlayer).playing,
		"Another timer tick can retrigger a still-active footstep stream")
	player._stop_step_audio()
	var frames: SpriteFrames = player.animator.sprite_frames
	for animation_name in [&"swim_l", &"swim_r", &"swim_idle_l", &"swim_idle_r"]:
		_check(frames.has_animation(animation_name)
			and frames.get_frame_count(animation_name) > 0,
			"Existing animator includes nonempty %s" % animation_name)
	for facing in [&"l", &"r"]:
		var idle_animation := StringName("swim_idle_" + String(facing))
		var texture: AtlasTexture = frames.get_frame_texture(idle_animation, 0) as AtlasTexture
		var expected: String = "penni_swim_idle_L.png" if facing == &"l" else "penni_swim_idle_R.png"
		_check(texture != null and texture.atlas != null
			and texture.atlas.resource_path.ends_with(expected),
			"Idle %s uses the new masked idle-swim sheet" % facing)
		_check(frames.get_animation_loop(idle_animation),
			"Idle %s loops while floating" % facing)

	# The player should float rather than swim in place when entering the sea.
	player.last_direction = -1.0
	player.set_swimming(true, Rect2(-200, -200, 400, 400))
	_check(player.animator.animation == &"swim_idle_l",
		"Entering the sea without movement starts the masked left idle")

	Input.action_press(&"Move Left")
	player._swim_physics(1.0 / 60.0)
	_check(player.animator.animation == &"swim_l",
		"Movement left switches to the existing swimming animation")
	var swim_audio: AudioStreamPlayer = player.get_node("SwimSound") as AudioStreamPlayer
	_check(swim_audio.stream is AudioStreamWAV
		and (swim_audio.stream as AudioStreamWAV).format != AudioStreamWAV.FORMAT_QOA
		and (swim_audio.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"New swim WAV imports as looping PCM instead of QOA")
	_check(swim_audio.playing and swim_audio.bus == &"UnderwaterSFX"
		and is_equal_approx(swim_audio.pitch_scale, 0.65)
		and is_equal_approx(swim_audio.volume_db, -1.5),
		"Active swimming respects editor-authored pitch and volume on SwimSound")
	Input.action_release(&"Move Left")
	player._swim_physics(1.0 / 60.0)
	_check(player.animator.animation == &"swim_idle_l",
		"Releasing left returns to floating while facing left")
	_check(not swim_audio.playing and not (player.get_node("StepSound") as AudioStreamPlayer).playing,
		"Idling underwater stops swim strokes without starting footsteps")

	Input.action_press(&"Move Right")
	player._swim_physics(1.0 / 60.0)
	_check(player.animator.animation == &"swim_r",
		"Movement right switches to the existing swimming animation")
	Input.action_release(&"Move Right")
	player._swim_physics(1.0 / 60.0)
	_check(player.animator.animation == &"swim_idle_r",
		"Releasing right returns to floating while facing right")

	player.busy = true
	player._physics_process(1.0 / 60.0)
	_check(player.animator.animation == &"swim_idle_r",
		"Underwater dialogue or busy state keeps the idle-swim pose")
	player.busy = false

	player.set_swimming(false)
	_check(not player.swimming and player.animator.animation == &"idle_r",
		"Surfacing restores the original land idle animation")
	_check(not swim_audio.playing, "Surfacing stops swimming loop")
	player.last_direction = -1.0
	player.set_swimming(true, Rect2(-200, -200, 400, 400))
	player.set_swimming(false)
	_check(player.animator.animation == &"idle_l",
		"Land idle continues respecting the last facing direction")

	player.queue_free()
	print("player_idle_swim_test: PASS" if failures == 0 else
		"player_idle_swim_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
