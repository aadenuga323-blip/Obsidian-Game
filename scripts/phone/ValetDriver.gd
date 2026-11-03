extends Node
class_name ValetDriver
## AI chauffeur attached as a child of a VehicleBody3D. The body is frozen in kinematic
## mode and driven along the ground toward `target` with smooth turning and a speed
## profile, so delivery works the same regardless of how the vehicle's wheels and
## suspension are tuned. On arrival the car is unfrozen, the NPC climbs out and walks
## off, and the driver removes itself so the vehicle's own script takes over.

signal arrived

@export var park_distance := 6.0
@export var cruise_speed := 9.0        # m/s
@export var acceleration := 4.0        # m/s^2
@export var turn_rate := 1.4           # rad/s at full lock
@export var give_up_after := 60.0      # seconds; afterwards the car is placed beside the player

var target: Node3D
var car: RigidBody3D

var _state := "driving"
var _elapsed := 0.0
var _speed := 0.0
var _nose_local := Vector3(0, 0, -1)   # which local axis the vehicle's front points along
var _ride_height := 0.0                # distance from the ground kept while driving
var _npc: Node3D


func _ready() -> void:
	car = get_parent() as RigidBody3D
	_nose_local = _detect_nose()
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	_ride_height = _measure_ride_height()
	_npc = _build_npc()
	var seat := car.get_node_or_null("SeatPosition") as Node3D
	_npc.position = seat.position if seat else Vector3(0.4, 0.6, 0.0)
	car.add_child(_npc)


## Front of the car = centroid of the steering wheels minus centroid of the others.
## Falls back to -Z when the scene has no VehicleWheel3D nodes.
func _detect_nose() -> Vector3:
	var steer := Vector3.ZERO
	var drive := Vector3.ZERO
	var ns := 0
	var nd := 0
	for w in car.get_children():
		if w is VehicleWheel3D:
			if w.use_as_steering:
				steer += w.position
				ns += 1
			else:
				drive += w.position
				nd += 1
	if ns > 0 and nd > 0:
		var d := steer / ns - drive / nd
		d.y = 0.0
		if d.length() > 0.2:
			return d.normalized()
	return Vector3(0, 0, -1)


func _ground_y(at: Vector3) -> float:
	var space := car.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 8.0)
	q.exclude = [car.get_rid()]
	if is_instance_valid(target) and target is CollisionObject3D:
		q.exclude.append(target.get_rid())
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else at.y


func _measure_ride_height() -> float:
	var g := _ground_y(car.global_position)
	return clampf(car.global_position.y - g, 0.3, 2.0)


func _build_npc() -> Node3D:
	var root := Node3D.new()
	root.name = "ValetNPC"
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 0.9
	body.mesh = cap
	body.position = Vector3(0, 0.45, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.42, 0.18)
	body.material_override = mat
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.16
	sph.height = 0.32
	head.mesh = sph
	head.position = Vector3(0, 1.05, 0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.75, 0.6, 0.5)
	head.material_override = skin
	root.add_child(head)
	var cap_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.17
	cyl.bottom_radius = 0.17
	cyl.height = 0.08
	cap_mesh.mesh = cyl
	cap_mesh.position = Vector3(0, 1.2, 0)
	var capm := StandardMaterial3D.new()
	capm.albedo_color = Color(0.13, 0.13, 0.14)
	cap_mesh.material_override = capm
	root.add_child(cap_mesh)
	return root


func _nose_world() -> Vector3:
	var n := car.global_transform.basis * _nose_local
	n.y = 0.0
	return n.normalized()


func _physics_process(delta: float) -> void:
	if _state != "driving" or not is_instance_valid(target) or car == null:
		return
	_elapsed += delta
	var to := target.global_position - car.global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= park_distance or _elapsed > give_up_after:
		if _elapsed > give_up_after:
			car.global_position = target.global_position + target.global_transform.basis.x * 4.0 + Vector3.UP * _ride_height
		_park()
		return
	# steer: rotate the nose toward the target at a limited rate
	var fwd := _nose_world()
	var angle := atan2(fwd.cross(to).y, fwd.dot(to))
	var max_turn := turn_rate * delta * clampf(_speed / 3.0 + 0.3, 0.3, 1.0)
	var turn := clampf(angle, -max_turn, max_turn)
	if _elapsed < 0.1:
		turn = angle                                     # snap to the road direction when setting off
	car.global_rotate(Vector3.UP, turn)
	# speed profile: accelerate, slow for sharp turns and for the approach
	var want := minf(cruise_speed, maxf(2.0, (dist - park_distance) * 0.9))
	want *= lerpf(1.0, 0.45, clampf(absf(angle) / 1.0, 0.0, 1.0))
	_speed = move_toward(_speed, want, acceleration * delta)
	var step := _nose_world() * _speed * delta
	var next := car.global_position + step
	next.y = _ground_y(next) + _ride_height
	car.global_position = next


func _park() -> void:
	_state = "parking"
	_speed = 0.0
	await get_tree().create_timer(0.6, true).timeout
	if not is_inside_tree():
		return
	car.freeze = false                                    # hand the body back to physics
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	# NPC climbs out on the side and walks away
	var world_pos := _npc.global_position
	var side := car.global_transform.basis.x
	side.y = 0.0
	if absf(side.dot(_nose_world())) > 0.8:               # X is the length axis on this car: use Z
		side = car.global_transform.basis.z
		side.y = 0.0
	side = side.normalized() * 1.8
	car.remove_child(_npc)
	get_tree().current_scene.add_child(_npc)
	_npc.global_position = world_pos + side
	var tw := _npc.create_tween()
	tw.tween_property(_npc, "global_position", _npc.global_position + side * 3.0 - _nose_world() * 6.0, 4.0)
	tw.tween_callback(_npc.queue_free)
	_state = "done"
	arrived.emit()
	queue_free()
