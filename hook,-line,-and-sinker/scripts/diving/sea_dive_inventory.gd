extends Node
class_name SeaDiveInventory

# Fish caught on an expedition remain carried until Penni returns safely.
# The existing FishingManager storage is the bank, not the dive bag.
# Deposited is the handoff point for a future terminal-pipe animation.
signal carried_changed(count: int)
signal deposited(items: Array[ItemData])
signal lost(items: Array[ItemData])

var _carried: Array[ItemData] = []


func begin_dive() -> void:
	# The previous expedition must have been committed or lost first.
	if not _carried.is_empty():
		push_warning("Unsettled sea catches were cleared when beginning a new dive.")
		_carried.clear()
	carried_changed.emit(0)


func record_fish(fish: FishData) -> void:
	if fish == null or fish.item_data == null:
		return
	_carried.append(fish.item_data)
	carried_changed.emit(_carried.size())


func count_carried() -> int:
	return _carried.size()


func count_species(item_id: StringName) -> int:
	var count: int = 0
	for item in _carried:
		if item != null and item.item_id == item_id:
			count += 1
	return count


func secure_catch() -> int:
	var landed: Array[ItemData] = _carried.duplicate()
	_carried.clear()
	for item in landed:
		FishingManager.add_to_storage(item)
	carried_changed.emit(0)
	# Future polish: animate the landed items traveling into Fish Co.'s pipe.
	deposited.emit(landed)
	return landed.size()


func lose_catch() -> int:
	var dropped: Array[ItemData] = _carried.duplicate()
	_carried.clear()
	carried_changed.emit(0)
	lost.emit(dropped)
	return dropped.size()
