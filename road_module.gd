extends Node3D

@export var building_scenes: Array[PackedScene]
@export var obstacle_scenes: Array[PackedScene]
@export var pedestrian_scenes: Array[PackedScene] 

@export var max_cars_per_tile: int = 2
@export var spawn_chance_per_attempt: float = 0.9
@export var pedestrian_spawn_chance: float = 0.45 

@onready var left_slot: Marker3D = $LeftSlot
@onready var right_slot: Marker3D = $RightSlot

# 4 Driving Lanes for Cars
@onready var lane_far_left: Marker3D = $LaneFarLeft
@onready var lane_mid_left: Marker3D = $LaneMidLeft
@onready var lane_mid_right: Marker3D = $LaneMidRight
@onready var lane_far_right: Marker3D = $LaneFarRight

# --- NEW: Dedicated Pedestrian Lanes (Outside the yellow lines) ---
@onready var lane_peds_left: Marker3D = $LanePedsLeft
@onready var lane_peds_right: Marker3D = $LanePedsRight

var incoming_lanes: Array[Marker3D]
var outgoing_lanes: Array[Marker3D]

func _ready() -> void:
	incoming_lanes = [lane_far_left, lane_mid_left]
	outgoing_lanes = [lane_mid_right, lane_far_right]
	
	if not building_scenes.is_empty():
		spawn_building_at_slot(left_slot, 90.0)
		spawn_building_at_slot(right_slot, -90.0)

func generate_4lane_traffic(horizon_z: float) -> void:
	var available_incoming = incoming_lanes.duplicate()
	var available_outgoing = outgoing_lanes.duplicate()
	
	# ==========================================
	# 1. SPAWN PEDESTRIANS (Dedicated Lanes Only)
	# ==========================================
	if not pedestrian_scenes.is_empty() and randf() <= pedestrian_spawn_chance:
		# Flip a coin: Left sidewalk or Right sidewalk?
		var spawn_on_left: bool = randf() > 0.5
		
		# Assign to the dedicated pedestrian markers
		var ped_lane: Marker3D = lane_peds_left if spawn_on_left else lane_peds_right
			
		var ped_instance = pedestrian_scenes.pick_random().instantiate()
		get_tree().current_scene.add_child(ped_instance)
		
		# Snap to the exact sidewalk coordinate
		ped_instance.global_position = Vector3(ped_lane.global_position.x, 0.1, horizon_z)

	# ==========================================
	# 2. SPAWN CARS (4 Driving Lanes)
	# ==========================================
	if obstacle_scenes.is_empty():
		return
		
	var spawn_attempts = randi_range(1, max_cars_per_tile)
	
	for i in range(spawn_attempts):
		if randf() > spawn_chance_per_attempt:
			continue
			
		var spawn_incoming: bool = randf() > 0.5
		
		if spawn_incoming and available_incoming.size() <= 1:
			spawn_incoming = false
		elif not spawn_incoming and available_outgoing.size() <= 1:
			spawn_incoming = true
			
		if available_incoming.size() <= 1 and available_outgoing.size() <= 1:
			break
			
		var target_lane: Marker3D
		if spawn_incoming:
			target_lane = available_incoming.pick_random()
			available_incoming.erase(target_lane)
		else:
			target_lane = available_outgoing.pick_random()
			available_outgoing.erase(target_lane)
			
		var random_car_variant: PackedScene = obstacle_scenes.pick_random()
		var car_instance = random_car_variant.instantiate()
		
		car_instance.add_to_group("obstacles")
		get_tree().current_scene.add_child.call_deferred(car_instance)
		
		var spawn_x = target_lane.global_position.x
		var random_z_stagger = randf_range(-1.2, 1.2)
		
		car_instance.position = Vector3(spawn_x, 0.1, horizon_z + random_z_stagger)
		
		if spawn_incoming:
			car_instance.rotation_degrees.y = 0.0
			if car_instance.has_method("set_incoming"):
				car_instance.call("set_incoming", true)
		else:
			car_instance.rotation_degrees.y = 180.0
			if car_instance.has_method("set_incoming"):
				car_instance.call("set_incoming", false)

func spawn_building_at_slot(slot: Marker3D, y_rotation_deg: float) -> void:
	var random_scene: PackedScene = building_scenes.pick_random()
	var building_instance := random_scene.instantiate()
	slot.add_child(building_instance)
	building_instance.position = Vector3.ZERO
	building_instance.rotation_degrees = Vector3(0.0, y_rotation_deg, 0.0)
