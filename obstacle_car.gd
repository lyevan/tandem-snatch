extends Area3D

# This MUST match the road_speed in your WorldSpawner!
@export var road_speed: float = 5.0 

# How fast this specific vehicle drives in the real world
@export var vehicle_speed: float = 5.0 

var is_incoming: bool = false

func set_incoming(incoming_flag: bool) -> void:
	is_incoming = incoming_flag

func _process(delta: float) -> void:
	if is_incoming:
		# LEFT LANES (Oncoming Hazards):
		# They drive TOWARD us while the road ALSO moves toward us.
		# Net approach velocity = road_speed + vehicle_speed (e.g., 15 + 9 = +24 m/s toward camera)
		global_position.z += (road_speed + vehicle_speed) * delta
	else:
		# RIGHT LANES (Catchable Targets for Player 2):
		# They drive in the SAME direction as us, but SLOWER than our motorcycle.
		# Net approach velocity = road_speed - vehicle_speed (e.g., 15 - 9 = +6 m/s toward camera)
		# Because the net result is still positive (+6), the car smoothly drifts from the 
		# horizon down to our handlebars so Player 2 can pull off the snatch!
		global_position.z += (road_speed - vehicle_speed + 10) * delta
		
	# Clean up safely once the vehicle passes behind the camera
	if global_position.z > 12.0 or global_position.z < -100.0:
		queue_free()
