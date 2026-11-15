extends CanvasLayer

# Compact, always-visible clock and date agenda. Does not capture mouse input;
# the F3 debug clock remains a separate testing tool.
var _panel: PanelContainer
var _clock_label: Label
var _date_label: Label


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.theme = PixelUI.get_theme()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(390, 0)
	add_child(_panel)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", PixelUI.SCALE)
	_panel.add_child(content)

	_clock_label = PixelUI.label("")
	_clock_label.add_theme_font_override("font", PixelUI.FONT_SMALL_BOLD)
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_clock_label)

	_date_label = PixelUI.label("")
	_date_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_date_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_date_label)

	GameManager.time_changed.connect(func(_day: int, _period: GameManager.Times) -> void: _refresh())
	GameManager.actions_changed.connect(func(_actions: int) -> void: _refresh())
	DateManager.bookings_changed.connect(_refresh)
	get_viewport().size_changed.connect(_place_panel)
	_refresh()


func _refresh() -> void:
	_clock_label.text = "DAY %d  |  %s  |  %d/%d ACTIONS" % [
		GameManager.get_day(),
		GameManager.get_period_name().to_upper(),
		GameManager.get_actions_left(),
		GameManager.ACTIONS_PER_PERIOD
	]
	if GameManager.get_period() == GameManager.Times.NIGHT:
		_clock_label.text += "\nREST TO START THE NEXT MORNING"
	else:
		var next_period := (GameManager.get_period() + 1) as GameManager.Times
		_clock_label.text += "\n%s IN %d ACTIONS" % [
			GameManager.get_period_name(next_period).to_upper(),
			GameManager.get_actions_left()
		]

	var lines := PackedStringArray()
	var ordered: Array[Dictionary] = []
	for date_id in DateManager.bookings.keys():
		var date := DateManager.get_date(date_id)
		if date == null:
			continue
		var slot: Dictionary = DateManager.bookings[date_id]
		var booked_day := int(slot.get("day", 0))
		var booked_period := int(slot.get("period", 0))
		ordered.append({
			"date": date,
			"day": booked_day,
			"period": booked_period,
			"order": booked_day * 3 + booked_period
		})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["order"]) < int(b["order"])
	)

	for booking in ordered:
		var scheduled_day := int(booking["day"])
		var scheduled_period := int(booking["period"])
		var date: DateData = booking["date"]
		var period_name := GameManager.get_period_name(scheduled_period as GameManager.Times).to_upper()
		var time_label := "DAY %d %s" % [scheduled_day, period_name]
		if scheduled_day == GameManager.get_day():
			time_label = "TODAY %s" % period_name
			if scheduled_period == GameManager.get_period():
				time_label = "NOW"
		lines.append("%s: %s" % [time_label, date.display_name])

	_date_label.text = "DATES: none planned" if lines.is_empty() else "UPCOMING DATES\n" + "\n".join(lines)
	# Text can grow as bookings change; reposition after minimum size updates.
	_place_panel.call_deferred()


func _place_panel() -> void:
	if _panel == null:
		return
	var size := get_viewport().get_visible_rect().size
	_panel.position = Vector2(maxf(8.0, size.x - _panel.size.x - 24.0), 24.0)
