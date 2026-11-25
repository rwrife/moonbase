class_name IsometricCamera
extends Node3D

var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24.0
	camera.position = Vector3(0, 26, 26)
	camera.rotation_degrees.x = -45.0
	camera.far = 200.0
	add_child(camera)
	camera.current = true
	rotation_degrees.y = 45.0


func _process(delta: float) -> void:
	var input := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	pan(input * delta * camera.size * 0.5)


func pan(direction: Vector2) -> void:
	var movement := global_basis * Vector3(direction.x, 0, direction.y)
	position.x = clampf(position.x + movement.x, -20.0, 20.0)
	position.z = clampf(position.z + movement.z, -20.0, 20.0)


func orbit(direction: float) -> void:
	rotation.y += direction * PI / 4.0


func zoom(direction: float) -> void:
	camera.size = clampf(camera.size + direction * 2.0, 12.0, 60.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rotate_left"):
		orbit(-1)
	elif event.is_action_pressed("rotate_right"):
		orbit(1)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1)
