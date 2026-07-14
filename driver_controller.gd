extends CharacterBody3D

@export var steer_speed: float = 8.0
@export var x_limit: float = 4.0
@export var max_steer_angle: float = 25.0 # How far the handlebars turn in degrees
@export var wheel_spin_speed: float = 18.0 # Multiplier for wheel rolling animation

# Drag your Camera3D node into this slot in the Inspector!
@export var camera: Camera3D 
@export var shake_decay: float = 6.0 # How fast the shake settles down
var current_shake_strength: float = 0.0

# Adjust these node paths to match your exact scene structure!
@export var fork: Node3D 
@export var wheel_f: Node3D
@export var wheel_r: Node3D
# If you also have a rear wheel, drag it in here too to spin it!
# @onready var wheel_r: Node3D = $Root/Internals/WheelR

var health: int = 3

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
	if wheel_r:
		wheel_r.rotation_degrees.y -= wheel_spin_speed * 360.0 * delta

	# --- ARCADE SCREEN SHAKE JUICE ---
	if current_shake_strength > 0.0:
		# Decay the shake strength smoothly toward zero
		current_shake_strength = lerpf(current_shake_strength, 0.0, shake_decay * delta)
		
		if camera:
			# Apply random lens offsets based on current strength
			camera.h_offset = randf_range(-current_shake_strength, current_shake_strength)
			camera.v_offset = randf_range(-current_shake_strength, current_shake_strength)
	elif camera and (camera.h_offset != 0.0 or camera.v_offset != 0.0):
		# Snap the lens back to dead-center once the shake finishes
		camera.h_offset = 0.0
		camera.v_offset = 0.0

func _on_hurtbox_area_entered(area: Area3D) -> void:
	# Verify we hit an obstacle car
	if area.name.contains("ObstacleCar") or area.is_in_group("obstacles"):
		take_damage(1)
		
		# Optional: Turn off the obstacle's collision shape instantly 
		# so it doesn't trigger damage multiple times in consecutive frames!
		area.queue_free() 

# Call this anytime you want impact juice (crashes, explosions, hard landings!)
func apply_screen_shake(strength: float = 0.4) -> void:
	current_shake_strength = strength

func take_damage(amount: int) -> void:
	health -= amount
	print("CRASHED! Health left: ", health)
	
	# Trigger the arcade screen shake juice!
	# 0.2 = light scrape, 0.4 = solid crash, 0.7 = absolute destruction
	apply_screen_shake(0.4) 
	
	if health <= 0:
		print("GAME OVER - BUSTED!")
		apply_screen_shake(0.8) # Huge shake for the death crash!
