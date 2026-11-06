class_name ChallengeToast
extends Node

# Announces completed challenges in the world: a ChallengeNotice bubble pops up
# above the terminal (ShopManager.delivery_point). Several completions at once
# are queued and shown one after another. With no terminal in the scene,
# nothing is shown.

var _queue: Array[ChallengeData] = []
var _showing := false


func show_challenge(challenge: ChallengeData) -> void:
	_queue.append(challenge)
	if not _showing:
		_show_next()


func _show_next() -> void:
	_showing = true
	while not _queue.is_empty():
		var challenge: ChallengeData = _queue.pop_front()
		var terminal := ShopManager.delivery_point
		if not is_instance_valid(terminal):
			continue

		var notice := ChallengeNotice.new()
		notice.challenge = challenge
		notice.position = terminal.notice_offset
		terminal.add_child(notice)
		# tree_exited also fires if the terminal goes away mid-notice.
		await notice.tree_exited
	_showing = false
