extends Node2D
class_name DivingWorld

signal surface_requested(with_silas: bool)

# Self-contained diving vertical slice. The original dock/fishing/romance
# systems remain on this branch for comparison; this is an alternate main scene.
# All distances are in the 320x180 game's small pixel-world coordinates.
const WILD_FISH_SCRIPT = preload("res://scripts/diving/wild_fish.gd")
const DIALOGUE_SCENE: PackedScene = preload("res://prefabs/dialogue_ui.tscn")
const SILAS_NPC: NPCData = preload("res://resources/npcs/silas.tres")
const SILAS_FISH_DATA: FishData = preload("res://resources/fish/silas.tres")
const PLAYER_IDLE: Texture2D = preload("res://sprites/characters/penni/penni_idle.png")
const SILAS_FISH: Texture2D = preload("res://sprites/fish/silas_eel.png")
const SILAS_HUMAN: Texture2D = preload("res://sprites/characters/silas_idle.png")
# Wild fish species, art, and spawn positions now live on FishSpawns marker
# nodes in diving_prototype.tscn instead of being hardcoded in this script.

# Dimensions and collision geometry now come from the editor-authored lagoon.
const SHORE_DIVE_POINT := Vector2(251.0, 111.0)
const SWIM_SPEED: float = 78.0
const REACH: float = 44.0
# How far from Penni a fish can be for Silas to be sent at it (right-click).
const BATTLE_RANGE: float = 120.0

@export var show_prototype_environment: bool = true
# Turn this off once you have painted/placed actual lagoon scenery in the
# LevelArt or ForegroundArt nodes. It hides placeholder terrain and reefs.

@onready var _entry_point: Vector2 = to_local(($Points/Entry as Marker2D).global_position)
@onready var _surface_point: Vector2 = to_local(($Points/SurfaceExit as Marker2D).global_position)
@onready var _silas_burrow: Vector2 = to_local(($Points/SilasBurrow as Marker2D).global_position)
@onready var _tangled_net: Vector2 = to_local(($Points/TangledNet as Marker2D).global_position)
@onready var _glowing_garden: Vector2 = to_local(($Points/ShellGarden as Marker2D).global_position)
@onready var _level_guide: LagoonEditorGuide = $EditorGuide
@onready var _wall_cast: ShapeCast2D = get_node_or_null("Player/WallCast") as ShapeCast2D
@onready var _prototype_visual: Sprite2D = get_node_or_null("Player") as Sprite2D
# The World scene shares its original Player and camera with this lagoon.
@onready var player_sprite: Node2D = (get_parent().get_node("Player") as Node2D) if get_parent().has_node("Player") else ($Player as Node2D)
@onready var camera: Camera2D = (player_sprite.get_node("Camera2D") as Camera2D) if player_sprite is Player else ($Camera2D as Camera2D)
@onready var _hud_root: Control = (get_node("../../../../DivingHUD") as Control) if player_sprite is Player else (get_node("../../../HUD") as Control)
@onready var silas_sprite: Sprite2D = $Silas
@onready var location_label: Label = _hud_root.get_node("Location") as Label
@onready var catch_label: Label = _hud_root.get_node("CatchCount") as Label
@onready var story_label: Label = _hud_root.get_node("StoryHint") as Label
@onready var prompt_label: Label = _hud_root.get_node("Prompt") as Label
@onready var toast_label: Label = _hud_root.get_node("Toast") as Label
@onready var hud_footer: Panel = _hud_root.get_node("FooterBack") as Panel
@onready var _combat: DivingCombat = $Combat
@onready var _net: DivingNetProjectile = $NetProjectile
@onready var _battle: DivingCompanionBattle = $CompanionBattle
# Short lunge toward the fish each time Silas lands a hit.
var _silas_lunge: float = 0.0
var _combat_direction: Vector2 = Vector2.RIGHT
var _combat_distance: float = 40.0

var _embedded_in_world: bool = false
var _underwater: bool = true
var _silas_met: bool = false
# _net_cleared now means Silas has been reeled free from his burrow.
var _net_cleared: bool = false
var _silas_rescue_target: DivingWildFish
var _silas_wait_position: Vector2 = Vector2.ZERO
var _silas_following: bool = false
var _silas_talks: int = 0
var _silas_ashore: bool = false
var _discovered_garden: bool = false
var _wild_fish: Array[DivingWildFish] = []
var _caught: Dictionary[StringName, int] = {}
var _time: float = 0.0
var _veil_time: float = 0.0
var _veil_cooldown: float = 0.0
var _talk_cooldown: float = 0.0
var _net_flash_time: float = 0.0
var _net_flash_point: Vector2 = Vector2.ZERO
var _toast_time: float = 0.0
var _dialogue_event: StringName = &""
var _surface_choice: StringName = &""
var _standalone_dialogue_ui: DialogueUI
var _shore_transformation_played: bool = false

func _ready() -> void:
	_embedded_in_world = player_sprite is Player
	_underwater = not _embedded_in_world
	if not _embedded_in_world:
		player_sprite.position = _entry_point
		var preview: Sprite2D = player_sprite as Sprite2D
		preview.texture = PLAYER_IDLE
		preview.hframes = 2
		preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		preview.scale = Vector2.ONE
	silas_sprite.position = _silas_burrow + Vector2(0, -16)
	silas_sprite.texture = SILAS_FISH
	silas_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_set_silas_fish_sprite()
	if not _embedded_in_world:
		camera.position = player_sprite.position
		_set_camera_bounds(true)
	_combat.finished.connect(_on_combat_finished)
	_net.fish_hit.connect(_on_net_fish_hit)
	_combat.parried.connect(_on_combat_parried)
	_battle.hit.connect(_on_battle_hit)
	_battle.fish_knocked_out.connect(_on_battle_fish_knocked_out)
	_battle.companion_knocked_out.connect(_on_battle_companion_knocked_out)
	# Resting (a new day) is the only cure for an exhausted companion.
	GameManager.day_started.connect(func(_day: int) -> void: _battle.rest())
	DialogueManager.conversation_finished.connect(_on_diving_conversation_finished)
	DialogueManager.choice_resolved.connect(_on_diving_choice_resolved)
	# The integrated island owns a DialogueUI already. For running the
	# standalone diving scene directly, add the same reusable UI once.
	_ensure_standalone_dialogue_ui.call_deferred()
	_spawn_fish()
	_update_hud()
	_toast("A voice somewhere in the reef...")

# When used by scenes/main.tscn, the existing dock is the land scene.
# This underwater instance stays alive between dives, preserving Silas's
# conversations, his decision to follow, and ordinary fish already caught.
func set_embedded_mode(value: bool) -> void:
	_embedded_in_world = value
	if value and is_instance_valid(_standalone_dialogue_ui):
		_standalone_dialogue_ui.queue_free()
		_standalone_dialogue_ui = null


func _ensure_standalone_dialogue_ui() -> void:
	if _embedded_in_world or is_instance_valid(_standalone_dialogue_ui):
		return
	_standalone_dialogue_ui = DIALOGUE_SCENE.instantiate() as DialogueUI
	get_tree().root.add_child(_standalone_dialogue_ui)
	_standalone_dialogue_ui.player_portrait = preload("res://sprites/characters/penni/penni_portrait.png")
	_standalone_dialogue_ui.set_underwater_mode(true)


func _set_dialogue_visual_mode(underwater: bool) -> void:
	# In the normal game, DiveEntry owns this switch on the single dialogue
	# UI. Standalone diving keeps its own instance of that same component.
	if is_instance_valid(_standalone_dialogue_ui):
		_standalone_dialogue_ui.set_underwater_mode(underwater)


func enter_from_dock() -> void:
	_go_underwater()


func _return_to_surface(with_silas: bool) -> void:
	# A throw that missed should not remain stuck midway through its flight
	# when the underwater scene is hidden until the next dive.
	_net.reset_net()
	# The lagoon stops processing on land, so end any battle here.
	_battle.stop()
	if _embedded_in_world:
		_underwater = false
		_dialogue_event = &""
		_surface_choice = &""
		if with_silas:
			# Remember his decision across later dives. His fish form still
			# follows underwater; the island provides his human form on land.
			_silas_ashore = true
		surface_requested.emit(with_silas)
	else:
		_go_shore(with_silas)


func _set_silas_fish_sprite() -> void:
	silas_sprite.texture = SILAS_FISH
	var width: float = float(SILAS_FISH.get_width())
	silas_sprite.scale = Vector2.ONE * (18.0 / maxf(width, 1.0))
	silas_sprite.rotation = 0.0
	silas_sprite.visible = true

func _set_silas_human_sprite() -> void:
	var frame := AtlasTexture.new()
	frame.atlas = SILAS_HUMAN
	frame.region = Rect2(0, 0, 32, 32)
	silas_sprite.texture = frame
	silas_sprite.scale = Vector2.ONE
	silas_sprite.rotation = 0.0
	silas_sprite.visible = true

# Resize the ocean in EditorGuide/Map Size; gameplay, spawn bounds and
# camera update together. Leave a small margin around the edges for sprites.
func _sea_bounds() -> Rect2:
	var size: Vector2 = _level_guide.map_size
	if _embedded_in_world:
		return Rect2(Vector2(16.0, 154.0), size - Vector2(32.0, 170.0))
	return Rect2(Vector2(16.0, 30.0), size - Vector2(32.0, 70.0))


func _swim_sweep(motion: Vector2) -> float:
	if motion.length_squared() <= 0.000001:
		return 1.0
	# Player is still the existing Sprite2D, so a child ShapeCast2D supplies
	# solid-tile collision without replacing its visual or dialogue references.
	# Cancel the slight visual bank so casts remain world-axis aligned.
	_wall_cast.rotation = -player_sprite.rotation
	_wall_cast.target_position = motion
	_wall_cast.force_shapecast_update()
	return clampf(_wall_cast.get_closest_collision_safe_fraction(), 0.0, 1.0)


func _move_swimmer(motion: Vector2) -> void:
	if motion.length_squared() <= 0.000001:
		return
	var safe: float = _swim_sweep(motion)
	player_sprite.position += motion * maxf(0.0, safe - 0.005)
	if safe >= 0.999:
		return
	# A blocked diagonal input slides along walls instead of freezing Penni.
	var remainder: Vector2 = motion * (1.0 - safe)
	for axis_motion in [Vector2(remainder.x, 0.0), Vector2(0.0, remainder.y)]:
		if axis_motion.length_squared() <= 0.000001:
			continue
		var axis_safe: float = _swim_sweep(axis_motion)
		player_sprite.position += axis_motion * maxf(0.0, axis_safe - 0.005)


func _spawn_fish() -> void:
	# Every fish starts from an editor-placeable FishSpawns marker. Designers
	# can move, add, duplicate or delete markers without rewriting code.
	for child in $FishSpawns.get_children():
		var spawn: DivingFishSpawn = child as DivingFishSpawn
		if spawn == null or spawn.species == null or spawn.species.item_data == null:
			continue
		var art: Texture2D = spawn.species.item_data.sprite
		if art == null or spawn.species.states.is_empty():
			continue
		var fish: DivingWildFish = WILD_FISH_SCRIPT.new() as DivingWildFish
		fish.setup(spawn.species.fish_id, art, to_local(spawn.global_position), _sea_bounds(), spawn.random_seed)
		fish.set_max_health(spawn.species.max_health)
		add_child(fish)
		_wild_fish.append(fish)

func _process(delta: float) -> void:
	_time += delta
	_veil_time = maxf(0.0, _veil_time - delta)
	_veil_cooldown = maxf(0.0, _veil_cooldown - delta)
	_talk_cooldown = maxf(0.0, _talk_cooldown - delta)
	_toast_time = maxf(0.0, _toast_time - delta)
	_net_flash_time = maxf(0.0, _net_flash_time - delta)
	var is_talking: bool = DialogueManager.is_active
	var fighting: bool = _combat.is_active()
	toast_label.visible = _toast_time > 0.0 and not is_talking and not fighting
	story_label.visible = not is_talking and not fighting
	prompt_label.visible = not is_talking and not fighting
	hud_footer.visible = not is_talking and not fighting

	if not _embedded_in_world and not is_talking and not fighting:
		_move_player(delta)
	# The auto-battle pauses for nothing: dialogue, the reel fight or leaving
	# the water calls Silas back. Idle steps regenerate his health.
	if _battle.is_active() and (is_talking or fighting or not _underwater):
		_battle.stop()
	_battle.step(delta)
	_silas_lunge = maxf(0.0, _silas_lunge - delta)
	if fighting:
		_combat.step(delta)
		_sync_combat_fish(delta)
	_update_net_tension()

	if _underwater:
		if not _combat.is_active():
			for fish in _wild_fish:
				if is_instance_valid(fish):
					fish.swim(delta, player_sprite.position, _veil_time > 0.0)
		_update_silas_fish(delta)
		_maybe_discover_garden()
		if not _embedded_in_world:
			camera.position = camera.position.lerp(player_sprite.position, minf(delta * 5.5, 1.0))
	else:
		if not _embedded_in_world:
			camera.position = camera.position.lerp(Vector2(160, 90), minf(delta * 7.0, 1.0))
			if _silas_ashore:
				silas_sprite.position.y = 110.0 + sin(_time * 1.7) * 0.45

	if not _embedded_in_world:
		_prototype_visual.frame = int(_time * 3.2) % 2
	_update_hud()
	queue_redraw()

func _move_player(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
	var speed: float = SWIM_SPEED if _underwater else 64.0
	if _underwater and _veil_time > 0.0:
		speed *= 0.82
	if _underwater:
		_move_swimmer(direction * speed * delta)
		var limits: Rect2 = _sea_bounds()
		player_sprite.position.x = clampf(player_sprite.position.x, limits.position.x + 8.0, limits.end.x - 8.0)
		player_sprite.position.y = clampf(player_sprite.position.y, limits.position.y + 8.0, limits.end.y - 8.0)
		player_sprite.rotation = lerpf(player_sprite.rotation, direction.x * 0.11, minf(delta * 6.0, 1.0))
		# Visual bob only: never shift the physics point through a painted wall.
		_prototype_visual.offset.y = sin(_time * 2.6) * 0.8
	else:
		player_sprite.position += direction * speed * delta
		_prototype_visual.offset.y = 0.0
		player_sprite.position.x = clampf(player_sprite.position.x, 38.0, 280.0)
		player_sprite.position.y = clampf(player_sprite.position.y, 76.0, 148.0)
		player_sprite.rotation = 0.0
	if direction.x < -0.05:
		_prototype_visual.flip_h = true
	elif direction.x > 0.05:
		_prototype_visual.flip_h = false

func _player_faces_left() -> bool:
	if _embedded_in_world:
		return (player_sprite as Player).last_direction < 0.0
	return _prototype_visual.flip_h


func _update_silas_fish(delta: float) -> void:
	# While Silas is a trapped, catchable fish, that actor owns his art. Don't
	# duplicate him as a second static sprite behind the net battle.
	if is_instance_valid(_silas_rescue_target):
		silas_sprite.hide()
		return
	silas_sprite.visible = true
	if _battle.is_active():
		# Fight on the side of the fish facing Penni, lunging on each hit.
		var foe: Vector2 = _battle.target.position
		var side: Vector2 = (player_sprite.position - foe).normalized()
		if side.length_squared() < 0.01:
			side = Vector2.LEFT
		var spot: Vector2 = foe + side * (22.0 - 7.0 * (_silas_lunge / 0.15))
		silas_sprite.position = silas_sprite.position.move_toward(spot, 140.0 * delta)
		silas_sprite.flip_h = foe.x < silas_sprite.position.x
		silas_sprite.rotation = sin(_time * 9.0) * 0.12
		return
	if not _silas_following:
		var resting: Vector2 = _silas_wait_position if _net_cleared else _silas_burrow + Vector2(0, -16)
		silas_sprite.position = resting + Vector2(sin(_time * 1.7) * 1.7, sin(_time * 2.3) * 1.4)
		silas_sprite.flip_h = false
		return
	# Keep Silas physically near the player but give him a little room to
	# explore, catch up, and glide naturally instead of snapping to a socket.
	var offset := Vector2(23.0 if _player_faces_left() else -23.0, 12.0 + sin(_time * 1.7) * 4.0)
	var target: Vector2 = player_sprite.position + offset
	var distance: float = silas_sprite.position.distance_to(target)
	var max_speed: float = 114.0 if distance > 95.0 else 67.0
	var before: Vector2 = silas_sprite.position
	if distance > 9.0:
		silas_sprite.position = silas_sprite.position.move_toward(target, max_speed * delta)
	else:
		silas_sprite.position.y += sin(_time * 2.0) * delta
	silas_sprite.flip_h = silas_sprite.position.x < before.x - 0.01
	silas_sprite.rotation = sin(_time * 3.0) * 0.07

func _maybe_discover_garden() -> void:
	if _discovered_garden or not _silas_following or DialogueManager.is_active or _combat.is_active():
		return
	if player_sprite.position.distance_to(_glowing_garden) < 45.0:
		_discovered_garden = true
		_start_dialogue("Silas", [
			"Wait... look at the light coming from those shells.",
			"I've lived down here forever, and I've never seen this place.",
			"I'm glad I came swimming with you."
		])

func _unhandled_input(event: InputEvent) -> void:
	if _embedded_in_world and not _underwater:
		return
	# Dialogue UI owns conversation input; diving combat owns scroll-down
	# while engaged. Movement, net clicks and Silas commands are paused.
	if DialogueManager.is_active:
		return
	if _combat.is_active():
		if event.is_action_pressed("Reel") or (
			event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			_combat.reel_scroll()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_combat.release()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E or event.keycode == KEY_SPACE:
			_interact()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Q:
			_ask_silas_to_hide()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_recall_silas()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _underwater:
			_try_catch(get_global_mouse_position())
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if _underwater:
			_command_battle(get_global_mouse_position())
			get_viewport().set_input_as_handled()

func _interact() -> void:
	if _combat.is_active():
		return
	if not _underwater:
		if player_sprite.position.distance_to(SHORE_DIVE_POINT) < REACH:
			_go_underwater()
		else:
			_toast("The ocean is to the right. Swim again at the dock.")
		return
	if player_sprite.position.distance_to(_surface_point) < REACH:
		_try_surface()
		return
	if player_sprite.position.distance_to(silas_sprite.position) < REACH:
		_talk_to_silas()
		return
	_toast("Swim near Silas or the surface marker, then press E.")

func _talk_to_silas() -> void:
	if _talk_cooldown > 0.0:
		_toast("Give him a moment.")
		return
	_talk_cooldown = 0.9
	if not _silas_met:
		_silas_met = true
		_start_dialogue("???", [
			"H-help! Can you hear me?",
			"I'm stuck in this old net! Could you help pull me out?",
			"Throw your net toward me, then reel me close.",
			"Please... I can't get out of here by myself."
		], &"silas_rescue_ready")
		return
	if not _net_cleared:
		_start_dialogue("???", [
			"I'm still caught here...",
			"Please throw your net toward me and reel me out!",
			"If I slip away, you can try again. I'll be right here."
		])
		return
	if not _silas_following:
		_start_dialogue("Silas", [
			"Thank you for pulling me out! I'm Silas.",
			"Could I swim with you? I'd like to get away from this burrow for a while."
		], &"start_following")
		return
	_silas_talks += 1
	match _silas_talks:
		1:
			_start_dialogue("Silas", [
				"I usually just watch everything from the sand.",
				"Swimming with someone is... different. Good different.",
				"You can ask me to hide us with Q, if another fish gets nervous."
			])
		2:
			_start_dialogue("Silas", [
				"Are the stars really like the little lights down here?",
				"I can see the surface from my burrow, but I've never gone up.",
				"Maybe I'd like to... if you were there."
			])
		3:
			_start_dialogue("Silas", [
				"You keep showing me things I never would've looked for.",
				"If you go back soon... could I see the surface with you?"
			])
		_:
			var extra: Array[String] = [
				"There's a whole world up there, isn't there?",
				"Sorry, I think I'm following you too closely. I'll give you some room.",
				"I like this. Just swimming somewhere together.",
				"I didn't know the reef could feel so big."
			]
			_start_dialogue("Silas", [extra[(_silas_talks - 4) % extra.size()]])

func _try_catch(world_mouse: Vector2) -> void:
	if _net.is_busy() or _combat.is_active():
		return
	# Cast the real net. After Silas calls for help, his trapped fish actor
	# joins the same projectile collision list as ordinary wild fish.
	_net.cast_net(player_sprite, world_mouse, _wild_fish)


func _on_net_fish_hit(fish: DivingWildFish) -> void:
	if fish == null or not is_instance_valid(fish):
		_net.retract()
		return
	_begin_combat(fish)
	if not _combat.is_active():
		_net.retract()



func _begin_combat(fish: DivingWildFish) -> void:
	if _combat.is_active() or DialogueManager.is_active:
		return
	var data: FishData = SILAS_FISH_DATA if fish == _silas_rescue_target else _get_fish_data(fish.fish_name)
	if data == null or data.states.is_empty():
		_toast("This fish doesn't have combat behavior yet.")
		return
	_combat_direction = (fish.position - player_sprite.position).normalized()
	if _combat_direction.length_squared() <= 0.01:
		_combat_direction = Vector2.RIGHT
	_combat_distance = player_sprite.position.distance_to(fish.position)
	# A fish worn down by Silas pulls and strains the line less.
	var health_ratio: float = 1.0 if fish == _silas_rescue_target else fish.health_ratio()
	if _combat.begin(fish, data, _combat_distance, _net.max_range, health_ratio):
		_battle.stop()
		_net_flash_time = 0.0
		_update_net_tension()


func _get_fish_data(fish_id: StringName) -> FishData:
	for resource in FishingManager.possible_catches:
		if resource != null and resource.fish_id == fish_id:
			return resource
	return null


func _sync_combat_fish(_delta: float) -> void:
	if not _combat.is_active():
		return
	var fish: DivingWildFish = _combat.target
	# Match the original FishingLine.update_line_dist(): the fish's visible
	# position comes from the SAME distance that governs the catch. No more
	# distant-looking fish being collected when an unrelated bar fills up.
	fish.position = player_sprite.position + _combat_direction * _combat.line_distance
	fish.rotation = sin(_time * 5.0) * (0.14 if _combat.phase == DivingCombat.Phase.WINDUP else 0.05)

# The tether itself is the tension display. Stagger has no permanent
# visual meter yet; future fish animations will communicate accumulated strain.
func _update_net_tension() -> void:
	_net.set_line_state(
		_combat.tension if _combat.is_active() else 0.0,
		_combat.is_active() and _combat.phase == DivingCombat.Phase.STUN
	)


func _on_combat_parried(_result: StringName) -> void:
	_update_net_tension()


func _on_combat_finished(won: bool, fish: DivingWildFish) -> void:
	# Release the physical net as soon as the encounter resolves; it must
	# never remain attached to a caught, escaped, or deleted fish.
	_net.reset_net()
	if fish == null or not is_instance_valid(fish):
		_update_net_tension()
		return
	fish.rotation = 0.0
	if fish == _silas_rescue_target:
		# This is a rescue, not an inventory catch or the old fish-to-human
		# transformation. Only reeling Silas all the way in frees him.
		if won:
			_net_cleared = true
			_silas_rescue_target = null
			_wild_fish.erase(fish)
			_silas_wait_position = player_sprite.position + Vector2(24, 9)
			silas_sprite.position = _silas_wait_position
			silas_sprite.show()
			fish.queue_free()
			_net_flash_point = _silas_wait_position
			_net_flash_time = 0.4
			_start_dialogue("Silas", [
				"You got me out! I thought I'd be stuck there forever...",
				"I'm Silas, by the way. Thank you for helping me.",
				"Could I swim with you? I want to see what's out there."
			], &"start_following")
		else:
			# On a failed rescue he remains trapped and can be hooked again.
			fish.position = _silas_burrow + Vector2(0, -16)
			fish.catch_cooldown = 1.0
			_toast("He's still stuck. Try throwing your net again!")
		_update_net_tension()
		return
	if won:
		_caught[fish.fish_name] = int(_caught.get(fish.fish_name, 0)) + 1
		var resource: FishData = _get_fish_data(fish.fish_name)
		if resource != null:
			FishingManager.catch_fish(resource)
		_net_flash_point = fish.position
		_net_flash_time = 0.4
		_toast("Caught %s!  (%d caught)" % [fish.get_display_name(), _total_catches()])
		_wild_fish.erase(fish)
		fish.queue_free()
	else:
		# The fish escapes alive and can be pursued again after a moment.
		fish.position += _combat_direction * 23.0
		fish.catch_cooldown = 1.5
		_toast("The %s got away!" % fish.get_display_name())
	_update_net_tension()


func _draw_combat_telegraph() -> void:
	var fish: DivingWildFish = _combat.target
	if fish == null or not is_instance_valid(fish):
		return
	# The latched NetProjectile draws the actual tether in the world.
	var center: Vector2 = fish.position
	match _combat.phase:
		DivingCombat.Phase.WARNING:
			draw_arc(center, 23.0, 0.0, TAU, 32, Color(0.75, 0.91, 0.95, 0.36), 1.5)
		DivingCombat.Phase.WINDUP:
			draw_arc(center, 23.0, -PI / 2, -PI / 2 + TAU * _combat.telegraph_fraction(), 32, Color(1.0, 0.72, 0.28, 0.95), 2.7)
			draw_arc(center, 26.0, 0.0, TAU, 32, Color(0.96, 0.61, 0.27, 0.25), 1.0)
		DivingCombat.Phase.ATTACK:
			draw_arc(center, 25.0, 0.0, TAU, 32, Color(1.0, 0.29, 0.25, 0.9), 2.6)
		DivingCombat.Phase.STUN:
			draw_arc(center, 22.0 + sin(_time * 10.0) * 2.0, 0.0, TAU, 32, Color(0.98, 0.92, 0.43, 0.85), 2.0)
		DivingCombat.Phase.RECOVERY:
			draw_arc(center, 23.0, 0.0, TAU, 32, Color(0.38, 0.82, 0.78, 0.55), 1.4)
		DivingCombat.Phase.DASH:
			draw_arc(center, 25.0, 0.0, TAU, 32, Color(0.90, 0.34, 0.27, 0.7), 1.4)


func _ask_silas_to_hide() -> void:
	if _combat.is_active():
		return
	if not _underwater or not _silas_following:
		_toast("You need a companion to hide with.")
		return
	if _veil_cooldown > 0.0:
		_toast("Silas needs a moment before hiding again.")
		return
	_veil_time = 5.0
	_veil_cooldown = 10.0
	_toast("Silas stirs up a veil of sand. Fish won't notice you so easily!")

# ---- Companion auto-battle ------------------------------------------------

func _fish_under_cursor(world_mouse: Vector2) -> DivingWildFish:
	var best: DivingWildFish = null
	var best_distance: float = INF
	for fish in _wild_fish:
		if not is_instance_valid(fish) or fish.trapped or fish == _silas_rescue_target:
			continue
		var distance: float = world_mouse.distance_to(fish.position)
		if distance <= fish.capture_radius + 7.0 and distance < best_distance:
			best = fish
			best_distance = distance
	return best


func _command_battle(world_mouse: Vector2) -> void:
	var fish: DivingWildFish = _fish_under_cursor(world_mouse)
	if fish != null and fish == _battle.target:
		_recall_silas()
		return
	if fish == null:
		if _battle.is_active():
			_recall_silas()
		else:
			_toast("Right-click a fish to send Silas at it.")
		return
	if not _silas_following:
		_toast("You need a companion to fight with.")
		return
	if not _battle.can_fight():
		_toast("Silas is too tired to fight. Rest first.")
		return
	if player_sprite.position.distance_to(fish.position) > BATTLE_RANGE:
		_toast("That fish is too far away.")
		return
	var data: FishData = _get_fish_data(fish.fish_name)
	if data == null:
		return
	if _battle.start(fish, data):
		_toast("Silas attacks the %s! Right-click it again or press F to call him back." % fish.get_display_name().to_lower())


func _recall_silas() -> void:
	if not _battle.is_active():
		return
	_battle.stop()
	_toast("Silas swims back to you.")


func _on_battle_hit(on_fish: bool, _damage: float) -> void:
	if on_fish:
		_silas_lunge = 0.15
	else:
		silas_sprite.modulate = Color(1.0, 0.55, 0.5)
		get_tree().create_timer(0.12).timeout.connect(func() -> void:
			if is_instance_valid(silas_sprite):
				silas_sprite.modulate = Color.WHITE)


func _on_battle_fish_knocked_out(fish: DivingWildFish) -> void:
	# Pushed too far: the fish is lost for this session, never stored.
	_wild_fish.erase(fish)
	_toast("The %s was knocked out and drifted away..." % fish.get_display_name().to_lower())
	var fade := fish.create_tween()
	fade.tween_property(fish, "modulate:a", 0.0, 0.6)
	fade.parallel().tween_property(fish, "position:y", fish.position.y - 10.0, 0.6)
	fade.tween_callback(fish.queue_free)


func _on_battle_companion_knocked_out() -> void:
	_toast("Silas is exhausted! He can't fight again until you rest.")


func _try_surface() -> void:
	if _combat.is_active():
		return
	if not _silas_following:
		_return_to_surface(false)
		return
	if _silas_ashore:
		_return_to_surface(true)
		return
	if _silas_talks < 2:
		_start_dialogue("Silas", [
			"Already heading up?",
			"I think I'll stay in the water for now.",
			"Maybe we could talk a little more next time?"
		], &"shore_alone")
		return
	_start_dialogue("Silas", [
		"The surface is right there...",
		"I've never been brave enough to leave the sea.",
		"But... I think I want to see it with you."
	], &"surface_invitation")


func _go_shore(with_silas: bool) -> void:
	_dialogue_event = &""
	_surface_choice = &""
	_underwater = false
	_set_dialogue_visual_mode(false)
	_set_camera_bounds(false)
	player_sprite.position = Vector2(135, 112)
	player_sprite.rotation = 0.0
	for fish in _wild_fish:
		if is_instance_valid(fish):
			fish.hide()
	if with_silas:
		_silas_ashore = true
		_set_silas_human_sprite()
		silas_sprite.position = Vector2(175, 110)
		_net_flash_time = 0.8
		_net_flash_point = silas_sprite.position
		_start_dialogue("Silas", [
			"Wait—what happened to my fins?!",
			"I have... legs? I can actually stand here?",
			"It's so bright. I didn't think the world could be this bright.",
			"Thank you for asking me to come with you."
		])
		_shore_transformation_played = true
	else:
		silas_sprite.hide()
		_toast("Back on shore. Press E at the right-hand dock to dive again.")

func _go_underwater() -> void:
	_dialogue_event = &""
	_surface_choice = &""
	_underwater = true
	_set_dialogue_visual_mode(true)
	_set_camera_bounds(true)
	if _embedded_in_world:
		(player_sprite as Player).set_swimming(true, _sea_bounds())
	else:
		player_sprite.position = _entry_point
		camera.position = player_sprite.position
		camera.reset_smoothing()
	_set_silas_fish_sprite()
	if _silas_following:
		silas_sprite.position = player_sprite.position + Vector2(-26, 14)
	else:
		silas_sprite.position = _silas_burrow + Vector2(0, -16)
	for fish in _wild_fish:
		if is_instance_valid(fish):
			fish.show()
	_toast("Back underwater. WASD to swim. Left click to use your net.")

func _set_camera_bounds(in_sea: bool) -> void:
	if _embedded_in_world and not in_sea:
		camera.limit_left = -10000000
		camera.limit_top = -10000000
		camera.limit_right = 10000000
		camera.limit_bottom = 10000000
	else:
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = roundi(_level_guide.map_size.x) if in_sea else 320
		camera.limit_bottom = roundi(_level_guide.map_size.y) if in_sea else 180

# This is a lightweight wrapper around the REAL DialogueManager; its normal
# DialogueUI now renders every underwater conversation and interactive choice.
func _start_dialogue(speaker: String, lines: Array[String], next_event: StringName = &"") -> void:
	if DialogueManager.is_active or lines.is_empty():
		return
	_dialogue_event = next_event
	_surface_choice = &""
	var choices: Array[Dictionary] = []
	if next_event == &"surface_invitation":
		choices.append({
			"text": "Come with me!",
			"spoken_text": "I'd like you to come with me!",
			"response": "Okay... I'll try. I want to see it with you.",
			"diving_surface": "invite"
		})
		choices.append({
			"text": "Not yet. We can stay a little longer.",
			"spoken_text": "You don't have to come up yet.",
			"response": "That's okay. I'd like to keep swimming together.",
			"diving_surface": "stay"
		})
	DialogueManager.request_inline_conversation(
		SILAS_NPC, lines, "???" if speaker == "???" else "", choices
	)


func _on_diving_choice_resolved(npc: NPCData, choice: Dictionary) -> void:
	if npc != SILAS_NPC or not _underwater:
		return
	_surface_choice = StringName(str(choice.get("diving_surface", "")))


func _on_diving_conversation_finished(npc: NPCData) -> void:
	if npc != SILAS_NPC:
		return
	var event: StringName = _dialogue_event
	_dialogue_event = &""
	match event:
		&"silas_rescue_ready":
			_make_silas_catchable()
		&"start_following":
			_silas_following = true
			_toast("Silas is swimming with you! Press Q to use his concealment.")
		&"shore_alone":
			_return_to_surface(false)
		&"surface_invitation":
			if _surface_choice == &"invite":
				_return_to_surface(true)
	_surface_choice = &""

func _make_silas_catchable() -> void:
	if not _silas_met or _net_cleared or is_instance_valid(_silas_rescue_target):
		return
	# A dedicated stationary fish actor, using Silas's existing FishData and
	# eel sprite. Its only purpose is the physical net-and-parry rescue.
	var rescue: DivingWildFish = WILD_FISH_SCRIPT.new() as DivingWildFish
	rescue.setup(
		SILAS_FISH_DATA.fish_id,
		SILAS_FISH,
		_silas_burrow + Vector2(0, -16),
		_sea_bounds(),
		2606
	)
	rescue.trapped = true
	rescue.capture_radius = 15.0
	add_child(rescue)
	_silas_rescue_target = rescue
	_wild_fish.append(rescue)
	silas_sprite.hide()
	_toast("Aim your net at the trapped eel and reel him free!")


func _total_catches() -> int:
	var count := 0
	for amount in _caught.values():
		count += int(amount)
	return count

func _toast(value: String) -> void:
	toast_label.text = value
	_toast_time = 3.0
	toast_label.show()

func _update_hud() -> void:
	location_label.text = "THE SHALLOWS" if _underwater else "BACK ON SHORE"
	catch_label.text = "NET CATCHES  %d" % _total_catches()
	if _underwater:
		if not _silas_met:
			story_label.text = "There's a voice somewhere to the east..."
		elif not _net_cleared:
			story_label.text = "Cast your net at the trapped eel and reel him free."
		elif not _silas_following:
			story_label.text = "Talk to Silas."
		elif _silas_talks < 2:
			story_label.text = "Explore and talk with Silas before leaving."
		else:
			story_label.text = "Silas seems curious about the surface..."
		var near_surface: bool = player_sprite.position.distance_to(_surface_point) < REACH
		var near_silas: bool = player_sprite.position.distance_to(silas_sprite.position) < REACH
		var near_trapped_eel: bool = _silas_met and not _net_cleared and player_sprite.position.distance_to(_silas_burrow) < REACH + 22.0
		if _battle.is_active():
			prompt_label.text = "SILAS IS FIGHTING  |  RIGHT-CLICK / F  CALL HIM BACK  |  CLICK NET"
		elif near_surface:
			prompt_label.text = "[E]  RETURN TO SURFACE"
		elif near_trapped_eel:
			prompt_label.text = "CLICK  CAST NET AT EEL  |  [E] TALK"
		elif near_silas:
			prompt_label.text = "[E] TALK TO SILAS"
		elif _silas_following:
			prompt_label.text = "WASD MOVE  |  CLICK NET  |  RIGHT-CLICK SILAS FIGHTS  |  Q HIDE"
		else:
			prompt_label.text = "WASD MOVE  |  CLICK TO CAST NET  |  Q SILAS HIDES"
	else:
		story_label.text = "A new world to discover together." if _silas_ashore else "The water is waiting."
		if player_sprite.position.distance_to(SHORE_DIVE_POINT) < REACH:
			prompt_label.text = "[E]  DIVE BACK IN"
		else:
			prompt_label.text = "WASD MOVE  |  SWIM AGAIN AT THE RIGHT DOCK"

func _draw() -> void:
	if _embedded_in_world or _underwater:
		_draw_underwater()
		if _underwater and _combat.is_active():
			_draw_combat_telegraph()
		if _underwater and _silas_following and silas_sprite.visible and (
			_battle.is_active() or _battle.health < _battle.stats.max_health
		):
			DivingCompanionBattle.draw_health_bar(
				self, silas_sprite.position + Vector2(0.0, -12.0), _battle.health_ratio()
			)
	else:
		_draw_shore()

func _draw_shore() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color("#a7c6cf"))
	draw_rect(Rect2(0, 48, 320, 72), Color("#dce8d3"))
	draw_rect(Rect2(0, 119, 250, 61), Color("#d3b990"))
	draw_rect(Rect2(245, 73, 75, 107), Color("#518ea7"))
	draw_rect(Rect2(248, 82, 72, 98), Color("#417d99"))
	draw_circle(Vector2(48, 31), 20, Color("#f6d79d"))
	for i in range(8):
		draw_line(Vector2(253, 90 + i * 12), Vector2(320, 91 + i * 12), Color(0.75, 0.88, 0.86, 0.24), 1)
	draw_rect(Rect2(60, 104, 215, 14), Color("#624d49"))
	draw_rect(Rect2(60, 102, 215, 6), Color("#94745a"))
	for x in range(68, 270, 20):
		draw_line(Vector2(x, 102), Vector2(x, 116), Color("#493b40"), 1)
	for x in [81, 135, 188, 241]:
		draw_rect(Rect2(x, 114, 4, 35), Color("#645050"))
	draw_rect(Rect2(76, 90, 29, 13), Color("#577575"))
	draw_rect(Rect2(71, 86, 39, 6), Color("#a7a184"))
	draw_circle(SHORE_DIVE_POINT + Vector2(0, -16), 7, Color(0.85, 0.95, 0.84, 0.38))
	if _silas_ashore and _net_flash_time > 0.0:
		draw_arc(_net_flash_point, (1.0 - _net_flash_time / 0.8) * 30.0 + 6.0, 0.0, TAU, 32, Color(1.0, 0.95, 0.74, _net_flash_time / 0.8), 1.6)

func _draw_underwater() -> void:
	var sea_size: Vector2 = _level_guide.map_size
	if not _embedded_in_world:
		draw_rect(Rect2(Vector2.ZERO, sea_size), Color("#143c58"))
	if show_prototype_environment:
		for i in range(14):
			var y: float = float(i) * 37.0
			draw_rect(Rect2(0, y, sea_size.x, 38.0), Color(0.08, 0.28 + float(i) * 0.003, 0.39, 0.10))
		for i in range(22):
			var top: Vector2 = Vector2(float(i * 52 - 80), 0.0)
			draw_line(top, top + Vector2(165, 425), Color(0.53, 0.78, 0.79, 0.035), 8.0)
		draw_rect(Rect2(0, 462, sea_size.x, 68), Color("#897b66"))
		draw_rect(Rect2(0, 460, sea_size.x, 6), Color("#b3a38a"))
		for i in range(92):
			var pebble := Vector2(float((i * 127 + 15) % 910), float(468 + (i * 23) % 58))
			draw_circle(pebble, float(1 + (i % 3)), Color("#756f65"))
		# Coral gardens and waving eelgrass are placed in the space you swim through.
		for i in range(26):
			var bx: float = 18.0 + float((i * 67 + 29) % 880)
			var by: float = 460.0 - float((i * 19) % 55)
			var sway: float = sin(_time * 1.5 + float(i)) * 4.0
			draw_line(Vector2(bx, by + 14), Vector2(bx + sway, by - 20 - float(i % 4) * 5.0), Color("#3b937d"), 2.0)
			draw_line(Vector2(bx, by), Vector2(bx - 5 + sway, by - 13), Color("#5dab86"), 1.0)
		for reef_center in [Vector2(240, 365), Vector2(520, 415), Vector2(780, 420)]:
			draw_circle(reef_center, 39, Color("#345d6a"))
			draw_circle(reef_center + Vector2(-13, 1), 21, Color("#547178"))
			draw_circle(reef_center + Vector2(16, -9), 17, Color("#466b73"))
			for i in range(7):
				var branch: Vector2 = Vector2(reef_center) + Vector2(-20 + i * 7, 7.0)
				draw_line(branch, branch + Vector2(sin(_time + i) * 3, -15 - i % 3 * 4), Color("#ce897e"), 2)
	# The starting surface entrance has a distinct safe pool of light.
	draw_circle(_surface_point, 25.0, Color(0.61, 0.87, 0.88, 0.09))
	draw_arc(_surface_point, 21.0, 0.0, TAU, 28, Color(0.62, 0.91, 0.88, 0.46), 1.5)
	draw_line(_surface_point + Vector2(-6, 7), _surface_point + Vector2(0, -7), Color("#ddf4dc"), 1.4)
	draw_line(_surface_point + Vector2(0, -7), _surface_point + Vector2(6, 7), Color("#ddf4dc"), 1.4)
	# Silas's burrow with the knot of abandoned line snagged over it.
	draw_circle(_silas_burrow, 28.0, Color("#485e63"))
	draw_circle(_silas_burrow + Vector2(0, -1), 15.0, Color("#193544"))
	draw_arc(_silas_burrow, 17.0, 0.0, PI, 16, Color("#a69f88"), 2.0)
	if not _net_cleared:
		for i in range(4):
			var p: Vector2 = _tangled_net + Vector2(-10 + i * 6, -14)
			draw_line(p, p + Vector2(9 - i * 3, 26), Color("#d3bfa6"), 1)
		draw_line(_tangled_net + Vector2(-12, 0), _tangled_net + Vector2(11, 5), Color("#d3bfa6"), 1)
		draw_circle(_tangled_net + Vector2(0, -24), 3.0 + sin(_time * 3.0), Color("#edb98b"))
	if not _silas_met:
		draw_circle(_silas_burrow + Vector2(0, -44 + sin(_time * 2.0) * 2.0), 3.0, Color("#f1d5a4"))
	# A distant glowing shell garden gives the player something to show Silas.
	for i in range(10):
		var a: float = TAU * float(i) / 10.0
		var shell_position: Vector2 = _glowing_garden + Vector2(cos(a) * 36, sin(a) * 24)
		var pulse: float = 0.34 + 0.22 * sin(_time * 2 + float(i))
		draw_circle(shell_position, 7.0, Color(0.4, 0.89, 0.9, pulse * 0.5))
		draw_circle(shell_position, 2.5, Color(0.64, 0.95, 0.86, pulse))
	for i in range(58):
		var x: float = float((i * 179 + 61) % 920)
		var y: float = fposmod(float((i * 117 + 17) % 500) - _time * (5.0 + float(i % 5)), 500.0)
		draw_circle(Vector2(x, y), 0.6 + float(i % 3) * 0.4, Color(0.58, 0.85, 0.87, 0.16))
	if _veil_time > 0.0 and _silas_following:
		var alpha: float = minf(_veil_time / 0.8, 1.0)
		draw_circle(player_sprite.position, 27.0 + sin(_time * 4) * 2.0, Color(0.59, 0.77, 0.71, 0.13 * alpha))
		draw_arc(player_sprite.position, 27.0, 0.0, TAU, 32, Color(0.76, 0.87, 0.78, 0.5 * alpha), 1.2)
	if _net_flash_time > 0.0:
		var life: float = _net_flash_time / 0.36
		draw_arc(_net_flash_point, (1.0 - life) * 18.0 + 5.0, 0.0, TAU, 24, Color(0.88, 0.98, 0.88, life), 1.2)
