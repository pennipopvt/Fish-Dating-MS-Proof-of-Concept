extends Node2D
class_name DivingWorld

signal surface_requested(with_silas: bool)

# Self-contained diving vertical slice. The original dock/fishing/romance
# systems remain on this branch for comparison; this is an alternate main scene.
# All distances are in the 320x180 game's small pixel-world coordinates.
const WILD_FISH_SCRIPT = preload("res://scripts/diving/wild_fish.gd")
const PLAYER_IDLE: Texture2D = preload("res://sprites/characters/penni/penni_idle.png")
const SILAS_FISH: Texture2D = preload("res://sprites/fish/silas_eel.png")
const SILAS_HUMAN: Texture2D = preload("res://sprites/characters/silas_idle.png")
const FISH_MULLET: Texture2D = preload("res://sprites/fish/mullet.png")
const FISH_PORGY: Texture2D = preload("res://sprites/fish/porgy.png")
const FISH_GOBY: Texture2D = preload("res://sprites/fish/goby.png")
const FISH_FLOUNDER: Texture2D = preload("res://sprites/fish/flounder.png")
const FISH_NEEDLE: Texture2D = preload("res://sprites/fish/needlefish.png")
const FISH_TUNA: Texture2D = preload("res://sprites/fish/tuna.png")
const PIXEL_FONT: Font = preload("res://fonts/pixel_operator(1)/PixelOperator.ttf")

const SEA_SIZE := Vector2(920.0, 530.0)
const SEA_BOUNDS := Rect2(Vector2(16.0, 30.0), Vector2(888.0, 460.0))
const SURFACE_POINT := Vector2(78.0, 92.0)
const SILAS_BURROW := Vector2(385.0, 258.0)
const TANGLED_NET := Vector2(411.0, 250.0)
const GLOWING_GARDEN := Vector2(670.0, 213.0)
const SHORE_DIVE_POINT := Vector2(251.0, 111.0)
const SWIM_SPEED: float = 78.0
const REACH: float = 44.0

@onready var camera: Camera2D = $Camera2D
@onready var player_sprite: Sprite2D = $Player
@onready var silas_sprite: Sprite2D = $Silas
@onready var location_label: Label = $CanvasLayer/HUD/Location
@onready var catch_label: Label = $CanvasLayer/HUD/CatchCount
@onready var story_label: Label = $CanvasLayer/HUD/StoryHint
@onready var prompt_label: Label = $CanvasLayer/HUD/Prompt
@onready var toast_label: Label = $CanvasLayer/HUD/Toast
@onready var dialogue_panel: Panel = $CanvasLayer/HUD/DialoguePanel
@onready var dialogue_name: Label = $CanvasLayer/HUD/DialoguePanel/Speaker
@onready var dialogue_text: Label = $CanvasLayer/HUD/DialoguePanel/Words
@onready var dialogue_next: Label = $CanvasLayer/HUD/DialoguePanel/Continue

var _embedded_in_world: bool = false
var _underwater: bool = true
var _silas_met: bool = false
var _net_cleared: bool = false
var _silas_following: bool = false
var _silas_talks: int = 0
var _silas_ashore: bool = false
var _discovered_garden: bool = false
var _wild_fish: Array[DivingWildFish] = []
var _caught: Dictionary[StringName, int] = {}
var _time: float = 0.0
var _veil_time: float = 0.0
var _veil_cooldown: float = 0.0
var _talk_cooldown: float = 0.0
var _net_flash_time: float = 0.0
var _net_flash_point: Vector2 = Vector2.ZERO
var _toast_time: float = 0.0
var _dialogue_lines: Array[String] = []
var _dialogue_index: int = 0
var _dialogue_event: StringName = &""
var _dialogue_active: bool = false
var _choice_active: bool = false
var _shore_transformation_played: bool = false

func _ready() -> void:
	player_sprite.position = Vector2(122.0, 123.0)
	player_sprite.texture = PLAYER_IDLE
	player_sprite.hframes = 2
	player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	player_sprite.scale = Vector2(0.78, 0.78)
	silas_sprite.position = SILAS_BURROW + Vector2(0, -16)
	silas_sprite.texture = SILAS_FISH
	silas_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_set_silas_fish_sprite()
	camera.position = player_sprite.position
	_set_camera_bounds(true)
	dialogue_panel.hide()
	_make_ui_pixels()
	_spawn_fish()
	_update_hud()
	_toast("A voice somewhere in the reef...")

# When used by scenes/main.tscn, the existing dock is the land scene.
# This underwater instance stays alive between dives, preserving Silas's
# conversations, his decision to follow, and ordinary fish already caught.
func set_embedded_mode(value: bool) -> void:
	_embedded_in_world = value


func enter_from_dock() -> void:
	_go_underwater()


func _return_to_surface(with_silas: bool) -> void:
	if _embedded_in_world:
		_dialogue_active = false
		_choice_active = false
		dialogue_panel.hide()
		surface_requested.emit(with_silas)
	else:
		_go_shore(with_silas)


func _make_ui_pixels() -> void:
	var all_labels: Array[Label] = [
		location_label, catch_label, story_label, prompt_label,
		toast_label, dialogue_name, dialogue_text, dialogue_next
	]
	for label in all_labels:
		label.add_theme_font_override("font", PIXEL_FONT)
	location_label.add_theme_font_size_override("font_size", 12)
	catch_label.add_theme_font_size_override("font_size", 10)
	story_label.add_theme_font_size_override("font_size", 9)
	prompt_label.add_theme_font_size_override("font_size", 10)
	toast_label.add_theme_font_size_override("font_size", 10)
	dialogue_name.add_theme_font_size_override("font_size", 11)
	dialogue_text.add_theme_font_size_override("font_size", 10)
	dialogue_next.add_theme_font_size_override("font_size", 8)

func _set_silas_fish_sprite() -> void:
	silas_sprite.texture = SILAS_FISH
	var width: float = float(SILAS_FISH.get_width())
	silas_sprite.scale = Vector2.ONE * (18.0 / maxf(width, 1.0))
	silas_sprite.rotation = 0.0
	silas_sprite.visible = true

func _set_silas_human_sprite() -> void:
	var frame := AtlasTexture.new()
	frame.atlas = SILAS_HUMAN
	frame.region = Rect2(0, 0, 32, 32)
	silas_sprite.texture = frame
	silas_sprite.scale = Vector2.ONE
	silas_sprite.rotation = 0.0
	silas_sprite.visible = true

func _spawn_fish() -> void:
	var fish_specs: Array[Dictionary] = [
		{"id": &"mullet", "tex": FISH_MULLET, "pos": Vector2(208, 138)},
		{"id": &"porgy", "tex": FISH_PORGY, "pos": Vector2(278, 197)},
		{"id": &"goby", "tex": FISH_GOBY, "pos": Vector2(320, 314)},
		{"id": &"mullet", "tex": FISH_MULLET, "pos": Vector2(476, 149)},
		{"id": &"flounder", "tex": FISH_FLOUNDER, "pos": Vector2(543, 356)},
		{"id": &"needlefish", "tex": FISH_NEEDLE, "pos": Vector2(600, 155)},
		{"id": &"porgy", "tex": FISH_PORGY, "pos": Vector2(758, 309)},
		{"id": &"tuna", "tex": FISH_TUNA, "pos": Vector2(814, 180)}
	]
	for i in range(fish_specs.size()):
		var spec: Dictionary = fish_specs[i]
		var fish: DivingWildFish = WILD_FISH_SCRIPT.new() as DivingWildFish
		var kind: StringName = spec["id"]
		var art: Texture2D = spec["tex"]
		var start: Vector2 = spec["pos"]
		fish.setup(kind, art, start, SEA_BOUNDS, 2041 + i * 37)
		add_child(fish)
		_wild_fish.append(fish)

func _process(delta: float) -> void:
	_time += delta
	_veil_time = maxf(0.0, _veil_time - delta)
	_veil_cooldown = maxf(0.0, _veil_cooldown - delta)
	_talk_cooldown = maxf(0.0, _talk_cooldown - delta)
	_toast_time = maxf(0.0, _toast_time - delta)
	_net_flash_time = maxf(0.0, _net_flash_time - delta)
	toast_label.visible = _toast_time > 0.0 and not _dialogue_active

	if not _dialogue_active:
		_move_player(delta)

	if _underwater:
		for fish in _wild_fish:
			if is_instance_valid(fish):
				fish.swim(delta, player_sprite.position, _veil_time > 0.0)
		_update_silas_fish(delta)
		_maybe_discover_garden()
		camera.position = camera.position.lerp(player_sprite.position, minf(delta * 5.5, 1.0))
	else:
		camera.position = camera.position.lerp(Vector2(160, 90), minf(delta * 7.0, 1.0))
		if _silas_ashore:
			silas_sprite.position.y = 110.0 + sin(_time * 1.7) * 0.45

	player_sprite.frame = int(_time * 3.2) % 2
	_update_hud()
	queue_redraw()

func _move_player(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
	var speed: float = SWIM_SPEED if _underwater else 64.0
	if _underwater and _veil_time > 0.0:
		speed *= 0.82
	player_sprite.position += direction * speed * delta
	if _underwater:
		player_sprite.position.x = clampf(player_sprite.position.x, SEA_BOUNDS.position.x + 8.0, SEA_BOUNDS.end.x - 8.0)
		player_sprite.position.y = clampf(player_sprite.position.y, SEA_BOUNDS.position.y + 8.0, SEA_BOUNDS.end.y - 8.0)
		player_sprite.rotation = lerpf(player_sprite.rotation, direction.x * 0.11, minf(delta * 6.0, 1.0))
		player_sprite.position.y += sin(_time * 2.6) * delta * 1.2
	else:
		player_sprite.position.x = clampf(player_sprite.position.x, 38.0, 280.0)
		player_sprite.position.y = clampf(player_sprite.position.y, 76.0, 148.0)
		player_sprite.rotation = 0.0
	if direction.x < -0.05:
		player_sprite.flip_h = true
	elif direction.x > 0.05:
		player_sprite.flip_h = false

func _update_silas_fish(delta: float) -> void:
	silas_sprite.visible = true
	if not _silas_following:
		silas_sprite.position = SILAS_BURROW + Vector2(sin(_time * 1.7) * 1.7, -16.0 + sin(_time * 2.3) * 1.4)
		silas_sprite.flip_h = false
		return
	# Keep Silas physically near the player but give him a little room to
	# explore, catch up, and glide naturally instead of snapping to a socket.
	var offset := Vector2(-23.0 if not player_sprite.flip_h else 23.0, 12.0 + sin(_time * 1.7) * 4.0)
	var target: Vector2 = player_sprite.position + offset
	var distance: float = silas_sprite.position.distance_to(target)
	var max_speed: float = 114.0 if distance > 95.0 else 67.0
	var before: Vector2 = silas_sprite.position
	if distance > 9.0:
		silas_sprite.position = silas_sprite.position.move_toward(target, max_speed * delta)
	else:
		silas_sprite.position.y += sin(_time * 2.0) * delta
	silas_sprite.flip_h = silas_sprite.position.x < before.x - 0.01
	silas_sprite.rotation = sin(_time * 3.0) * 0.07

func _maybe_discover_garden() -> void:
	if _discovered_garden or not _silas_following or _dialogue_active:
		return
	if player_sprite.position.distance_to(GLOWING_GARDEN) < 45.0:
		_discovered_garden = true
		_start_dialogue("Silas", [
			"Wait... look at the light coming from those shells.",
			"I've lived down here forever, and I've never seen this place.",
			"I'm glad I came swimming with you."
		])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _dialogue_active:
			if _choice_active:
				if event.keycode == KEY_1 or event.keycode == KEY_KP_1:
					_choose_surface(true)
					get_viewport().set_input_as_handled()
				elif event.keycode == KEY_2 or event.keycode == KEY_KP_2:
					_choose_surface(false)
					get_viewport().set_input_as_handled()
			elif event.keycode in [KEY_E, KEY_SPACE, KEY_ENTER]:
				_advance_dialogue()
				get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_E or event.keycode == KEY_SPACE:
			_interact()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Q:
			_ask_silas_to_hide()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _underwater and not _dialogue_active:
			_try_catch(get_global_mouse_position())
			get_viewport().set_input_as_handled()

func _interact() -> void:
	if not _underwater:
		if player_sprite.position.distance_to(SHORE_DIVE_POINT) < REACH:
			_go_underwater()
		else:
			_toast("The ocean is to the right. Swim again at the dock.")
		return
	if player_sprite.position.distance_to(SURFACE_POINT) < REACH:
		_try_surface()
		return
	if player_sprite.position.distance_to(silas_sprite.position) < REACH:
		_talk_to_silas()
		return
	_toast("Swim near Silas or the surface marker, then press E.")

func _talk_to_silas() -> void:
	if _talk_cooldown > 0.0:
		_toast("Give him a moment.")
		return
	_talk_cooldown = 0.9
	if not _silas_met:
		_silas_met = true
		_start_dialogue("???", [
			"Um... excuse me? You can really hear me?",
			"I didn't think anyone from the surface could understand fish.",
			"There's a discarded net tangled around my burrow...",
			"Could you clear it? Get close and click the tangled net."
		])
		return
	if not _net_cleared:
		_start_dialogue("???", [
			"I can't get far with that net across my burrow.",
			"Try clicking on the knot beside me when you're nearby."
		])
		return
	if not _silas_following:
		_start_dialogue("Silas", [
			"I've never really explored away from my burrow.",
			"Do you mind if I tag along?"
		], &"start_following")
		return
	_silas_talks += 1
	match _silas_talks:
		1:
			_start_dialogue("Silas", [
				"I usually just watch everything from the sand.",
				"Swimming with someone is... different. Good different.",
				"You can ask me to hide us with Q, if another fish gets nervous."
			])
		2:
			_start_dialogue("Silas", [
				"Are the stars really like the little lights down here?",
				"I can see the surface from my burrow, but I've never gone up.",
				"Maybe I'd like to... if you were there."
			])
		3:
			_start_dialogue("Silas", [
				"You keep showing me things I never would've looked for.",
				"If you go back soon... could I see the surface with you?"
			])
		_:
			var extra: Array[String] = [
				"There's a whole world up there, isn't there?",
				"Sorry, I think I'm following you too closely. I'll give you some room.",
				"I like this. Just swimming somewhere together.",
				"I didn't know the reef could feel so big."
			]
			_start_dialogue("Silas", [extra[(_silas_talks - 4) % extra.size()]])

func _try_catch(world_mouse: Vector2) -> void:
	_net_flash_point = world_mouse
	_net_flash_time = 0.36
	if not _net_cleared and world_mouse.distance_to(TANGLED_NET) < 22.0:
		if player_sprite.position.distance_to(TANGLED_NET) > REACH:
			_toast("Get a little closer to the tangled net.")
			return
		if not _silas_met:
			# Preserve the talking-fish reveal as the first encounter beat.
			_talk_to_silas()
			return
		_net_cleared = true
		_start_dialogue("Silas", [
			"Oh! You got it loose!",
			"I... I'm Silas, by the way.",
			"Would it be alright if I swam with you for a while?"
		], &"start_following")
		return
	for i in range(_wild_fish.size() - 1, -1, -1):
		var fish: DivingWildFish = _wild_fish[i]
		if not is_instance_valid(fish):
			_wild_fish.remove_at(i)
			continue
		if fish.is_targeted(world_mouse, player_sprite.position):
			_caught[fish.fish_name] = int(_caught.get(fish.fish_name, 0)) + 1
			# Feed the normal world's storage, collection and challenges, too.
			# The GameManager dive flag prevents each net catch from consuming
			# another action while the player is still underwater.
			for data in FishingManager.possible_catches:
				if data != null and data.fish_id == fish.fish_name:
					FishingManager.catch_fish(data)
					break
			_net_flash_point = fish.position
			_toast("Caught a %s!  (%d caught)" % [fish.get_display_name(), _total_catches()])
			_wild_fish.remove_at(i)
			fish.queue_free()
			return
	# A near miss is useful feedback. Clicking from across the world should
	# never teleport a fish into your inventory.
	var closest: float = INF
	for fish in _wild_fish:
		if is_instance_valid(fish):
			closest = minf(closest, fish.position.distance_to(world_mouse))
	if closest < 22.0:
		_toast("Get closer before casting the net.")

func _ask_silas_to_hide() -> void:
	if not _underwater or not _silas_following:
		_toast("You need a companion to hide with.")
		return
	if _veil_cooldown > 0.0:
		_toast("Silas needs a moment before hiding again.")
		return
	_veil_time = 5.0
	_veil_cooldown = 10.0
	_toast("Silas stirs up a veil of sand. Fish won't notice you so easily!")

func _try_surface() -> void:
	if not _silas_following:
		_return_to_surface(false)
		return
	if _silas_ashore:
		_return_to_surface(true)
		return
	if _silas_talks < 2:
		_start_dialogue("Silas", [
			"Already heading up?",
			"I think I'll stay in the water for now.",
			"Maybe we could talk a little more next time?"
		], &"shore_alone")
		return
	_start_dialogue("Silas", [
		"The surface is right there...",
		"I've never been brave enough to leave the sea.",
		"But... I think I want to see it with you."
	], &"surface_invitation")

func _choose_surface(invite: bool) -> void:
	_choice_active = false
	_dialogue_active = false
	dialogue_panel.hide()
	if invite:
		_return_to_surface(true)
	else:
		_start_dialogue("Silas", ["That's okay. I'll keep swimming with you."])

func _go_shore(with_silas: bool) -> void:
	_dialogue_active = false
	_choice_active = false
	dialogue_panel.hide()
	_underwater = false
	_set_camera_bounds(false)
	player_sprite.position = Vector2(135, 112)
	player_sprite.rotation = 0.0
	for fish in _wild_fish:
		if is_instance_valid(fish):
			fish.hide()
	if with_silas:
		_silas_ashore = true
		_set_silas_human_sprite()
		silas_sprite.position = Vector2(175, 110)
		_net_flash_time = 0.8
		_net_flash_point = silas_sprite.position
		_start_dialogue("Silas", [
			"Wait—what happened to my fins?!",
			"I have... legs? I can actually stand here?",
			"It's so bright. I didn't think the world could be this bright.",
			"Thank you for asking me to come with you."
		])
		_shore_transformation_played = true
	else:
		silas_sprite.hide()
		_toast("Back on shore. Press E at the right-hand dock to dive again.")

func _go_underwater() -> void:
	_dialogue_active = false
	dialogue_panel.hide()
	_underwater = true
	_set_camera_bounds(true)
	player_sprite.position = SURFACE_POINT + Vector2(42.0, 29.0)
	camera.position = player_sprite.position
	camera.reset_smoothing()
	_set_silas_fish_sprite()
	if _silas_following:
		silas_sprite.position = player_sprite.position + Vector2(-26, 14)
	else:
		silas_sprite.position = SILAS_BURROW + Vector2(0, -16)
	for fish in _wild_fish:
		if is_instance_valid(fish):
			fish.show()
	_toast("Back underwater. WASD to swim. Left click to use your net.")

func _set_camera_bounds(in_sea: bool) -> void:
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(SEA_SIZE.x) if in_sea else 320
	camera.limit_bottom = int(SEA_SIZE.y) if in_sea else 180

func _start_dialogue(speaker: String, lines: Array[String], next_event: StringName = &"") -> void:
	_dialogue_active = true
	_choice_active = false
	_dialogue_lines = lines
	_dialogue_index = 0
	_dialogue_event = next_event
	dialogue_name.text = speaker.to_upper()
	dialogue_text.text = lines[0] if not lines.is_empty() else ""
	dialogue_next.text = "E / SPACE  CONTINUE"
	dialogue_panel.show()

func _advance_dialogue() -> void:
	if _dialogue_index + 1 < _dialogue_lines.size():
		_dialogue_index += 1
		dialogue_text.text = _dialogue_lines[_dialogue_index]
		return
	var event: StringName = _dialogue_event
	_dialogue_active = false
	dialogue_panel.hide()
	_dialogue_event = &""
	match event:
		&"start_following":
			_silas_following = true
			_toast("Silas is swimming with you! Press Q to use his concealment.")
		&"shore_alone":
			_return_to_surface(false)
		&"surface_invitation":
			_choice_active = true
			_dialogue_active = true
			dialogue_name.text = "YOUR ANSWER"
			dialogue_text.text = "Invite Silas to see the surface?"
			dialogue_next.text = "1  COME WITH ME         2  NOT YET"
			dialogue_panel.show()

func _total_catches() -> int:
	var count := 0
	for amount in _caught.values():
		count += int(amount)
	return count

func _toast(value: String) -> void:
	toast_label.text = value
	_toast_time = 3.0
	toast_label.show()

func _update_hud() -> void:
	location_label.text = "THE SHALLOWS" if _underwater else "BACK ON SHORE"
	catch_label.text = "NET CATCHES  %d" % _total_catches()
	if _underwater:
		if not _silas_met:
			story_label.text = "There's a voice somewhere to the east..."
		elif not _net_cleared:
			story_label.text = "Help the talking eel. Click the tangled net."
		elif not _silas_following:
			story_label.text = "Talk to Silas."
		elif _silas_talks < 2:
			story_label.text = "Explore and talk with Silas before leaving."
		else:
			story_label.text = "Silas seems curious about the surface..."
		var near_surface: bool = player_sprite.position.distance_to(SURFACE_POINT) < REACH
		var near_silas: bool = player_sprite.position.distance_to(silas_sprite.position) < REACH
		var near_net: bool = not _net_cleared and player_sprite.position.distance_to(TANGLED_NET) < REACH
		if near_surface:
			prompt_label.text = "[E]  RETURN TO SURFACE"
		elif near_net:
			prompt_label.text = "LEFT CLICK  CLEAR NET  |  [E] TALK"
		elif near_silas:
			prompt_label.text = "[E] TALK TO SILAS"
		else:
			prompt_label.text = "WASD MOVE  |  CLICK NET FISH  |  Q SILAS HIDES"
	else:
		story_label.text = "A new world to discover together." if _silas_ashore else "The water is waiting."
		if player_sprite.position.distance_to(SHORE_DIVE_POINT) < REACH:
			prompt_label.text = "[E]  DIVE BACK IN"
		else:
			prompt_label.text = "WASD MOVE  |  SWIM AGAIN AT THE RIGHT DOCK"

func _draw() -> void:
	if not _underwater:
		_draw_shore()
	else:
		_draw_underwater()

func _draw_shore() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color("#a7c6cf"))
	draw_rect(Rect2(0, 48, 320, 72), Color("#dce8d3"))
	draw_rect(Rect2(0, 119, 250, 61), Color("#d3b990"))
	draw_rect(Rect2(245, 73, 75, 107), Color("#518ea7"))
	draw_rect(Rect2(248, 82, 72, 98), Color("#417d99"))
	draw_circle(Vector2(48, 31), 20, Color("#f6d79d"))
	for i in range(8):
		draw_line(Vector2(253, 90 + i * 12), Vector2(320, 91 + i * 12), Color(0.75, 0.88, 0.86, 0.24), 1)
	draw_rect(Rect2(60, 104, 215, 14), Color("#624d49"))
	draw_rect(Rect2(60, 102, 215, 6), Color("#94745a"))
	for x in range(68, 270, 20):
		draw_line(Vector2(x, 102), Vector2(x, 116), Color("#493b40"), 1)
	for x in [81, 135, 188, 241]:
		draw_rect(Rect2(x, 114, 4, 35), Color("#645050"))
	draw_rect(Rect2(76, 90, 29, 13), Color("#577575"))
	draw_rect(Rect2(71, 86, 39, 6), Color("#a7a184"))
	draw_circle(SHORE_DIVE_POINT + Vector2(0, -16), 7, Color(0.85, 0.95, 0.84, 0.38))
	if _silas_ashore and _net_flash_time > 0.0:
		draw_arc(_net_flash_point, (1.0 - _net_flash_time / 0.8) * 30.0 + 6.0, 0.0, TAU, 32, Color(1.0, 0.95, 0.74, _net_flash_time / 0.8), 1.6)

func _draw_underwater() -> void:
	draw_rect(Rect2(Vector2.ZERO, SEA_SIZE), Color("#143c58"))
	for i in range(14):
		var y: float = float(i) * 37.0
		draw_rect(Rect2(0, y, SEA_SIZE.x, 38.0), Color(0.08, 0.28 + float(i) * 0.003, 0.39, 0.10))
	for i in range(22):
		var top: Vector2 = Vector2(float(i * 52 - 80), 0.0)
		draw_line(top, top + Vector2(165, 425), Color(0.53, 0.78, 0.79, 0.035), 8.0)
	draw_rect(Rect2(0, 462, SEA_SIZE.x, 68), Color("#897b66"))
	draw_rect(Rect2(0, 460, SEA_SIZE.x, 6), Color("#b3a38a"))
	for i in range(92):
		var pebble := Vector2(float((i * 127 + 15) % 910), float(468 + (i * 23) % 58))
		draw_circle(pebble, float(1 + (i % 3)), Color("#756f65"))
	# Coral gardens and waving eelgrass are placed in the space you swim through.
	for i in range(26):
		var bx: float = 18.0 + float((i * 67 + 29) % 880)
		var by: float = 460.0 - float((i * 19) % 55)
		var sway: float = sin(_time * 1.5 + float(i)) * 4.0
		draw_line(Vector2(bx, by + 14), Vector2(bx + sway, by - 20 - float(i % 4) * 5.0), Color("#3b937d"), 2.0)
		draw_line(Vector2(bx, by), Vector2(bx - 5 + sway, by - 13), Color("#5dab86"), 1.0)
	for reef_center in [Vector2(240, 365), Vector2(520, 415), Vector2(780, 420)]:
		draw_circle(reef_center, 39, Color("#345d6a"))
		draw_circle(reef_center + Vector2(-13, 1), 21, Color("#547178"))
		draw_circle(reef_center + Vector2(16, -9), 17, Color("#466b73"))
		for i in range(7):
			var branch := reef_center + Vector2(-20 + i * 7, 7.0)
			draw_line(branch, branch + Vector2(sin(_time + i) * 3, -15 - i % 3 * 4), Color("#ce897e"), 2)
	# The starting surface entrance has a distinct safe pool of light.
	draw_circle(SURFACE_POINT, 25.0, Color(0.61, 0.87, 0.88, 0.09))
	draw_arc(SURFACE_POINT, 21.0, 0.0, TAU, 28, Color(0.62, 0.91, 0.88, 0.46), 1.5)
	draw_line(SURFACE_POINT + Vector2(-6, 7), SURFACE_POINT + Vector2(0, -7), Color("#ddf4dc"), 1.4)
	draw_line(SURFACE_POINT + Vector2(0, -7), SURFACE_POINT + Vector2(6, 7), Color("#ddf4dc"), 1.4)
	# Silas's burrow with the knot of abandoned line snagged over it.
	draw_circle(SILAS_BURROW, 28.0, Color("#485e63"))
	draw_circle(SILAS_BURROW + Vector2(0, -1), 15.0, Color("#193544"))
	draw_arc(SILAS_BURROW, 17.0, 0.0, PI, 16, Color("#a69f88"), 2.0)
	if not _net_cleared:
		for i in range(4):
			var p: Vector2 = TANGLED_NET + Vector2(-10 + i * 6, -14)
			draw_line(p, p + Vector2(9 - i * 3, 26), Color("#d3bfa6"), 1)
		draw_line(TANGLED_NET + Vector2(-12, 0), TANGLED_NET + Vector2(11, 5), Color("#d3bfa6"), 1)
		draw_circle(TANGLED_NET + Vector2(0, -24), 3.0 + sin(_time * 3.0), Color("#edb98b"))
	if not _silas_met:
		draw_circle(SILAS_BURROW + Vector2(0, -44 + sin(_time * 2.0) * 2.0), 3.0, Color("#f1d5a4"))
	# A distant glowing shell garden gives the player something to show Silas.
	for i in range(10):
		var a: float = TAU * float(i) / 10.0
		var shell_position: Vector2 = GLOWING_GARDEN + Vector2(cos(a) * 36, sin(a) * 24)
		var pulse: float = 0.34 + 0.22 * sin(_time * 2 + float(i))
		draw_circle(shell_position, 7.0, Color(0.4, 0.89, 0.9, pulse * 0.5))
		draw_circle(shell_position, 2.5, Color(0.64, 0.95, 0.86, pulse))
	for i in range(58):
		var x: float = float((i * 179 + 61) % 920)
		var y: float = fposmod(float((i * 117 + 17) % 500) - _time * (5.0 + float(i % 5)), 500.0)
		draw_circle(Vector2(x, y), 0.6 + float(i % 3) * 0.4, Color(0.58, 0.85, 0.87, 0.16))
	if _veil_time > 0.0 and _silas_following:
		var alpha: float = minf(_veil_time / 0.8, 1.0)
		draw_circle(player_sprite.position, 27.0 + sin(_time * 4) * 2.0, Color(0.59, 0.77, 0.71, 0.13 * alpha))
		draw_arc(player_sprite.position, 27.0, 0.0, TAU, 32, Color(0.76, 0.87, 0.78, 0.5 * alpha), 1.2)
	if _net_flash_time > 0.0:
		var life: float = _net_flash_time / 0.36
		draw_arc(_net_flash_point, (1.0 - life) * 18.0 + 5.0, 0.0, TAU, 24, Color(0.88, 0.98, 0.88, life), 1.2)
