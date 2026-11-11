class_name ChallengeToast
extends Node

# Announces completed challenges in the world: a ChallengeNotice bubble pops up
# above the terminal (the node in ShopInteractable.TERMINAL_GROUP). Several
# completions at once are queued and shown one after another. With no terminal
# in the scene, nothing is shown.
# Listens to ChallengeManager; the manager never calls this directly.

## Played once per notice. Empty stream = silent.
@export var unlock_sfx: AudioStreamPlayer

var _queue: Array[ChallengeData] = []
var _showing := false


func _ready() -> void:
	if unlock_sfx == null:
		unlock_sfx = get_node_or_null(^"../UnlockSfx") as AudioStreamPlayer
	ChallengeManager.challenge_completed.connect(show_challenge)
	ChallengeManager.challenge_preview_requested.connect(show_challenge)


func show_challenge(challenge: ChallengeData) -> void:
	if challenge == null:
		return
	if unlock_sfx != null and unlock_sfx.stream != null:
		unlock_sfx.play()
	_queue.append(challenge)
	if not _showing:
		_show_next()


func _show_next() -> void:
	_showing = true
	while not _queue.is_empty():
		var challenge: ChallengeData = _queue.pop_front()
		var terminal := get_tree().get_first_node_in_group(ShopInteractable.TERMINAL_GROUP) as ShopInteractable
		if terminal == null:
			continue

		var notice := ChallengeNotice.new()
		notice.challenge = challenge
		notice.position = terminal.notice_offset
		terminal.add_child(notice)
		# tree_exited also fires if the terminal goes away mid-notice.
		await notice.tree_exited
	_showing = false
