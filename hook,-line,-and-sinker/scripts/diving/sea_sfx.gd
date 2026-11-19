extends Node

# Sound effects for the sea (diving). One slot per event; set them on
# prefabs/sea_sfx.tscn in the Inspector. An empty slot stays silent, so a
# sound can be added later without touching code. DivingWorld and
# SeaDiveTransition call play() / set_swimming().

@export_group("Diving")
@export var dive: AudioStream  # Penni splashes into the water
@export var surface: AudioStream  # Penni climbs back out at the dock
@export var swim: AudioStream  # repeats while Penni is swimming
@export_group("Net Fight")
@export var hook: AudioStream  # the net latches onto a fish
@export var windup: AudioStream  # the fish winds up an attack
@export var attack: AudioStream  # the fish attacks
@export var counter: AudioStream  # perfect or close parry
@export var reel: AudioStream  # each reel scroll
@export var catch: AudioStream  # fish caught
@export var lose: AudioStream  # fish escaped
@export_group("Companion Battle")
@export var battle_hit: AudioStream  # Silas or the fish lands a hit
@export_group("Mix")
@export_range(-30.0, 6.0, 0.5) var volume_db: float = 0.0
@export_range(-30.0, 6.0, 0.5) var reel_volume_db: float = -6.0
@export_range(-30.0, 6.0, 0.5) var swim_volume_db: float = -10.0

const EVENTS: Array[StringName] = [
	&"dive", &"surface", &"swim", &"hook", &"windup", &"attack",
	&"counter", &"reel", &"catch", &"lose", &"battle_hit",
]

var _players: Dictionary = {}  # StringName -> AudioStreamPlayer
var _swimming: bool = false


func _ready() -> void:
	for event in EVENTS:
		var player := AudioStreamPlayer.new()
		player.name = String(event).capitalize().replace(" ", "") + "Sfx"
		player.stream = get(event) as AudioStream
		player.volume_db = volume_db
		add_child(player)
		_players[event] = player
	(_players[&"reel"] as AudioStreamPlayer).volume_db = reel_volume_db
	(_players[&"reel"] as AudioStreamPlayer).max_polyphony = 6
	var swim_player: AudioStreamPlayer = _players[&"swim"]
	swim_player.volume_db = swim_volume_db
	swim_player.finished.connect(_on_swim_finished)


func play(event: StringName) -> void:
	var player: AudioStreamPlayer = _players.get(event)
	if player == null or player.stream == null:
		return
	player.play()


# The swim sound repeats while Penni moves underwater and stops when she
# stops, whether or not the stream itself is set to loop.
func set_swimming(moving: bool) -> void:
	if moving == _swimming:
		return
	_swimming = moving
	var player: AudioStreamPlayer = _players[&"swim"]
	if player.stream == null:
		return
	if moving:
		player.play()
	else:
		player.stop()


func _on_swim_finished() -> void:
	if _swimming:
		(_players[&"swim"] as AudioStreamPlayer).play()
