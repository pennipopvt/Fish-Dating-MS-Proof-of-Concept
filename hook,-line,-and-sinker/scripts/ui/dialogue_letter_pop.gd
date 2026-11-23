@tool
class_name DialogueLetterPop
extends RichTextEffect

# Short bounce when each glyph first appears in the shared DialogueUI.
# All effect strengths/speed are exported on DialogueUI (not hardcoded here).
var bbcode = "letterpop"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var speed: float = maxf(float(char_fx.env.get("speed", 36.0)), 1.0)
	var duration: float = maxf(float(char_fx.env.get("duration", 0.18)), 0.001)
	var age: float = char_fx.elapsed_time - float(char_fx.relative_index) / speed
	if age < 0.0 or age >= duration:
		return true
	var strength: float = 1.0 - clampf(age / duration, 0.0, 1.0)
	strength *= strength
	var scale_boost: float = maxf(float(char_fx.env.get("scale", 0.16)), 0.0)
	char_fx.transform = char_fx.transform.scaled_local(
		Vector2.ONE * (1.0 + strength * scale_boost)
	)
	# Stable pseudo-random offsets: individual letters settle rather than
	# twitching constantly after the reveal.
	var seed: float = float(char_fx.relative_index)
	var jitter: float = maxf(float(char_fx.env.get("jitter", 2.0)), 0.0) * strength
	char_fx.offset += Vector2(
		sin(seed * 13.71 + 0.7),
		cos(seed * 9.37 + 2.1)
	) * jitter
	return true
