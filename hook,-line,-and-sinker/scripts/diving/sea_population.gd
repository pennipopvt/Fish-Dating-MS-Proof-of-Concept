extends Node
class_name SeaPopulation

# World keeps ownership of fish actors/registry. This component chooses
# species and valid positions only; it doesn't move or fight fish.
signal spawn_requested(species: FishData, sea_position: Vector2, seed_value: int,
	region: SeaSpawnRegion)

@export_range(12, 250, 1) var attempts_per_fish: int = 100
# Native game pixels beyond ALL four sides of the camera view.
@export_range(0.0, 160.0, 1.0) var offscreen_margin: float = 36.0
@export var generation_seed: int = 37027

@onready var _regions: Node2D = $"../SpawnRegions"
var _generated: bool = false
var _rng := RandomNumberGenerator.new()


func has_generated() -> bool:
	return _generated


func generate_after_tutorial(camera: Camera2D, sea_bounds: Rect2,
		water_is_clear: Callable, existing_positions: Array[Vector2]) -> void:
	if _generated or camera == null or not water_is_clear.is_valid():
		return
	_generated = true
	_rng.seed = generation_seed
	var visible_size: Vector2 = camera.get_viewport_rect().size / camera.zoom.abs()
	var center: Vector2 = camera.get_screen_center_position()
	var visible: Rect2 = Rect2(center - visible_size * 0.5, visible_size)
	visible = visible.grow(offscreen_margin)
	var occupied: Array[Vector2] = existing_positions.duplicate()
	var world: Node2D = get_parent() as Node2D
	var period: int = GameManager.get_period()
	for region_node in _regions.get_children():
		var region: SeaSpawnRegion = region_node as SeaSpawnRegion
		if region == null or region.population_count <= 0:
			continue
		var count: int = 0
		# Guaranteed habitat minima happen before the weighted remainder.
		for option in region.species_options:
			if option == null or option.species == null:
				continue
			for i in range(option.minimum_count):
				if count >= region.population_count:
					break
				if _try_spawn(option.species, region, world, visible, sea_bounds,
						water_is_clear, occupied):
					count += 1
		while count < region.population_count:
			var choice: SeaSpawnOption = _pick_option(region.species_options, period)
			if choice == null or not _try_spawn(choice.species, region, world,
						visible, sea_bounds, water_is_clear, occupied):
				# No clear/offscreen space left: never teleport fish into view.
				break
			count += 1


func _pick_option(options: Array[SeaSpawnOption], period: int) -> SeaSpawnOption:
	var total: float = 0.0
	for option in options:
		if option != null and option.species != null:
			total += option.effective_weight(period)
	if total <= 0.0:
		return null
	var value: float = _rng.randf() * total
	for option in options:
		if option == null or option.species == null:
			continue
		value -= option.effective_weight(period)
		if value <= 0.0:
			return option
	return options.back()


func _try_spawn(species: FishData, region: SeaSpawnRegion, world: Node2D,
		visible: Rect2, sea_bounds: Rect2, water_is_clear: Callable,
		occupied: Array[Vector2]) -> bool:
	if species == null or species.item_data == null or species.item_data.sprite == null:
		return false
	for attempt in range(attempts_per_fish):
		var local: Vector2 = Vector2(
			_rng.randf_range(10.0, region.region_size.x - 10.0),
			_rng.randf_range(10.0, region.region_size.y - 10.0)
		)
		var position: Vector2 = world.to_local(region.to_global(local))
		if not sea_bounds.grow(-12.0).has_point(position) or visible.has_point(
			world.to_global(position)):
			continue
		if not bool(water_is_clear.call(position)):
			continue
		var far_enough: bool = true
		for other in occupied:
			if other.distance_to(position) < region.minimum_fish_spacing:
				far_enough = false
				break
		if not far_enough:
			continue
		occupied.append(position)
		spawn_requested.emit(species, position, _rng.randi(), region)
		return true
	push_warning("No valid offscreen water found for %s in habitat %s" %
		[String(species.fish_id), region.name])
	return false
