extends PanelContainer

# Placeholder HUD: one toggle button per FishingManager.available_baits entry.

@onready var current_label: Label = $VBox/CurrentLabel
@onready var button_row: HBoxContainer = $VBox/Buttons

var _buttons: Dictionary[BaitData, Button] = {}

func _ready() -> void:
	var group := ButtonGroup.new()
	for bait in FishingManager.available_baits:
		if bait == null:
			continue
		var button := Button.new()
		button.text = _bait_name(bait)
		button.icon = bait.icon
		button.toggle_mode = true
		button.button_group = group
		# Keep Space (Interact) from pressing the focused button
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(FishingManager.equip_bait.bind(bait))
		button_row.add_child(button)
		_buttons[bait] = button

	FishingManager.bait_changed.connect(_on_bait_changed)
	_on_bait_changed(FishingManager.equipped_bait)

func _on_bait_changed(bait: BaitData) -> void:
	current_label.text = "Bait: " + (_bait_name(bait) if bait != null else "None")
	if _buttons.has(bait):
		_buttons[bait].set_pressed_no_signal(true)

func _bait_name(bait: BaitData) -> String:
	return bait.display_name if bait.display_name != "" else String(bait.bait_id)
