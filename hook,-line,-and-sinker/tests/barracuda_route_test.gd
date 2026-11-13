extends SceneTree

# Run from the Godot project root:
# godot --headless --path . -s res://tests/barracuda_route_test.gd
#
# Checks the resource hookups, dialogue graphs, recruitment retry conditions,
# gift choice, attack profile, shop availability and catch-pool removal.
# The actual illustrated transition still needs an in-game visual playtest.

const FISH: FishData = preload("res://resources/fish/barracuda.tres")
const NPC: NPCData = preload("res://resources/npcs/barracuda.tres")
const NPC_SCENE: PackedScene = preload("res://prefabs/barracuda.tscn")
const GIFT: ItemData = preload("res://resources/items/barracuda_scarf.tres")
const WRONG_GIFT: ItemData = preload("res://resources/items/spyglass.tres")
const TRADE: TradeData = preload("res://resources/trades/barracuda_scarf.tres")
const SHOP_SCENE: PackedScene = preload("res://scenes/shop_manager.tscn")

const GRAPHS := [
    "res://dialogue/barracuda_first_catch.json",
    "res://dialogue/barracuda_second_catch.json",
    "res://dialogue/barracuda_casual.json",
    "res://dialogue/barracuda_gift_correct.json",
    "res://dialogue/barracuda_gift_wrong.json",
    "res://dialogue/barracuda_invitation.json",
    "res://dialogue/barracuda_house_scene.json",
    "res://dialogue/barracuda_after_scene.json"
]

var failures: int = 0


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var original_pool: Array[FishData] = FishingManager.possible_catches.duplicate()
    var had_state := NPCManager.npc_states.has(NPC.npc_id)
    var original_state: Dictionary = NPCManager.get_npc_state(NPC.npc_id).duplicate(true)
    NPCManager.npc_states.erase(NPC.npc_id)

    _expect(FISH.npc_data == NPC_SCENE, "Barracuda fish spawns the NPC scene")
    _expect(FISH.item_data != null and FISH.item_data.sprite != null, "Flipped fish has a visible placeholder sprite")
    _expect(FISH.states.size() == 2, "Barracuda has two authored fast attacks")
    for attack in FISH.states:
        _expect(attack != null and attack.windup_duration < 0.45 and attack.state_length < 1.0, "Attack is shorter/faster than the old default")
    _expect(FishingManager.possible_catches.has(FISH), "Barracuda appears in the catch pool")

    var actor := NPC_SCENE.instantiate() as NPCInteractable
    get_root().add_child(actor)
    _expect(actor != null and actor.npc == NPC, "NPC placeholder instantiates with Barracuda NPCData")
    _expect((actor.get_node("Sprite") as AnimatedSprite2D).sprite_frames.has_animation(&"on_caught"), "NPC has the required catch pose animation")
    actor.queue_free()

    var shop := SHOP_SCENE.instantiate()
    var trades: Array = shop.get("trades")
    _expect(trades.has(TRADE), "Scarf appear in the existing gift shop")
    _expect(TRADE.reward_item == GIFT and TRADE.icon == GIFT.sprite, "Scarf are an item with an icon")
    _expect(NPC.desired_gift == GIFT, "Barracuda's configured correct gift is scarf")
    shop.free()

    for path in GRAPHS:
        _expect(not DialogueJsonLoader.read_graph(path).is_empty(), "Valid dialogue graph: " + path)

    var first_graph: Dictionary = DialogueJsonLoader.read_graph("res://dialogue/barracuda_first_catch.json")
    _expect(first_graph["nodes"]["decision"]["choices"].size() == 3, "Three first-catch choices")
    _expect(first_graph["nodes"]["flirt_reply"].has("lines"), "Flirting path is present")
    _expect(first_graph["nodes"]["penni_confident"].get("effects", {}).get("set_flags", []).has("Recruited"), "Only winning path recruits")
    var retry_graph: Dictionary = DialogueJsonLoader.read_graph("res://dialogue/barracuda_second_catch.json")
    _expect(retry_graph["nodes"]["decision"]["choices"].size() == 3, "Second catch repeats recruitment choices")
    _expect(NPC.gift_completed_flag == &"barracuda_scarf_complete", "Scarf has own gift completion flag")

    _expect(NPCManager.get_encounter_json_path(NPC).ends_with("barracuda_first_catch.json"), "First catch uses first meeting")
    var flags: Dictionary = NPCManager.get_npc_state(NPC.npc_id)["flags"]
    flags[&"barracuda_met"] = true
    _expect(NPCManager.get_encounter_json_path(NPC).ends_with("barracuda_second_catch.json"), "Failed recruitment uses special second catch")
    flags[&"Recruited"] = true
    _expect(NPCManager.get_encounter_json_path(NPC).ends_with("barracuda_casual.json"), "Recruited NPC uses casual hints")
    _expect(NPCManager.get_gift_encounter_path(NPC, GIFT).ends_with("barracuda_gift_correct.json"), "Correct gift routes to acceptance dialogue")
    _expect(NPCManager.get_gift_encounter_path(NPC, WRONG_GIFT).ends_with("barracuda_gift_wrong.json"), "Wrong gift routes to hint dialogue")
    flags[&"barracuda_scarf_complete"] = true
    _expect(NPCManager.get_encounter_json_path(NPC).ends_with("barracuda_invitation.json"), "Correct gift unlocks invitation")
    _expect(NPCManager.get_gift_encounter_path(NPC, GIFT).is_empty(), "Completed gift cannot be consumed twice")
    flags[&"barracuda_invitation_accepted"] = true
    _expect(NPCManager.get_encounter_json_path(NPC).ends_with("barracuda_casual.json"), "After invitation NPC returns to casual dialogue")

    var scene_controller_script := load("res://scripts/illustration_scene_controller.gd") as GDScript
    var scene_configs: Dictionary = scene_controller_script.get_script_constant_map().get("SCENES", {})
    _expect(scene_configs.has("barracuda_house"), "Intimate-scene controller supports Barracuda")
    if scene_configs.has("barracuda_house"):
        _expect(scene_configs["barracuda_house"].get("route_complete_flag", "") == "barracuda_route_complete", "Post-scene dialogue uses Barracuda route flag")
    _expect(scene_configs.has("silas_house"), "Silas's existing scene remains available")

    # Remove only recruited Barracuda from catch choices.
    FishingManager.possible_catches = [FISH, preload("res://resources/fish/easy_test_fish.tres")]
    FishingManager.remove_recruited_catch(FISH)
    _expect(not FishingManager.possible_catches.has(FISH), "Recruitment removes Barracuda from the catch pool")
    _expect(FishingManager.possible_catches.size() == 1, "Recruitment leaves regular fish untouched")

    FishingManager.possible_catches = original_pool
    if had_state:
        NPCManager.npc_states[NPC.npc_id] = original_state
    else:
        NPCManager.npc_states.erase(NPC.npc_id)
    print("barracuda_route_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
    quit(1 if failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
    print(("  PASS " if condition else "  FAIL ") + message)
    if not condition:
        failures += 1
