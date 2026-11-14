class_name DateLocation
extends Interactable

# A place dates happen (beach, ship). DateManager finds it by location_id and
# puts Penni at PlayerSpot and the NPC at NpcSpot. Interacting starts a date
# booked here for the current period. The sign shows the next booking.

@export var location_id: StringName
@export var prompt: InteractPrompt

@onready var _player_spot: Marker2D = $PlayerSpot
@onready var _npc_spot: Marker2D = $NpcSpot
@onready var _sign: Label = $Sign

var _player_in_range := false


func _ready() -> void:
	super()
	add_to_group(DateManager.LOCATION_GROUP)
	DateManager.bookings_changed.connect(_refresh)
	GameManager.time_changed.connect(func(_day: int, _period: int) -> void: _refresh())
	_refresh()


func get_player_spot() -> Vector2:
	return _player_spot.global_position


func get_npc_spot() -> Vector2:
	return _npc_spot.global_position


func interact(player: Node2D) -> void:
	if player is Player and player.busy:
		return
	var date := DateManager.get_ready_booking(location_id)
	if date == null:
		print("[Date] Nothing planned at %s right now." % location_id)
		return
	DateManager.start_date(date)


func _on_body_entered(body: Node2D) -> void:
	super(body)
	if body is Player:
		_player_in_range = true
		_refresh()


func _on_body_exited(body: Node2D) -> void:
	super(body)
	if body is Player:
		_player_in_range = false
		_refresh()


func _refresh() -> void:
	var date := DateManager.get_booking_at(location_id)
	_sign.visible = date != null
	if date != null:
		var is_now := DateManager.get_ready_booking(location_id) == date
		_sign.text = "%s\n%s" % [date.display_name, "Now!" if is_now else DateManager.describe_booking(date)]
	if prompt == null:
		return
	if _player_in_range and DateManager.get_ready_booking(location_id) != null:
		prompt.pop_in()
	else:
		prompt.pop_out()
