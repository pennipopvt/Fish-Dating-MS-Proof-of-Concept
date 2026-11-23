extends Node2D

# Decorative background fish for the dive: shrunken, greyed silhouettes of
# the real fish sprites drifting far behind the play layer. Purely visual:
# no collision, no catching, nothing else reads them.
#
# Each shadow lives in its own parallax depth. Farther shadows are smaller,
# fainter and slower, and move less when the camera moves. Shadows wrap
# around the camera's view, so the same few sprites fill the whole sea.
# They sit below the terrain (z_index -3 in the scene, behind the Background Terrain at -2), so rocks cover them.

const SILHOUETTE_SHADER: Shader = preload("res://shaders/fish_catalog_silhouette.gdshader")

## Fish whose sprites are used for the shadows.
## (FishData resources; typed as Resource so the scene file stays simple.)
@export var species: Array[Resource] = []
## Lone fish on screen at once.
@export var single_count: int = 6
## Small schools on screen at once, and how many fish each has.
@export var school_count: int = 2
@export var school_size_range: Vector2i = Vector2i(3, 5)
## Shadow length in pixels for the nearest and farthest depth
## (real fish in the sea are 20px long).
@export var near_width: float = 14.0
@export var far_width: float = 7.0
## School fish are drawn this much smaller than lone fish.
@export var school_width_scale: float = 0.7
## Opacity for the nearest and farthest depth.
@export var near_alpha: float = 0.32
@export var far_alpha: float = 0.14
## How much a shadow follows the camera: 0 = moves like the play layer,
## 1 = stuck to the screen. Higher reads as farther away.
@export var near_parallax: float = 0.35
@export var far_parallax: float = 0.75
## Swim speed in pixels per second at the nearest depth.
@export var swim_speed_range: Vector2 = Vector2(5.0, 11.0)
@export var silhouette_color: Color = Color(0.17, 0.22, 0.26, 1.0)
## Shadows fade out within this many pixels of the water surface and floor.
@export var edge_fade: float = 24.0
## Sea surface y in this node's parent space (DivingWorld.SEA_TOP).
@export var surface_y: float = 154.0
## Bottom of the sea in parent space. 0 = read from the sibling EditorGuide.
@export var floor_y: float = 0.0
## Extra space around the view where shadows can wrap unseen.
@export var wrap_margin: float = 40.0
@export var random_seed: int = 4242

## Extra rotation (degrees, clockwise) per fish_id, for sprites drawn tilted.
## Only the shadows rotate; the real sprite files are untouched.
@export var tilt_by_fish: Dictionary = {&"goby": 45.0}

var _rng := RandomNumberGenerator.new()
var _texture_tilt: Dictionary = {}
var _groups: Array[Dictionary] = []
var _material: ShaderMaterial


func _ready() -> void:
	_rng.seed = random_seed
	if floor_y <= 0.0:
		var guide: Node = get_parent().get_node_or_null("EditorGuide")
		if guide != null and "map_origin" in guide and "map_size" in guide:
			var origin: Vector2 = guide.get("map_origin")
			var size: Vector2 = guide.get("map_size")
			floor_y = origin.y + size.y
		else:
			floor_y = surface_y + 600.0
	_material = ShaderMaterial.new()
	_material.shader = SILHOUETTE_SHADER
	_material.set_shader_parameter("silhouette_color", silhouette_color)
	var textures: Array[Texture2D] = _usable_textures()
	if textures.is_empty():
		return
	for i in single_count:
		_add_group(textures, 1)
	for i in school_count:
		_add_group(textures, _rng.randi_range(school_size_range.x, school_size_range.y))


func _process(delta: float) -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null or _groups.is_empty():
		return
	# Work in parent space so the node's own transform never matters.
	var cam: Vector2 = get_parent().to_local(camera.get_screen_center_position()) \
			if get_parent() is Node2D else camera.get_screen_center_position()
	var view: Vector2 = get_viewport_rect().size / camera.zoom.abs()
	var box: Vector2 = view + Vector2.ONE * wrap_margin * 2.0
	for group in _groups:
		var heading: float = group.heading
		var layer_pos: Vector2 = group.layer_pos
		layer_pos.x += heading * group.speed * delta
		group.time += delta
		var follow: float = group.parallax
		# Where the group would be drawn this frame, then wrap it around the
		# view so it re-enters from the other side once it is off screen.
		var world_pos: Vector2 = layer_pos + cam * follow
		var rel: Vector2 = world_pos - cam
		rel.x = wrapf(rel.x, -box.x * 0.5, box.x * 0.5)
		rel.y = wrapf(rel.y, -box.y * 0.5, box.y * 0.5)
		world_pos = cam + rel
		layer_pos = world_pos - cam * follow
		group.layer_pos = layer_pos
		for member in group.members:
			var sprite: Sprite2D = member.sprite
			var bob: float = sin(group.time * member.bob_speed + member.phase) * 1.5
			var pos: Vector2 = world_pos + member.offset + Vector2(0.0, bob)
			# Round the offset from the screen center, not the world position,
			# so shadows sit on the screen's pixel grid while the camera is
			# between pixels (no 1px flicker while it settles).
			sprite.position = cam + (pos - cam).round() - position
			sprite.flip_h = heading < 0.0
			# Mirror the tilt too, so a flipped fish leans the same way.
			sprite.rotation = deg_to_rad(member.tilt) * (-1.0 if sprite.flip_h else 1.0)
			sprite.modulate.a = group.alpha * _edge_fade(pos.y)


func _usable_textures() -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for resource in species:
		var data: FishData = resource as FishData
		if data != null and data.item_data != null and data.item_data.sprite != null:
			result.append(data.item_data.sprite)
			_texture_tilt[data.item_data.sprite] = _tilt_for(data.fish_id)
	return result


# Keys typed in the Inspector may be String or StringName; match either.
func _tilt_for(fish_id: StringName) -> float:
	for key in tilt_by_fish:
		if String(key) == String(fish_id):
			return float(tilt_by_fish[key])
	return 0.0


func _add_group(textures: Array[Texture2D], size: int) -> void:
	var depth: float = _rng.randf()
	var group: Dictionary = {
		"heading": 1.0 if _rng.randf() < 0.5 else -1.0,
		"speed": lerpf(swim_speed_range.x, swim_speed_range.y, _rng.randf())
				* lerpf(1.0, 0.5, depth),
		"parallax": lerpf(near_parallax, far_parallax, depth),
		"alpha": lerpf(near_alpha, far_alpha, depth),
		# Random start spread over a view-sized box around the origin; the
		# first frame wraps it around the camera.
		"layer_pos": Vector2(_rng.randf_range(-200.0, 200.0), _rng.randf_range(-120.0, 120.0)),
		"time": _rng.randf_range(0.0, 10.0),
		"members": [],
	}
	var texture: Texture2D = textures[_rng.randi() % textures.size()]
	var width: float = lerpf(near_width, far_width, depth)
	if size > 1:
		width *= school_width_scale
	for i in size:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.material = _material
		sprite.scale = Vector2.ONE * (width / maxf(float(texture.get_width()), 1.0))
		add_child(sprite)
		var offset := Vector2.ZERO
		if size > 1:
			offset = Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-7.0, 7.0))
		group.members.append({
			"sprite": sprite,
			"offset": offset,
			"phase": _rng.randf_range(0.0, TAU),
			"bob_speed": _rng.randf_range(1.2, 2.2),
			"tilt": float(_texture_tilt.get(texture, 0.0)),
		})
	_groups.append(group)


func _edge_fade(y: float) -> float:
	var from_top: float = (y - surface_y) / maxf(edge_fade, 1.0)
	var from_floor: float = (floor_y - y) / maxf(edge_fade, 1.0)
	return clampf(minf(from_top, from_floor), 0.0, 1.0)
