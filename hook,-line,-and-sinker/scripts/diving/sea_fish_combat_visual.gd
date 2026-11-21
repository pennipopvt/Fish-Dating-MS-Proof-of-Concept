extends Node2D
class_name SeaFishCombatVisual

# Presentation only: this child of DivingWildFish reads the EXISTING
# DivingCombat phases. It never owns timing, parries, fish movement or health.
# All textures are Inspector-editable; the old LAND RippleTell remains intact.
@export_group("Combat Art")
@export var prewindup_sheet: Texture2D = preload("res://sprites/fish/attack-prewindup.png")
@export var windup_sheet: Texture2D = preload("res://sprites/fish/attack-windup.png")
@export var idle_sheet: Texture2D = preload("res://sprites/fish/ripple_idle.png")
@export var splash_sheet: Texture2D = preload("res://sprites/fish/ripple_small_splash.png")
@export var miss_sheet: Texture2D = preload("res://sprites/fish/ripple_fail.png")
@export var perfect_sheet: Texture2D = preload("res://sprites/fish/stun_flash.png")
@export var close_sheet: Texture2D = preload("res://sprites/fish/close_parry_flash.png")

@export_group("Position and Frame Layout")
@export var art_offset: Vector2 = Vector2(0, -2)
@export_range(0.1, 3.0, 0.05) var art_scale: float = 1.0
# Default 0 infers square cells across one horizontal strip (e.g. 128x32
# becomes four 32px frames); override in the Inspector if your PNG differs.
@export_range(0, 128, 1) var frame_width_override: int = 0
@export_range(1.0, 30.0, 1.0) var one_shot_fps: float = 12.0

var _combat: DivingCombat
var _phase_sprite: AnimatedSprite2D
var _feedback_sprite: AnimatedSprite2D
var _last_phase: int = -1


func _ready() -> void:
	_phase_sprite = _new_sprite("CombatPhase")
	_feedback_sprite = _new_sprite("ParryFlash")
	var frames := SpriteFrames.new()
	# The new authored sheets replace ONLY the two lead-in states.
	_add_sheet(frames, &"prewindup", prewindup_sheet, true)
	_add_sheet(frames, &"windup", windup_sheet, true)
	# The rest reuse the same effects as the old ripple feedback.
	_add_sheet(frames, &"idle", idle_sheet, true)
	_add_sheet(frames, &"splash", splash_sheet, false)
	_add_sheet(frames, &"miss", miss_sheet, false)
	_add_sheet(frames, &"perfect", perfect_sheet, false)
	_add_sheet(frames, &"close", close_sheet, false)
	_phase_sprite.sprite_frames = frames
	_feedback_sprite.sprite_frames = frames
	_phase_sprite.hide()
	_feedback_sprite.hide()
	_feedback_sprite.animation_finished.connect(_feedback_sprite.hide)
	_phase_sprite.animation_finished.connect(_on_phase_animation_finished)


func _new_sprite(node_name: String) -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.name = node_name
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = art_offset
	sprite.scale = Vector2.ONE * art_scale
	sprite.z_index = 5
	add_child(sprite)
	return sprite


func _add_sheet(frames: SpriteFrames, animation: StringName,
		sheet: Texture2D, looped: bool) -> void:
	if sheet == null:
		return
	frames.add_animation(animation)
	frames.set_animation_loop(animation, looped)
	frames.set_animation_speed(animation, one_shot_fps)
	var size: Vector2 = sheet.get_size()
	var cell_width: int = frame_width_override if frame_width_override > 0 \
		else mini(int(size.x), int(size.y))
	cell_width = maxi(1, cell_width)
	var count: int = maxi(1, int(size.x) / cell_width)
	for i in range(count):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(i * cell_width, 0, cell_width, size.y)
		frames.add_frame(animation, frame)


func bind_combat(combat: DivingCombat) -> void:
	if _combat != null and _combat.parried.is_connected(_on_parried):
		_combat.parried.disconnect(_on_parried)
	_combat = combat
	if _combat != null:
		_combat.parried.connect(_on_parried)
	_last_phase = -1
	set_process(true)
	_process(0.0)


func _process(_delta: float) -> void:
	if _combat == null or not _combat.is_active() or _combat.target != get_parent():
		_phase_sprite.hide()
		_feedback_sprite.hide()
		_last_phase = -1
		return
	if _combat.phase != _last_phase:
		_last_phase = _combat.phase
		_enter_phase(_combat.phase)
	if _combat.phase == DivingCombat.Phase.WARNING:
		_sync_to_attack_duration(&"prewindup",
			maxf(_combat.attack.pre_windup_duration, 0.05))
	elif _combat.phase == DivingCombat.Phase.WINDUP:
		_sync_to_attack_duration(&"windup",
			maxf(_combat.attack.windup_duration, 0.05))


func _enter_phase(phase: int) -> void:
	match phase:
		DivingCombat.Phase.WARNING:
			_show_phase(&"prewindup", true)
		DivingCombat.Phase.WINDUP:
			_show_phase(&"windup", true)
		DivingCombat.Phase.ATTACK:
			_show_phase(&"splash", false)
		DivingCombat.Phase.DASH:
			_show_phase(&"miss", false)
		DivingCombat.Phase.RECOVERY:
			_show_phase(&"idle", false)
		DivingCombat.Phase.STUN:
			_show_phase(&"idle", false)
			if not _feedback_sprite.visible:
				_show_feedback(&"perfect")


func _show_phase(animation: StringName, frame_locked: bool) -> void:
	var frames: SpriteFrames = _phase_sprite.sprite_frames
	if frames == null or not frames.has_animation(animation):
		_phase_sprite.hide()
		return
	_phase_sprite.show()
	_phase_sprite.play(animation)
	if frame_locked:
		_phase_sprite.pause()


func _sync_to_attack_duration(animation: StringName, seconds: float) -> void:
	var frames: SpriteFrames = _phase_sprite.sprite_frames
	if frames == null or not frames.has_animation(animation):
		return
	var count: int = frames.get_frame_count(animation)
	if count <= 0:
		return
	var fraction: float = clampf(1.0 - _combat.phase_time / seconds, 0.0, 0.9999)
	_phase_sprite.set_frame_and_progress(mini(int(fraction * count), count - 1), 0.0)


func _on_parried(result: StringName) -> void:
	# Miss uses the fish's DASH phase animation. Successful parry effects
	# overlay the moving fish without suppressing the combat cycle.
	if result == &"perfect":
		_show_feedback(&"perfect")
	elif result == &"close":
		_show_feedback(&"close")


func _show_feedback(animation: StringName) -> void:
	var frames: SpriteFrames = _feedback_sprite.sprite_frames
	if frames != null and frames.has_animation(animation):
		_feedback_sprite.show()
		_feedback_sprite.play(animation)


func _on_phase_animation_finished() -> void:
	if _phase_sprite.animation in [&"splash", &"miss"]:
		_phase_sprite.hide()
