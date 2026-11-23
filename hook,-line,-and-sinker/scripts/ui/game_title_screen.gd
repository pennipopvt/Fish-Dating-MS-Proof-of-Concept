class_name GameTitleScreen
extends CanvasLayer

signal play_requested

@onready var _menu: Control = $Menu
@onready var _options: Control = $Options
@onready var _play: Button = $Menu/Contents/Play
@onready var _settings: Button = $Menu/Contents/Options
@onready var _quit: Button = $Menu/Contents/Quit
@onready var _back: Button = $Options/Contents/Back
@onready var _music_slider: HSlider = $Options/Contents/MusicVolume
@onready var _ambience_slider: HSlider = $Options/Contents/AmbienceVolume


func _ready() -> void:
	_play.pressed.connect(_on_play)
	_settings.pressed.connect(_show_options)
	_quit.pressed.connect(func() -> void: get_tree().quit())
	_back.pressed.connect(_show_menu)
	_music_slider.value_changed.connect(_set_bus_volume.bind(&"Music"))
	_ambience_slider.value_changed.connect(_set_bus_volume.bind(&"Ambience"))
	_show_menu()


func _on_play() -> void:
	_play.disabled = true
	hide()
	play_requested.emit()


func _show_options() -> void:
	_menu.hide()
	_options.show()
	_music_slider.set_value_no_signal(_get_bus_volume(&"Music"))
	_ambience_slider.set_value_no_signal(_get_bus_volume(&"Ambience"))
	_back.grab_focus()


func _show_menu() -> void:
	_options.hide()
	_menu.show()
	_play.grab_focus()


func _get_bus_volume(bus_name: StringName) -> float:
	var index: int = AudioServer.get_bus_index(bus_name)
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.0, 1.0) if index >= 0 else 1.0


func _set_bus_volume(value: float, bus_name: StringName) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))
