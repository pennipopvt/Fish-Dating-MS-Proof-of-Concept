class_name RoomLightingProfile
extends Resource

# One editable palette shared by every first-person NPC room. GameManager
# owns the time of day; this resource only describes its visual treatment.
# Tints multiply only the background image, never the character portrait/UI.

@export_group("Overall Room Darkness")
## 1 = original room art brightness. Lower values darken every room equally.
@export_range(0.0, 1.0, 0.01) var base_brightness: float = 0.82

@export_group("Morning / Sunrise")
@export var morning_tint: Color = Color(1.0, 0.91, 0.72, 1.0)
@export_range(0.0, 1.0, 0.01) var morning_brightness: float = 1.0

@export_group("Afternoon / Neutral")
@export var afternoon_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var afternoon_brightness: float = 1.0

@export_group("Night / Cool Blue")
@export var night_tint: Color = Color(0.67, 0.76, 0.99, 1.0)
@export_range(0.0, 1.0, 0.01) var night_brightness: float = 0.79


func color_for_period(period: GameManager.Times) -> Color:
	var tint: Color = afternoon_tint
	var period_brightness: float = afternoon_brightness
	match period:
		GameManager.Times.MORNING:
			tint = morning_tint
			period_brightness = morning_brightness
		GameManager.Times.NIGHT:
			tint = night_tint
			period_brightness = night_brightness
	var value: float = base_brightness * period_brightness
	return Color(tint.r * value, tint.g * value, tint.b * value, 1.0)
