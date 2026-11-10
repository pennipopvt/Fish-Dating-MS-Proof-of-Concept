class_name ChallengesPanel
extends VBoxContainer

# Achievement-style list for the terminal's Challenges tab, drawn in the game's
# pixel style (see PixelUI). Reads everything from ChallengeManager and rebuilds
# whenever it's shown or progress changes.

const S := PixelUI.SCALE
const ICON_SIZE := Vector2(32 * S, 32 * S)
const HIDDEN_ICON := preload("res://sprites/challenges/hidden.png")

const GREYSCALE_SHADER := """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(g) * 0.6, c.a);
}
"""

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var _summary_label: Label
var _summary_bar: ProgressBar
var _list: VBoxContainer
var _greyscale := ShaderMaterial.new()
var _row_style: StyleBoxTexture
var _row_done_style: StyleBoxTexture


func _ready() -> void:
	var shader := Shader.new()
	shader.code = GREYSCALE_SHADER
	_greyscale.shader = shader

	_row_style = PixelUI.box(PixelUI.ROW, PixelUI.ROW_EDGE, 3)
	_row_done_style = PixelUI.box(PixelUI.ROW_DONE, PixelUI.CYAN, 3)

	_build()
	ChallengeManager.challenge_progressed.connect(_on_challenge_changed)
	ChallengeManager.challenge_completed.connect(_on_challenge_changed)
	ChallengeManager.progress_reset.connect(refresh)
	visibility_changed.connect(_on_visibility_changed)
	refresh()


func refresh() -> void:
	var done := ChallengeManager.get_completed_count()
	var total := ChallengeManager.get_total_count()
	var percent := int(round(100.0 * done / total)) if total > 0 else 0

	_summary_label.text = "Completed %d/%d (%d%%)" % [done, total, percent]
	_summary_bar.max_value = maxi(total, 1)
	_summary_bar.value = done

	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	if total == 0:
		_list.add_child(PixelUI.label("No challenges yet.", &"DimLabel"))
		return

	# Completed first (newest on top), then incomplete in authored order.
	var completed: Array[ChallengeData] = []
	var incomplete: Array[ChallengeData] = []
	var hidden_remaining := 0
	for challenge in ChallengeManager.challenges:
		if challenge == null:
			continue
		if challenge.completed:
			completed.append(challenge)
		elif challenge.hidden:
			# Hidden challenges don't appear until they're unlocked.
			hidden_remaining += 1
		else:
			incomplete.append(challenge)

	completed.sort_custom(func(a, b): return a.completed_at > b.completed_at)

	for challenge in completed + incomplete:
		_list.add_child(_make_row(challenge))

	if hidden_remaining > 0:
		_list.add_child(_make_hidden_row(hidden_remaining))


# ---- Layout --------------------------------------------------------------

func _build() -> void:
	add_theme_constant_override("separation", 3 * S)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4 * S)
	add_child(header)

	_summary_label = PixelUI.label("", &"TitleLabel")
	header.add_child(_summary_label)

	_summary_bar = _make_bar()
	_summary_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_summary_bar)

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", PixelUI.box(PixelUI.INSET, PixelUI.ROW_EDGE, 2))
	add_child(frame)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2 * S)
	scroll.add_child(_list)


func _make_row(challenge: ChallengeData) -> Control:
	var done := challenge.completed
	var secret := challenge.hidden and not done

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_done_style if done else _row_style)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 5 * S)
	row.add_child(columns)

	# Icon: color when done, greyed out (or custom locked art) when not.
	var icon := TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if secret:
		icon.texture = HIDDEN_ICON
	elif done or challenge.locked_icon == null:
		icon.texture = challenge.icon
		if not done:
			icon.material = _greyscale
	else:
		icon.texture = challenge.locked_icon
	columns.add_child(icon)

	# Name, description, progress, reward.
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 2 * S)
	columns.add_child(text)

	text.add_child(PixelUI.label(
		"Hidden Challenge" if secret else challenge.display_name,
		&"TitleLabel", PixelUI.TEXT if done else PixelUI.TEXT_DIM.lerp(PixelUI.TEXT, 0.5)
	))

	var description := PixelUI.label(
		"Keep fishing to reveal this challenge." if secret else challenge.description,
		&"DimLabel"
	)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(description)

	if not done and not secret:
		var progress_row := HBoxContainer.new()
		progress_row.add_theme_constant_override("separation", 4 * S)
		var bar := _make_bar()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = challenge.target_amount
		bar.value = challenge.progress
		progress_row.add_child(bar)
		progress_row.add_child(PixelUI.label(
			"%d/%d" % [challenge.progress, challenge.target_amount], &"DimLabel"
		))
		text.add_child(progress_row)

	if not secret and challenge.reward_text != "":
		var reward := PixelUI.label(
			("Unlocked: " if done else "Reward: ") + challenge.reward_text,
			&"", PixelUI.GOLD if done else PixelUI.TEXT_DIM
		)
		reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(reward)

	# Right side: unlock date.
	if done:
		var date := PixelUI.label(
			"Unlocked\n" + _format_date(challenge.completed_at), &"DimLabel"
		)
		date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		columns.add_child(date)

	return row


# Steam-style footer: "+3 hidden challenges remaining".
func _make_hidden_row(count: int) -> Control:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_style)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 5 * S)
	row.add_child(columns)

	var icon := TextureRect.new()
	icon.texture = HIDDEN_ICON
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	columns.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 2 * S)
	columns.add_child(text)

	text.add_child(PixelUI.label(
		"+%d hidden challenge%s remaining" % [count, "" if count == 1 else "s"],
		&"TitleLabel", PixelUI.TEXT_DIM.lerp(PixelUI.TEXT, 0.5)
	))
	var hint := PixelUI.label(
		"Details for each challenge will be revealed once unlocked.", &"DimLabel"
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(hint)

	return row


func _make_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6 * S)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


# e.g. "Nov 3, 2026 4:12 PM" in local time.
func _format_date(unix_time: int) -> String:
	if unix_time <= 0:
		return ""

	var bias_minutes: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	var hour: int = d.hour % 12
	if hour == 0:
		hour = 12

	return "%s %d, %d %d:%02d %s" % [
		MONTHS[d.month - 1], d.day, d.year, hour, d.minute, "AM" if d.hour < 12 else "PM"
	]


func _on_challenge_changed(_challenge: ChallengeData) -> void:
	if is_visible_in_tree():
		refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		refresh()
