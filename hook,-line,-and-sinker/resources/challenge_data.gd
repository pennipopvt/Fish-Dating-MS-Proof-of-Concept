class_name ChallengeData
extends Resource

# One Steam-style challenge (achievement).
# Exported fields are the definition you edit in the Inspector.
# progress / completed / completed_at are runtime state owned and saved by ChallengeManager.

enum RequirementType {
	## Catch target_amount fish in a row. Losing any fish resets progress.
	CONSECUTIVE_CATCHES,
	## Catch target_amount fish in total. Losing a fish does not reset progress.
	TOTAL_CATCHES,
}

## Stable save key. Don't rename after release or saved completion is lost.
@export var challenge_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Art")
## Shown in color once completed (and in the unlock popup).
@export var icon: Texture2D
## Optional art while incomplete. Empty = a greyed-out copy of icon, like Steam.
@export var locked_icon: Texture2D
## Hidden challenges show as "Hidden Challenge" until completed.
@export var hidden: bool = false

@export_group("Requirement")
@export var requirement_type: RequirementType = RequirementType.CONSECUTIVE_CATCHES
@export_range(1, 999) var target_amount: int = 3
## Only these fish count toward progress. Empty = any fish.
@export var counted_fish: Array[FishData] = []

@export_group("Reward")
## These trades stay locked in the terminal until this challenge is completed.
## The player still pays the trade's normal cost after unlocking.
@export var unlocks_trades: Array[TradeData] = []
## Optional reward line in the Challenges tab, e.g. "Pearl Necklace gift trade".
@export var reward_text: String = ""

var progress: int = 0
var completed: bool = false
## Unix time of completion, 0 if not completed.
var completed_at: int = 0


func counts_item(item: ItemData) -> bool:
	if item == null:
		return false

	if counted_fish.is_empty():
		return true

	for counted in counted_fish:
		if counted == null or counted.item_data == null:
			continue
		if counted.item_data == item:
			return true
		if item.item_id != &"" and counted.item_data.item_id == item.item_id:
			return true

	return false


# Returns true when this catch completes the challenge.
func record_catch(item: ItemData) -> bool:
	if completed or not counts_item(item):
		return false

	progress = mini(progress + 1, target_amount)
	return progress >= target_amount


# Returns true if progress changed.
func record_loss() -> bool:
	if completed or requirement_type != RequirementType.CONSECUTIVE_CATCHES:
		return false

	if progress == 0:
		return false

	progress = 0
	return true


func get_progress_ratio() -> float:
	if completed:
		return 1.0
	return clampf(float(progress) / float(maxi(target_amount, 1)), 0.0, 1.0)


func unlocks_trade(trade: TradeData) -> bool:
	if trade == null:
		return false

	for unlock in unlocks_trades:
		if unlock == trade:
			return true
		if unlock != null and trade.trade_id != &"" and unlock.trade_id == trade.trade_id:
			return true

	return false
