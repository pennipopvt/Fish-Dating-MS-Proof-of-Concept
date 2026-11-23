class_name NPCTemporaryActor
extends RefCounted

# Shared, non-interactive land presentation for dates, dock returns, and
# cutscenes. Real recruited NPCs have no persistent island actor.
# Scene paths live on NPCData as strings to avoid circular PackedScene loads.

static func create(npc: NPCData, override_scene: PackedScene = null) -> Node2D:
	if npc == null:
		return null
	var scene: PackedScene = override_scene
	if scene == null and not npc.land_actor_scene_path.is_empty():
		scene = load(npc.land_actor_scene_path) as PackedScene
	if scene != null:
		var actor: Node2D = scene.instantiate() as Node2D
		if actor != null:
			_make_noninteractive(actor)
			return actor
	# Keep story scenes functional if a future NPC has no land actor yet.
	var sprite := Sprite2D.new()
	sprite.texture = npc.portrait
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if sprite.texture != null:
		sprite.scale = Vector2.ONE * (30.0 / maxf(float(sprite.texture.get_width()), 1.0))
	return sprite


static func spawn(npc: NPCData, parent: Node, feet_at: Vector2,
		override_scene: PackedScene = null) -> Node2D:
	if parent == null:
		return null
	var actor: Node2D = create(npc, override_scene)
	if actor == null:
		return null
	actor.z_index = 6
	parent.add_child(actor)
	place_feet(actor, feet_at)
	return actor


# Marker locations are feet coordinates, not actor origins or sprite centers.
static func place_feet(actor: Node2D, feet_at: Vector2) -> void:
	if actor == null:
		return
	actor.global_position = feet_at
	var art: AnimatedSprite2D = actor.get_node_or_null("Sprite") as AnimatedSprite2D
	if art != null and art.sprite_frames != null:
		var frame: Texture2D = art.sprite_frames.get_frame_texture(art.animation, art.frame)
		if frame != null and art.centered:
			actor.global_position.y = feet_at.y - art.position.y - frame.get_height() * 0.5 * art.scale.y
	elif actor is Sprite2D:
		var sprite: Sprite2D = actor as Sprite2D
		if sprite.texture != null and sprite.centered:
			actor.global_position.y = feet_at.y - sprite.texture.get_height() * sprite.scale.y * 0.5


static func _make_noninteractive(actor: Node2D) -> void:
	if actor is Area2D:
		var area: Area2D = actor as Area2D
		area.monitoring = false
		area.monitorable = false
		area.collision_layer = 0
		area.collision_mask = 0
	var collision: CollisionShape2D = actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		collision.disabled = true
	var prompt: InteractPrompt = actor.get_node_or_null("InteractPrompt") as InteractPrompt
	if prompt != null:
		prompt.hide()
