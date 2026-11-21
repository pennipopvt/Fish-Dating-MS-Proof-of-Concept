class_name ShopInteractable
extends Interactable

# The world terminal. Opens the shop, receives ShopManager.delivery_requested
# and flies the rewards in by drone. ChallengeToast finds it by TERMINAL_GROUP.

const TERMINAL_GROUP := &"shop_terminal"

@export var prompt: InteractPrompt

@export_group("Delivery")
## Where purchased items land, relative to the terminal (to its right, clear
## of the bobber shelf).
@export var drop_offset := Vector2(26, 0)
## Extra items from the same trade line up along this step.
@export var drop_spacing := Vector2(18, 0)

@export_group("Notices")
## Where challenge notices point their tail, relative to the terminal
## (just above the interact prompt).
@export var notice_offset := Vector2(0, -29)

var _player_in_range := false
var _claim_notice: PanelContainer
# First-time quota reminder shares the existing challenge-notice bubble.
var _intro_quota_notice: bool = false
var _progression_notice: bool = false
# Set by Main from the terminal's actual Challenges unlock state.
# Otherwise a hidden challenge could leave an impossible-to-clear notice.
var _challenge_notice_enabled: bool = false
var _pending: Array[ItemPickup] = []  # bought while the menu is open


func _ready() -> void:
	super()
	add_to_group(TERMINAL_GROUP)
	_build_claim_notice()
	ChallengeManager.challenge_completed.connect(_on_challenge_notice_changed)
	ChallengeManager.challenge_claimed.connect(_on_challenge_notice_changed)
	ChallengeManager.progress_reset.connect(_update_claim_notice)
	ShopManager.shop_opened.connect(_update_prompt)
	ShopManager.shop_opened.connect(_on_shop_opened)
	ShopManager.shop_closed.connect(_update_prompt)
	ShopManager.shop_closed.connect(_launch_drone)
	# The autoload survives a world reload while the physical drone/packages
	# do not. Restore outstanding upgrade deliveries without charging again.
	if ShopManager.is_shop_open:
		ShopManager.set_shop_open(false)
	var recovered: Array[ItemPickup] = ShopManager.get_pending_upgrade_pickups()
	if not recovered.is_empty():
		deliver(recovered)


# A small persistent exclamation badge, shown until all rewards are claimed.
# The slim pixel frame matches Spyglass without the terminal's heavy border.
func _build_claim_notice() -> void:
	_claim_notice = PanelContainer.new()
	_claim_notice.name = "UnclaimedAchievementNotice"
	_claim_notice.custom_minimum_size = Vector2(16, 16)
	_claim_notice.position = notice_offset + Vector2(-8, -20)
	_claim_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_claim_notice.z_as_relative = false
	_claim_notice.z_index = 20
	_claim_notice.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_claim_notice.add_theme_stylebox_override("panel", PixelUI.notification_bubble_style())
	var mark := Label.new()
	mark.text = "!"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_override("font", PixelUI.FONT_SMALL_BOLD)
	mark.add_theme_font_size_override("font_size", 8)
	mark.add_theme_color_override("font_color", PixelUI.CYAN)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_claim_notice.add_child(mark)
	add_child(_claim_notice)
	_update_claim_notice()


func _on_challenge_notice_changed(_challenge: ChallengeData) -> void:
	_update_claim_notice()


func set_intro_quota_notice(enabled: bool) -> void:
	_intro_quota_notice = enabled
	_update_claim_notice()


func set_progression_notice(pending: bool) -> void:
	_progression_notice = pending
	_update_claim_notice()


func set_challenge_notice_enabled(enabled: bool) -> void:
	_challenge_notice_enabled = enabled
	_update_claim_notice()


func _on_shop_opened() -> void:
	# The first visit acknowledges the onboarding prompt, even if the
	# terminal later continues to show ordinary challenge notices.
	if _intro_quota_notice:
		set_intro_quota_notice(false)


func _update_claim_notice() -> void:
	if is_instance_valid(_claim_notice):
		_claim_notice.visible = _intro_quota_notice or _progression_notice \
			or (_challenge_notice_enabled and ChallengeManager.get_claimable_count() > 0)


func _on_body_entered(body: Node2D) -> void:
	super(body)
	if body is Player:
		_player_in_range = true
		_update_prompt()


func _on_body_exited(body: Node2D) -> void:
	super(body)
	if body is Player:
		_player_in_range = false
		_update_prompt()


func interact(_player: Node2D) -> void:
	ShopManager.request_shop()


func _update_prompt() -> void:
	if prompt == null:
		return
	if _player_in_range and not ShopManager.is_shop_open:
		prompt.pop_in()
	else:
		prompt.pop_out()


# On ShopManager.delivery_requested after a trade: a drone flies the pickups (items or
# upgrade packages) in and drops them next to the terminal. Items bought while the
# shop menu is open wait until it closes so the player sees the drone, and
# arrive together on one drone.
func deliver(pickups: Array[ItemPickup]) -> void:
	_pending.append_array(pickups)
	if not ShopManager.is_shop_open:
		_launch_drone()


func _launch_drone() -> void:
	if _pending.is_empty():
		return

	var pickups: Array[ItemPickup] = _pending.duplicate()
	_pending.clear()

	var positions: Array[Vector2] = []
	for i in pickups.size():
		positions.append(global_position + drop_offset + drop_spacing * i)

	var drone := DeliveryDrone.new()
	get_parent().add_child(drone)
	drone.deliver(pickups, positions)


# Listen only while in the tree, so ShopManager.has_delivery_point() is false
# (rewards apply instantly) whenever no terminal is loaded.
func _enter_tree() -> void:
	if not ShopManager.delivery_requested.is_connected(deliver):
		ShopManager.delivery_requested.connect(deliver)


func _exit_tree() -> void:
	if ShopManager.delivery_requested.is_connected(deliver):
		ShopManager.delivery_requested.disconnect(deliver)
	for pickup in _pending:
		pickup.free()
	_pending.clear()
