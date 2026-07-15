extends Area3D

@export var walking_speed: float = 2.0 
@onready var prompt_label: Label3D = $PromptLabel

# Map our possible input actions to visual arrow symbols
var possible_prompts: Dictionary = {
	"ui_up": "↑",
	"ui_down": "↓",
	"ui_left": "←",
	"ui_right": "→"
}

# This will hold the chosen action string for this specific pedestrian
var required_action: String = ""

func _ready() -> void:
	add_to_group("pedestrians")
	# Pick a random action key from our dictionary
	var keys = possible_prompts.keys()
	required_action = keys.pick_random()
	
	# Set the floating text above their head to the matching arrow!
	if prompt_label:
		prompt_label.text = possible_prompts[required_action]

func _process(delta: float) -> void:
	global_position.z += (Global.road_speed - walking_speed) * delta
	
	if global_position.z > 8.0 or global_position.z < -100.0:
		queue_free()
