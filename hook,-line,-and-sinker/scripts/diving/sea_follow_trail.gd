extends RefCounted
class_name SeaFollowTrail

# A small recorded path of Penni's actual swim, sampled by DivingWorld.
# Every follower reads the SAME trail at a different distance. No new
# manager, movement authority, or NPC-specific positioning logic is needed.
const SAMPLE_DISTANCE: float = 6.0
const TELEPORT_RESET_DISTANCE: float = 240.0
const MAX_SAMPLES: int = 180

var _head: Vector2 = Vector2.ZERO
var _samples: Array[Vector2] = [] # Newest point first.


func reset(at: Vector2) -> void:
	_head = at
	_samples.clear()
	_samples.append(at)


func record(at: Vector2) -> void:
	if _samples.is_empty() or _head.distance_to(at) > TELEPORT_RESET_DISTANCE:
		reset(at)
		return
	_head = at
	if _samples[0].distance_to(at) >= SAMPLE_DISTANCE:
		_samples.push_front(at)
		if _samples.size() > MAX_SAMPLES:
			_samples.resize(MAX_SAMPLES)


# Walk BACK along the actual path (including corners and reversals), not an
# offset based on Penni's current facing. Short new trails extend away from
# her facing direction so companions don't pile on top of her after a dive.
func point_behind(distance: float, facing: Vector2 = Vector2.RIGHT) -> Vector2:
	if _samples.is_empty():
		return Vector2.ZERO
	var remaining: float = maxf(0.0, distance)
	var here: Vector2 = _head
	for anchor in _samples:
		var segment_length: float = here.distance_to(anchor)
		if segment_length > 0.0001:
			if remaining <= segment_length:
				return here.lerp(anchor, remaining / segment_length)
			remaining -= segment_length
		here = anchor
	var direction: Vector2 = facing.normalized() if facing.length_squared() > 0.0001 else Vector2.RIGHT
	return here - direction * remaining
