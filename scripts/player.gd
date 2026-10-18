extends Node3D

#-----State Groupes:-----
enum Moving_State{WALKING, RUNNING, JUMPING}

#-----Camera Nodes:-----
@onready var camera: Camera3D = $"Camera pivot/Spring arm/Camera"
@onready var camera_pivot: Node3D = $"Camera pivot"
@onready var spring_arm: SpringArm3D = $"Camera pivot/Spring arm"

#-----Character Nodes:-----
@onready var main_character: CharacterBody3D = $"Main character"
@onready var mesh: MeshInstance3D = $"Main character/Mesh"
@onready var collision: CollisionShape3D = $"Main character/Collision"

#-----CameraVariables:-----
@export_category("Camera Variables")
var camera_pitch: float = 0.0
@export var MIN_PITCH: float = -60.0
@export var MAX_PITCH: float = 60.0
var sensitivity : float = 0.01

#-----Camera Zoom variables:------
@export_category("Camera Zoom")
@export var ZOOM_SPEED: float = 1.0
@export var MIN_ZOOM: float = 2.0
@export var MAX_ZOOM: float = 10.0
var zoom_distance: float = 5.0

#-----Flags:-----
var _mouse_look_enabled: bool = false
var _can_handle_physics: bool = true
var _can_follow_camera:bool = true

#-----Player Variable Group:-----
@export_category("Player Variables")
@export var SPEED: float = 5.0
@export var JUMP_VELOCITY: float = 4.5
@export var MOUSE_SENSITIVITY: float = 0.003

#-----State Machine:-----
var current_state = Moving_State.WALKING

func _ready() -> void:
	camera_pitch = camera_pivot.rotation.x
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and current_state != Moving_State.JUMPING:
		_enter_jump_state()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_distance -= ZOOM_SPEED
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_distance += ZOOM_SPEED
		
		zoom_distance = clamp(zoom_distance, MIN_ZOOM, MAX_ZOOM)
		spring_arm.spring_length = zoom_distance 

		if event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_look_enabled = event.pressed

			if _mouse_look_enabled:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event is InputEventMouseMotion and _mouse_look_enabled:
		var next_rotation := spring_arm.rotation
		next_rotation.x -= event.relative.y * sensitivity
		next_rotation.x = clamp(
			next_rotation.x,
			deg_to_rad(-75),
			deg_to_rad(60)
		)
		next_rotation.y -= event.relative.x * sensitivity
		spring_arm.rotation = spring_arm.rotation.lerp(
			next_rotation,
			0.2
		)

func _process(delta: float) -> void:
	match current_state:
		Moving_State.WALKING:
			_handle_walking_state()
		Moving_State.RUNNING:
			_handle_running_state()
		Moving_State.JUMPING:
			_handle_jump_state()

	if _can_follow_camera:
		follow_camera(4, delta)

func _physics_process(delta: float) -> void:
	if _can_handle_physics:
		main_character._handle_physics(delta)

#-----Walking State:-----
func _enter_walking_state() -> void:
	current_state = Moving_State.WALKING

func _handle_walking_state() -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (spring_arm.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		var target_angle = atan2(direction.x, direction.z)
		mesh.rotation.y = lerp_angle(
			mesh.rotation.y,
			target_angle,
			0.15
		)
	main_character._handle_walking(direction, SPEED)

#-----Running State:-----
func _enter_running_state() -> void:
	current_state = Moving_State.RUNNING

func _handle_running_state() -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (spring_arm.global_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		var target_angle = atan2(direction.x, direction.z)
		mesh.rotation.y = lerp_angle(
			mesh.rotation.y,
			target_angle,
			0.15
		)
	main_character._handle_running(direction, SPEED * 2)

#-----Jumping State:-----
func _enter_jump_state() -> void:
	current_state = Moving_State.JUMPING
	main_character.jump(JUMP_VELOCITY)

func _handle_jump_state() -> void:
	if main_character.is_on_floor():
		_end_jump_state()
		return

func _end_jump_state() -> void:
	_enter_walking_state()

#-----Follow camera:-----
func follow_camera(speed: float, delta: float) -> void:
	camera_pivot.global_position = camera_pivot.global_position.lerp(main_character.global_position, speed * delta)
