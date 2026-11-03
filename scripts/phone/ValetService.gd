extends Node
## Valet (autoload). The Mechanic contact's three services:
##  Request - an NPC spawns at a nearby road node in the chosen owned vehicle, drives it
##            to the player, parks, climbs out, and the car is yours to enter.
##  Return  - the delivered vehicle disappears immediately (back to the garage).
##  Fix     - a damaged vehicle enters the mechanic's service queue; repairs run one at
##            a time and the mechanic calls when the car is ready.
## Road nodes: place Marker3D nodes in the "road_node" group along streets. Without any,
## a spawn point is picked ~spawn_distance metres from the player on the ground.

signal state_changed
signal driver_dispatched(vehicle_id: String, eta_seconds: float)
signal vehicle_delivered(vehicle_id: String, vehicle: Node3D)
signal vehicle_returned(vehicle_id: String)
signal repair_started(vehicle_id: String, seconds: float)
signal repair_finished(vehicle_id: String)

const VEHICLE_SCENE := "res://scenes/car/car_a.tscn"
const COLOR_SWATCHES := {
	"Black": Color(0.05, 0.05, 0.06), "Red": Color(0.6, 0.08, 0.08), "White": Color(0.9, 0.9, 0.88),
	"Silver": Color(0.65, 0.66, 0.7), "Navy": Color(0.08, 0.12, 0.3), "Crimson": Color(0.55, 0.05, 0.12),
	"Grey": Color(0.35, 0.36, 0.38), "Obsidian": Color(0.06, 0.05, 0.09), "Cyan": Color(0.1, 0.6, 0.7),
	"Gold": Color(0.75, 0.6, 0.2), "Pearl": Color(0.85, 0.83, 0.78),
}

@export var spawn_distance := 40.0
@export var repair_seconds_per_percent := 0.6   # 50 % damage -> 30 s in the shop
@export var min_repair_seconds := 8.0

var deployed: Dictionary = {}          # vehicle_id -> VehicleBody3D in the world
var en_route: Dictionary = {}          # vehicle_id -> ValetDriver
var service_queue: Array = []          # [{"id": String, "remaining": float, "total": float}], front is on the lift
var last_delivery_eta := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


# ============================================================ queries
func owned_ids() -> Array:
	return Globalvar.owned_vehicles.duplicate()


func damage_of(vehicle_id: String) -> int:
	return int(Globalvar.vehicle_damage.get(vehicle_id, 0))


func in_service(vehicle_id: String) -> bool:
	for item in service_queue:
		if item["id"] == vehicle_id:
			return true
	return false


func service_remaining(vehicle_id: String) -> float:
	var ahead := 0.0
	for item in service_queue:
		ahead += float(item["remaining"])
		if item["id"] == vehicle_id:
			return ahead
	return 0.0


## Human-readable status for the phone.
func status(vehicle_id: String) -> String:
	if en_route.has(vehicle_id):
		return "En route to you"
	if deployed.has(vehicle_id):
		return "Delivered - parked nearby"
	if in_service(vehicle_id):
		return "In service - %s left" % _fmt(service_remaining(vehicle_id))
	var d := damage_of(vehicle_id)
	return ("Garage - damaged %d%%" % d) if d > 0 else "Garage - ready"


## "" when a request is possible, otherwise the reason.
func request_blocker(vehicle_id: String) -> String:
	if not Globalvar.owned_vehicles.has(vehicle_id):
		return "You do not own this vehicle."
	if en_route.has(vehicle_id):
		return "A driver is already bringing it."
	if deployed.has(vehicle_id):
		return "It is already parked near you."
	if in_service(vehicle_id):
		return "It is in the service queue."
	if damage_of(vehicle_id) >= 80:
		return "Too damaged to drive - send it for repair."
	return ""


func _fmt(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]


# ============================================================ REQUEST
func request(vehicle_id: String) -> bool:
	if request_blocker(vehicle_id) != "":
		return false
	var player := _player()
	if player == null:
		return false
	var spawn := _pick_spawn(player)
	var car: Node3D = load(VEHICLE_SCENE).instantiate()
	car.transform = Transform3D(Basis(), spawn + Vector3.UP * 1.0)   # the driver turns it onto the road
	get_tree().current_scene.add_child(car)
	_tint(car, vehicle_id)
	_enable_damage_tracking(car, vehicle_id)
	var driver := ValetDriver.new()
	driver.name = "ValetDriver"
	driver.target = player
	car.add_child(driver)                     # freezes the body and drives it kinematically
	en_route[vehicle_id] = driver
	last_delivery_eta = spawn.distance_to(player.global_position) / 6.0 + 4.0
	driver.arrived.connect(func() -> void: _on_delivered(vehicle_id, car))
	driver_dispatched.emit(vehicle_id, last_delivery_eta)
	state_changed.emit()
	return true


func _on_delivered(vehicle_id: String, car: Node3D) -> void:
	en_route.erase(vehicle_id)
	deployed[vehicle_id] = car
	vehicle_delivered.emit(vehicle_id, car)
	state_changed.emit()


# ============================================================ RETURN
func return_vehicle(vehicle_id: String) -> bool:
	var car: Node3D = deployed.get(vehicle_id)
	if car == null and en_route.has(vehicle_id):
		car = en_route[vehicle_id].get_parent()
		en_route.erase(vehicle_id)
	if car == null:
		return false
	deployed.erase(vehicle_id)
	if is_instance_valid(car):
		if car.get("is_driving") == true and car.has_method("exit_car"):
			car.exit_car()
		car.queue_free()
	vehicle_returned.emit(vehicle_id)
	state_changed.emit()
	return true


# ============================================================ FIX
func fix(vehicle_id: String) -> bool:
	if not Globalvar.owned_vehicles.has(vehicle_id) or in_service(vehicle_id):
		return false
	var d := damage_of(vehicle_id)
	if d <= 0:
		return false
	if deployed.has(vehicle_id) or en_route.has(vehicle_id):
		return_vehicle(vehicle_id)                 # the tow truck takes it from the street
	var secs := maxf(min_repair_seconds, d * repair_seconds_per_percent)
	service_queue.append({"id": vehicle_id, "remaining": secs, "total": secs})
	repair_started.emit(vehicle_id, secs)
	state_changed.emit()
	return true


func _process(delta: float) -> void:
	if service_queue.is_empty():
		return
	var job: Dictionary = service_queue[0]
	job["remaining"] = float(job["remaining"]) - delta
	if job["remaining"] <= 0.0:
		service_queue.pop_front()
		Globalvar.repair_vehicle(job["id"])
		repair_finished.emit(job["id"])
		state_changed.emit()


# ============================================================ helpers
## The player's body. The city scene puts both the "Player" wrapper and its
## "Main character" CharacterBody3D in the "players" group, so prefer a physics body.
func _player() -> Node3D:
	var fallback: Node3D = null
	for n in get_tree().get_nodes_in_group("players"):
		if n is CharacterBody3D:
			return n
		if n is Node3D:
			var body := (n as Node3D).get_node_or_null("Main character")
			if body is CharacterBody3D:
				return body
			if fallback == null:
				fallback = n
	return fallback


func _pick_spawn(player: Node3D) -> Vector3:
	var nodes := get_tree().get_nodes_in_group("road_node")
	var best: Node3D = null
	var best_d := INF
	for n in nodes:
		if n is Node3D:
			var d: float = n.global_position.distance_to(player.global_position)
			if d >= 18.0 and d < best_d:
				best = n
				best_d = d
	if best:
		return best.global_position
	# no road nodes: a point spawn_distance away, snapped to the ground with a ray
	var dir := -player.global_transform.basis.z
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	var guess := player.global_position + dir.normalized() * spawn_distance
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(guess + Vector3.UP * 25.0, guess + Vector3.DOWN * 25.0)
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	return Vector3(guess.x, player.global_position.y, guess.z)


func _tint(car: Node3D, vehicle_id: String) -> void:
	var color_name: String = str(Globalvar.vehicle_colors.get(vehicle_id, ""))
	if not COLOR_SWATCHES.has(color_name):
		return
	var body := car.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if body:
		var m := StandardMaterial3D.new()
		m.albedo_color = COLOR_SWATCHES[color_name]
		m.metallic = 0.6
		m.roughness = 0.35
		body.material_override = m


func _enable_damage_tracking(car: Node3D, vehicle_id: String) -> void:
	var body := car as RigidBody3D
	if body == null:
		return
	body.contact_monitor = true
	body.max_contacts_reported = 4
	body.body_entered.connect(func(_other: Node) -> void:
		var impact: float = body.linear_velocity.length()
		if impact > 6.0:
			Globalvar.damage_vehicle(vehicle_id, int((impact - 6.0) * 2.0)))
