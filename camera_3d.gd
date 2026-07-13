extends Camera3D

# Drag your Marker3D nodes into these slots in the Godot Inspector
@export var driver_pos: Marker3D
@export var snatcher_pos: Marker3D
@export var transition_speed: float = 8.0 # Higher number = faster camera transition

var is_driver_view: bool = true
var target_transform: Transform3D

func _ready() -> void:
	# Set the initial view immediately without interpolation
	if driver_pos:
		global_transform = driver_pos.global_transform
		target_transform = driver_pos.global_transform

func _input(event: InputEvent) -> void:
	# Map "toggle_camera" in Project Settings -> Input Map (e.g., to the Tab key or Triangle/Y button)
	if event.is_action_pressed("toggle_camera"):
		is_driver_view = !is_driver_view
		print("Switched POV. Driver View: ", is_driver_view)

func _process(delta: float) -> void:
	# Determine which marker we should be following
	if is_driver_view and driver_pos:
		target_transform = driver_pos.global_transform
	elif !is_driver_view and snatcher_pos:
		target_transform = snatcher_pos.global_transform
		
	# Smoothly interpolate position toward the target marker
	global_position = global_position.lerp(target_transform.origin, transition_speed * delta)
	
	# --- FIX APPLIED HERE ---
	# We call .orthonormalized() on both bases to strip out tiny floating point errors 
	# and force them to stay mathematically clean before the slerp operation.
	var current_basis = global_transform.basis.orthonormalized()
	var target_basis = target_transform.basis.orthonormalized()
	
	global_transform.basis = current_basis.slerp(target_basis, transition_speed * delta)
