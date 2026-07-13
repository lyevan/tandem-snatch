extends CharacterBody3D

@export var steer_speed: float = 8.0
@export var x_limit: float = 2.0
@export var max_steer_angle: float = 25.0 # How far the handlebars turn in degrees
@export var wheel_spin_speed: float = 18.0 # Multiplier for wheel rolling animation

# Adjust these node paths to match your exact scene structure!
@export var fork: Node3D 
@export var wheel_f: Node3D
# If you also have a rear wheel, drag it in here too to spin it!
# @onready var wheel_r: Node3D = $Root/Internals/WheelR

func _physics_process(delta: float) -> void:
	var input_dir := 0.0
	
	if Input.is_action_pressed("ui_left"):
		input_dir -= 1.0
	if Input.is_action_pressed("ui_right"):
		input_dir += 1.0
		
	# 1. LATERAL MOVEMENT
	velocity.x = input_dir * steer_speed
	velocity.z = 0.0
	move_and_slide()
	
	# Clamp position to the road boundaries
	if position.x < -x_limit:
		position.x = -x_limit
		velocity.x = 0.0
	elif position.x > x_limit:
		position.x = x_limit
		velocity.x = 0.0

	# 2. HANDLEBAR STEERING (Rotate around Y-axis)
	# We lerp the fork's Y rotation based on input direction.
	# Note: In standard Godot 3D space, turning left is positive Y rotation, right is negative.
	var target_steer = -input_dir * max_steer_angle
	if fork:
		fork.rotation_degrees.z = lerp(fork.rotation_degrees.z, target_steer, 5.0 * delta)
		
		# If WheelF is NOT a child of Fork, uncomment the line below to turn it separately:
		# if wheel_f: wheel_f.rotation_degrees.y = fork.rotation_degrees.y

	# 3. CHASSIS TILT (Lean the bike body into the turn)
	rotation_degrees.z = lerp(rotation_degrees.z, -input_dir * 15.0, 10.0 * delta)

	# 4. BONUS JAM JUICE: SPIN THE WHEELS (Rotate around X-axis)
	# This makes the bike look like it's driving at high speed on the treadmill!
	if wheel_f:
		wheel_f.rotation_degrees.y -= wheel_spin_speed * 360.0 * delta
