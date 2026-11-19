extends Node
class_name SeaSpeechBubbleHost

# Owns ONLY the recovery/binding of Main's editable SeaSpeechBubble.
# Keep the instance under Main, outside the sea SubViewport.
var source: String = "uninitialized"
var _main: Control
var _story: SeaStoryDirector


func configure(main: Control, story: SeaStoryDirector) -> void:
	_main = main
	_story = story
	ensure_bubble()


func _bind(bubble: SeaSpeechBubble) -> void:
	if _story != null:
		_story.bind_speech_bubble(bubble)


# Prefer the authored PackedScene. Runtime recovery exists because a
# partially imported scene really lost this instance in earlier builds.
func ensure_bubble() -> SeaSpeechBubble:
	var existing: Node = _main.get_node_or_null("SeaSpeechBubble")
	if existing is SeaSpeechBubble and existing.is_node_ready():
		source = "authored scene"
		_bind(existing as SeaSpeechBubble)
		return existing as SeaSpeechBubble

	if existing != null:
		push_warning("[SEA UI] SeaSpeechBubble exists but is not a ready SeaSpeechBubble (class=%s); rebuilding." % existing.get_class())
		existing.name = "UnusableSeaSpeechBubble"
		existing.queue_free()
	else:
		push_warning("[SEA UI] Main/SeaSpeechBubble is missing; rebuilding it.")

	# First try the exact existing authored PackedScene. This is a runtime
	# load, not an extra scene dependency in Main.
	var resource: PackedScene = load("res://scenes/sea_speech_bubble.tscn") as PackedScene
	if resource != null:
		var node: Node = resource.instantiate()
		if node is SeaSpeechBubble and node.has_node("Call/Frame") and node.has_node("Call/Message") and node.has_node("Call/Tail"):
			node.name = "SeaSpeechBubble"
			_main.add_child(node)
			var result: SeaSpeechBubble = node as SeaSpeechBubble
			if result.is_node_ready():
				source = "recovered PackedScene"
				print("[SEA UI] Recovered original bubble scene under Main.")
				_bind(result)
				return result
			node.name = "UnreadySeaSpeechBubble"
			node.queue_free()
		else:
			node.free()

	# Last resort: make the SAME SeaSpeechBubble class and expected child
	# names in memory. It draws a plain fallback panel even when textures
	# or scene imports are unavailable.
	var bubble: SeaSpeechBubble = SeaSpeechBubble.new()
	bubble.name = "SeaSpeechBubble"
	bubble.layer = 8
	var call: Control = Control.new()
	call.name = "Call"
	call.size = Vector2(83.0, 30.0)
	call.mouse_filter = Control.MOUSE_FILTER_IGNORE
	call.hide()
	bubble.add_child(call)

	var tail: TextureRect = TextureRect.new()
	tail.name = "Tail"
	tail.size = Vector2(12.0, 12.0)
	tail.pivot_offset = Vector2(6.0, 6.0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tail.stretch_mode = TextureRect.STRETCH_KEEP
	tail.hide()
	call.add_child(tail)

	var fallback: Panel = Panel.new()
	fallback.name = "Fallback"
	fallback.size = call.size
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = Color.BLACK
	style.set_border_width_all(3)
	fallback.add_theme_stylebox_override("panel", style)
	call.add_child(fallback)

	var frame: NinePatchRect = NinePatchRect.new()
	frame.name = "Frame"
	frame.size = call.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.hide()
	call.add_child(frame)

	var message: Label = Label.new()
	message.name = "Message"
	message.position = Vector2(7.0, 4.0)
	message.size = Vector2(69.0, 22.0)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message.add_theme_color_override("font_color", Color.BLACK)
	message.add_theme_font_size_override("font_size", 11)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	call.add_child(message)

	# Optional originals: never require these imports for a basic bubble.
	bubble.bubble_texture = load("res://sprites/ui/speech_bubble.png") as Texture2D
	bubble.tail_texture = load("res://sprites/ui/speech_marker.png") as Texture2D
	var pixel_font: Font = load("res://fonts/pixel_operator(1)/PixelOperator.ttf") as Font
	if pixel_font != null:
		message.add_theme_font_override("font", pixel_font)
	_main.add_child(bubble)
	source = "runtime fallback"
	print("[SEA UI] Built fallback bubble under Main; ready=%s" % str(bubble.is_node_ready()))
	_bind(bubble)
	return bubble

