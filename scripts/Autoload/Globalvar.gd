extends Node


var current_scene: Node = null
var current_class: String = "None"
var current_rank: String = "D"
var current_renown: int = 0
var current_credits: int = 0
var current_points: int = 0
var player_name: String = "Player"

# Active quest
var active_job_id: String = ""
var active_job_title: String = ""
var active_job_description: String = ""
var active_job_progress: int = 0
var active_job_target: int = 0

# Completed quest IDs
var completed_jobs: Array[String] = []

# ---- Phone system additions (wallet events, holdings, contacts, GPS, vehicles) ----
signal credits_changed(credits: int)
signal points_changed(points: int)
signal reputation_changed(reputation: int)
signal destination_changed(position: Vector3, label: String)

var current_reputation: int = 50          # 0..100, lower reputation = jobs pay less
var owned_properties: Array[String] = []
var rented_property: String = ""
var owned_vehicles: Array[String] = []
var inventory_items: Array[String] = []   # market item ids (one entry per unit)
var market_stock: Dictionary = {}         # item id -> remaining stock
var contacts: Array[String] = []          # PhoneData.CONTACTS ids, saved automatically
var vehicle_damage: Dictionary = {}       # vehicle id -> 0..100 (valet "Fix" repairs it)
var vehicle_colors: Dictionary = {}       # vehicle id -> colour name chosen at purchase
var destination: Vector3 = Vector3.ZERO
var destination_label: String = ""
var has_destination: bool = false


func add_credits(amount: int) -> void:
	current_credits = maxi(0, current_credits + amount)
	credits_changed.emit(current_credits)


func spend_credits(amount: int) -> bool:
	if current_credits < amount:
		return false
	current_credits -= amount
	credits_changed.emit(current_credits)
	return true


func add_points(amount: int) -> void:
	current_points = maxi(0, current_points + amount)
	points_changed.emit(current_points)


func change_reputation(delta: int) -> void:
	current_reputation = clampi(current_reputation + delta, 0, 100)
	reputation_changed.emit(current_reputation)


func damage_vehicle(vehicle_id: String, amount: int) -> void:
	vehicle_damage[vehicle_id] = clampi(int(vehicle_damage.get(vehicle_id, 0)) + amount, 0, 100)


func repair_vehicle(vehicle_id: String) -> void:
	vehicle_damage[vehicle_id] = 0


func add_contact(contact_id: String) -> void:
	if not contacts.has(contact_id):
		contacts.append(contact_id)


func set_destination(position: Vector3, label: String) -> void:
	destination = position
	destination_label = label
	has_destination = true
	destination_changed.emit(position, label)


func clear_destination() -> void:
	has_destination = false
	destination_label = ""

func _ready():
	var root = get_tree().root
	current_scene = root.get_child(-1)
	print(player_name)
	print(current_scene )






















func _process(_delta: float) -> void:
	pass
