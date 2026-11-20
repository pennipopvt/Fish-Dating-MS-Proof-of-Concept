extends Node
class_name SeaPartyEntrance

# Dive presentation only: ephemeral dock actors -> jumps -> poofs -> fish.
# This deliberately knows nothing about townhouses, housing, or dates.
const SILAS_SCENE: PackedScene = preload("res://prefabs/silas.tscn")
const KUDA_SCENE: PackedScene = preload("res://prefabs/kuda.tscn")
@export_range(0.1, 1.0, 0.05) var fade_seconds: float = 0.32
@export_range(0.2, 1.0, 0.05) var jump_seconds: float = 0.46
@export_range(0.0, 0.5, 0.05) var jump_stagger_seconds: float = 0.14
@export_range(0.0, 60.0, 1.0) var jump_arc_height: float = 24.0

var _world: Node2D
var _player: Player
var _land_scenes: Dictionary = {&"test_npc": SILAS_SCENE, &"barracuda": KUDA_SCENE}
var _staged: Array[Dictionary] = []
var _fish_visuals: Array[Sprite2D] = []


func configure(world: Node2D, player: Player) -> void:
	_world = world
	_player = player


# Register additional NPC art directly with the diving system, not housing.
func register_land_scene(npc_id: StringName, scene: PackedScene) -> void:
	_land_scenes[npc_id] = scene


# Called by SeaDiveTransition immediately after dock dive confirmation.
func call_party_to_dock(party: Array[NPCData], dock: Node2D) -> void:
	clear()
	if party.is_empty():
		return
	var fade := ScreenFade.new()
	get_tree().root.add_child(fade)
	await fade.fade_to(1.0, fade_seconds)
	_player.global_position = dock.global_position + Vector2(21.0, 11.0)
	_player.animator.play(&"idle_l")
	var camera: Camera2D = _player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	for i in range(party.size()):
		var npc: NPCData = party[i]
		var actor: Node2D = _make_actor(npc)
		actor.name = "DiveGuest_" + String(npc.npc_id)
		_world.add_child(actor)
		actor.global_position = dock.global_position + Vector2(42.0 + 24.0 * i, 11.0)
		_align_feet(actor, dock.global_position.y + 11.0)
		_staged.append({"npc": npc, "actor": actor, "index": i})
	await fade.fade_to(0.0, fade_seconds)
	fade.queue_free()


func _make_actor(npc: NPCData) -> Node2D:
	var scene: PackedScene = _land_scenes.get(npc.npc_id) as PackedScene
	if scene != null:
		var actor: Node2D = scene.instantiate() as Node2D
		if actor != null:
			if actor is Area2D:
				(actor as Area2D).monitoring = false
				(actor as Area2D).monitorable = false
				(actor as Area2D).collision_layer = 0
				(actor as Area2D).collision_mask = 0
			var collision: CollisionShape2D = actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if collision != null:
				collision.disabled = true
			var prompt: InteractPrompt = actor.get_node_or_null("InteractPrompt") as InteractPrompt
			if prompt != null:
				prompt.hide()
			return actor
	# If new NPC art isn't ready, the portrait is a visible temporary fallback.
	var sprite := Sprite2D.new()
	sprite.texture = npc.portrait
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if sprite.texture != null:
		sprite.scale = Vector2.ONE * (30.0 / maxf(float(sprite.texture.get_width()), 1.0))
	return sprite


func _align_feet(actor: Node2D, ground_y: float) -> void:
	var art: AnimatedSprite2D = actor.get_node_or_null("Sprite") as AnimatedSprite2D
	if art != null and art.sprite_frames != null:
		var frame: Texture2D = art.sprite_frames.get_frame_texture(art.animation, art.frame)
		if frame != null and art.centered:
			actor.global_position.y = ground_y - art.position.y - frame.get_height() * 0.5 * art.scale.y
	elif actor is Sprite2D:
		var image: Sprite2D = actor as Sprite2D
		if image.texture != null and image.centered:
			actor.global_position.y = ground_y - image.texture.get_height() * image.scale.y * 0.5


# Guests jump after Penni; each temporary human actor disappears at the poof.
func jump_party_in(dock: Node2D, splash: Callable) -> void:
	for info in _staged:
		var actor: Node2D = info["actor"] as Node2D
		if not is_instance_valid(actor):
			continue
		var i: int = int(info["index"])
		var start: Vector2 = actor.global_position
		var landing: Vector2 = Vector2(dock.global_position.x - 6.0 - i * 8.0, dock.global_position.y + 46.0)
		var jump: Tween = create_tween()
		jump.tween_method(_move_jump.bind(actor, start, landing),
			0.0, 1.0, jump_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await jump.finished
		splash.call(landing)
		var poof: AnimatedSprite2D = SeaPoofEffect.spawn(_world, landing)
		actor.hide()
		var npc: NPCData = info["npc"] as NPCData
		if npc != null and npc.underwater_sprite != null:
			var fish := Sprite2D.new()
			fish.name = "DiveFish_" + String(npc.npc_id)
			fish.texture = npc.underwater_sprite
			fish.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			fish.z_index = 6
			fish.scale = Vector2.ONE * (24.0 / maxf(float(fish.texture.get_width()), 1.0))
			_world.add_child(fish)
			fish.global_position = landing
			_fish_visuals.append(fish)
		await get_tree().create_timer(jump_stagger_seconds).timeout
		poof.queue_free()
		actor.queue_free()
	_staged.clear()


func _move_jump(t: float, actor: Node2D, start: Vector2, landing: Vector2) -> void:
	if is_instance_valid(actor):
		actor.global_position = start.lerp(landing, t) + Vector2(0.0, -jump_arc_height * sin(PI * t))


func descend_with_player(entry: Vector2, duration: float) -> void:
	for i in range(_fish_visuals.size()):
		var fish: Sprite2D = _fish_visuals[i]
		var movement: Tween = create_tween()
		movement.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		movement.tween_property(fish, "global_position",
			entry + Vector2(-20.0 - 18.0 * i, 8.0 + 7.0 * i), duration)


func clear() -> void:
	for info in _staged:
		var actor: Node2D = info.get("actor") as Node2D
		if is_instance_valid(actor):
			actor.queue_free()
	_staged.clear()
	for fish in _fish_visuals:
		if is_instance_valid(fish):
			fish.queue_free()
	_fish_visuals.clear()
