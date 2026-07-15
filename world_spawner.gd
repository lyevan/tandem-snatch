extends Node3D

@export var road_scene: PackedScene
@export var module_length: float = 2.0  # Your measured mesh length  # Controlled centrally here now
@export var initial_modules: int = 25    # Enough modules to fill past the horizon
@export var safe_zone_distance: float = 40.0

func _ready() -> void:
	# Clean up any editor remnants and spawn the initial track perfectly flush
	for child in get_children():
		child.queue_free()
		
	for i in range(initial_modules):
		spawn_module(-i * module_length)

func reset_spawner() -> void:
	for child in get_children():
		child.queue_free()
	for i in range(initial_modules):
		spawn_module(-i * module_length)

func _process(delta: float) -> void:
	# 1. Move ALL active road pieces backward together (prevents micro-drifting)
	for child in get_children():
		child.position.z += Global.road_speed * delta
		
		# 2. INSTANT CLEANUP: If a piece goes behind the camera, remove it immediately
		if child.position.z > 6.0: # Adjust this number based on where your camera sits
			remove_child(child) # Unparent immediately so get_child_count() drops instantly!
			child.queue_free()  # Safely delete from memory at the end of the frame

	# 3. Check if we need to replenish the road at the horizon
	# Using 'while' ensures that even if multiple tiles are cleaned up, they all respawn instantly
	while get_child_count() < initial_modules:
		var furthest_z := get_furthest_tail_z()
		spawn_module(furthest_z - module_length)

# Helper function to find the absolute tail end of the current highway road chain
func get_furthest_tail_z() -> float:
	var min_z := 0.0
	if get_child_count() > 0:
		min_z = get_child(0).position.z
		for child in get_children():
			if child.position.z < min_z:
				min_z = child.position.z
	return min_z

func spawn_module(z_pos: float) -> void:
	var instance = road_scene.instantiate()
	add_child(instance)
	instance.position.z = z_pos
	
	# --- THE PREP TIME SAFE ZONE ---
	# Road chunks extend into negative Z space (e.g., -10, -20, -50).
	# By checking if z_pos is LESS than our negative safe zone distance,
	# we guarantee that tiles at 0, -10, and -20 stay completely empty!
	if z_pos < -safe_zone_distance and instance.has_method("generate_4lane_traffic"):
		instance.call_deferred("generate_4lane_traffic", z_pos)
