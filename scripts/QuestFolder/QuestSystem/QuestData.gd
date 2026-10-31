
extends Resource
class_name QuestData

@export var quest_id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""

@export_category("Objective")
@export var target: int = 1

@export_category("Rewards")
@export var renown_reward: int = 0
@export var credits_reward: int = 0

@export_category("Phone job board")
@export var client: String = "City contract"
@export var job_type: String = "Delivery"      # Delivery, Moving, Foundry, Combat
@export var pay: int = 0                        # credits paid on completion (scaled by reputation)
@export var distance_m: int = 0
@export var duration_min: int = 0
@export var has_location: bool = false
@export var location: Vector3 = Vector3.ZERO    # objective position; the phone drops a GPS beacon here
