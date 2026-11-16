extends SceneTree

# godot --headless --path . -s res://tests/kuda_art_bindings_test.gd
# Guard against old, deleted barracuda art paths being reintroduced.

const KUDA_SCENE: PackedScene = preload("res://prefabs/kuda.tscn")
const KUDA_DATA: NPCData = preload("res://resources/npcs/kuda.tres")
const KUDA_IDLE: Texture2D = preload("res://sprites/characters/kuda_idle.png")
const KUDA_PORTRAIT: Texture2D = preload("res://sprites/characters/kuda_portrait.png")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(KUDA_DATA.display_name == "Kuda", "NPC still displays the name Kuda")
	_expect(KUDA_DATA.portrait == KUDA_PORTRAIT, "Dialogue uses the new Kuda portrait")
	var actor := KUDA_SCENE.instantiate()
	_expect(actor is NPCInteractable, "Kuda scene instantiates as an interactable NPC")
	if actor is NPCInteractable:
		_expect(actor.npc == KUDA_DATA, "Kuda world scene points to the same NPC data")
	var sprite := actor.get_node_or_null("Sprite") as AnimatedSprite2D
	_expect(sprite != null, "Kuda has an animated world sprite")
	if sprite != null and sprite.sprite_frames != null:
		for animation in [&"default", &"on_caught"]:
			_expect(sprite.sprite_frames.has_animation(animation),
				"Animation %s exists" % animation)
			if not sprite.sprite_frames.has_animation(animation):
				continue
			var frame_count := sprite.sprite_frames.get_frame_count(animation)
			_expect(frame_count > 0, "Animation %s has frames" % animation)
			for i in frame_count:
				var texture := sprite.sprite_frames.get_frame_texture(animation, i)
				var atlas := texture as AtlasTexture
				_expect(atlas != null and atlas.atlas == KUDA_IDLE,
					"Animation %s frame %d uses kuda_idle.png" % [animation, i])
	actor.free()
	print("kuda_art_bindings_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(0 if failures == 0 else 1)


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("  ok   ", description)
	else:
		failures += 1
		push_error("  FAIL " + description)
