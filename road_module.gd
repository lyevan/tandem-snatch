extends Node3D

# Export an array so we can drag-and-drop all 6 buildings into the Inspector!
@export var building_scenes: Array[PackedScene]

@onready var left_slot: Marker3D = $LeftSlot
@onready var right_slot: Marker3D = $RightSlot

func _ready() -> void:
	# If no buildings are assigned in the editor, exit safely to prevent crashes
	if building_scenes.is_empty():
		return
		
	# Spawn a random building on the left sidewalk, rotated 90 degrees
	spawn_building_at_slot(left_slot, 90.0)
	
	# Spawn a random building on the right sidewalk, rotated -90 degrees (or 270)
	spawn_building_at_slot(right_slot, -90.0)

# Added a second parameter 'y_rotation_deg' to handle custom Y-axis rotation
func spawn_building_at_slot(slot: Marker3D, y_rotation_deg: float) -> void:
	# 1. Pick a random building from our array (Building A through F)
	var random_scene: PackedScene = building_scenes.pick_random()
	
	# 2. Instantiate it
	var building_instance := random_scene.instantiate()
	
	# 3. Add it as a child of the slot so it inherits its position
	slot.add_child(building_instance)
	
	# 4. Zero out local position so it sits squarely on the slot marker
	building_instance.position = Vector3.ZERO
	
	# 5. Reset X and Z tilt, but apply our custom Y rotation in degrees!
	building_instance.rotation_degrees = Vector3(0.0, y_rotation_deg, 0.0)
