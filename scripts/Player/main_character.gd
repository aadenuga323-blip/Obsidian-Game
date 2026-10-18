extends CharacterBody3D

func _handle_physics(delta):
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()

func jump(JUMP_VELOCITY: float):
	velocity.y = JUMP_VELOCITY

func _handle_walking(direction: Vector3, SPEED: float):
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

func _handle_running(direction: Vector3, SPEED: float):
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
