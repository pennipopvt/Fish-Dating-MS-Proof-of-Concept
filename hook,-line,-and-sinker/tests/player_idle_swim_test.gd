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
	Input.action_release(&"Move Left")
	player._swim_physics(1.0 / 60.0)
	_check(player.animator.animation == &"swim_idle_l",
		"Releasing left returns to floating while facing left")

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
