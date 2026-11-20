extends RefCounted

# Load with preload("res://scripts/ground_gd") (no class_name, so it
# works before the editor rescans), then call build(layer).

# The walkable surface of a ground TileMapLayer, read from the tiles' pixels:
# for every world x column, the y of the topmost opaque pixel. The player
# walks on this, so the walking height follows stairs and the beach slope,
# and the walk border is where drawn ground starts and ends (not where the
# tile cells do; edge tiles are often partly transparent).

const ALPHA_THRESHOLD: float = 0.5

var left: int = 0  # first world x column with ground
var right: int = -1  # last world x column with ground
var _surface: PackedFloat32Array = PackedFloat32Array()


func is_empty() -> bool:
	return right < left


# Surface y (global) at world x, or NAN outside the ground.
func surface_at(x: float) -> float:
	var i: int = floori(x) - left
	if i < 0 or i >= _surface.size():
		return NAN
	return _surface[i]


func build(layer: TileMapLayer) -> void:
	left = 0
	right = -1
	_surface = PackedFloat32Array()
	if layer == null or layer.tile_set == null:
		return
	var tops: Dictionary = {}  # int world x -> float topmost y
	var images: Dictionary = {}  # source id -> Image
	var tile_size: Vector2i = layer.tile_set.tile_size
	for cell in layer.get_used_cells():
		var source_id: int = layer.get_cell_source_id(cell)
		var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or source.texture == null:
			continue
		if not images.has(source_id):
			var image: Image = source.texture.get_image()
			if image != null and image.is_compressed():
				image.decompress()
			images[source_id] = image
		var image: Image = images[source_id]
		if image == null:
			continue
		var region: Rect2i = source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
		var alt: int = layer.get_cell_alternative_tile(cell)
		var flip_h: bool = (alt & TileSetAtlasSource.TRANSFORM_FLIP_H) != 0
		var flip_v: bool = (alt & TileSetAtlasSource.TRANSFORM_FLIP_V) != 0
		var cell_origin: Vector2 = layer.to_global(layer.map_to_local(cell) - Vector2(tile_size) * 0.5)
		for cx in region.size.x:
			var src_x: int = region.position.x + (region.size.x - 1 - cx if flip_h else cx)
			for cy in region.size.y:
				var src_y: int = region.position.y + (region.size.y - 1 - cy if flip_v else cy)
				if image.get_pixel(src_x, src_y).a < ALPHA_THRESHOLD:
					continue
				var wx: int = roundi(cell_origin.x) + cx
				var wy: float = cell_origin.y + float(cy)
				if not tops.has(wx) or wy < tops[wx]:
					tops[wx] = wy
				break
	if tops.is_empty():
		return
	var xs: Array = tops.keys()
	xs.sort()
	left = xs[0]
	right = xs[xs.size() - 1]
	_surface.resize(right - left + 1)
	var last: float = tops[left]
	for x in range(left, right + 1):
		# A gap inside the ground (an empty column) keeps the height before it.
		if tops.has(x):
			last = tops[x]
		_surface[x - left] = last
