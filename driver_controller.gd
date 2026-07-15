extends CharacterBody3D

@export var steer_speed: float = 8.0
@export var x_limit: float = 4.0
@export var max_steer_angle: float = 25.0 
@export var wheel_spin_speed: float = 18.0 
# Drag your FuelGauge node into this slot in the Inspector!
@export var fuel_gauge: ProgressBar

# ==========================================
# --- CRASH & FUEL PENALTY VARIABLES ---
# ==========================================
@export var crash_fuel_penalty: float = 20.0 # How much gas is instantly lost on impact
@export var invincibility_duration: float = 1.5 # Seconds of safety after a crash
var is_invincible: bool = false

@export var camera: Camera3D 
@export var shake_decay: float = 6.0 
var current_shake_strength: float = 0.0
var is_recovering: bool = false

@export var fork: Node3D 
@export var wheel_f: Node3D
@export var wheel_r: Node3D


# --- ADD THIS VARIABLE TO YOUR QTE SECTION ---
var current_required_action: String = ""
var all_qte_actions: Array[String] = ["ui_up", "ui_down", "ui_left", "ui_right"]
# ==========================================
# --- QTE & FUEL ECONOMY VARIABLES ---
# ==========================================
@export var max_fuel: float = 100.0
@export var base_fuel_drain: float = 6.0 # Fuel lost per second
@export var nitro_multiplier: float = 2.0 # 2x drain when Nitro is active

var current_fuel: float = 100.0
var is_nitro_active: bool = false
var is_busted: bool = false

# --- CUSTOM GAME STATS & HUD ---
var cash: int = 0
var heat: float = 0.0
var max_heat: float = 100.0
var hud = null

@export var snatch_fuel_reward: float = 35.0
@export var stumble_penalty_time: float = 2.0

var active_pedestrian: Area3D = null
var is_in_qte_window: bool = false
var is_stumbling: bool = false
var qte_timer: float = 0.0
var qte_duration: float = 2.0 # Player has 2.0 seconds to react
var _qte_accepting_input: bool = false # True only after HUD pop-in finishes

# Make sure your Area3D is exactly named "SnatchZone" in the scene tree!
@onready var snatch_zone: Area3D = $SnatchZone 

func _ready() -> void:
	current_fuel = max_fuel
	
	# Automatically locate the HUD node in the scene tree
	hud = get_parent().get_node_or_null("HUD")
	if not hud:
		hud = get_tree().current_scene.get_node_or_null("HUD")
		
	# Connect the SnatchZone signals automatically via code
	if snatch_zone:
		snatch_zone.area_entered.connect(_on_snatch_zone_entered)
		snatch_zone.area_exited.connect(_on_snatch_zone_exited)
		
	# Initialize HUD stats
	if hud:
		hud.update_gas(current_fuel, max_fuel, false)
		hud.update_loot(0, 0)
		hud.update_heat(0.0, max_heat)

func _physics_process(delta: float) -> void:
	# ------------------------------------------
	# RESET & NITRO INPUT LISTENERS
	# ------------------------------------------
	if Input.is_key_pressed(KEY_R):
		reset_game()
		return
		
	if not is_busted:
		# Nitro is active when Shift is held down
		is_nitro_active = Input.is_key_pressed(KEY_SHIFT)
		var target_speed = 15.0 if is_nitro_active else 5.0 # Boost highway scrolling speed
		if is_invincible:
			target_speed = maxf(1.0, target_speed - 4.0) # Apply speed penalty gracefully
		Global.road_speed = lerpf(Global.road_speed, target_speed, 4.0 * delta)
	else:
		is_nitro_active = false
		
	# ------------------------------------------
	# FUEL DRAIN & QTE TRACKER
	# ------------------------------------------
	if not is_busted:
		var current_drain = base_fuel_drain * (nitro_multiplier if is_nitro_active else 1.0)
		current_fuel -= current_drain * delta
		
		if hud:
			hud.update_gas(current_fuel, max_fuel, is_nitro_active)
			hud.update_speed(Global.road_speed)
			
		if current_fuel <= 0.0:
			trigger_busted_sequence()
			if hud:
				hud.show_game_over(false) # Out of Gas game over
			


	# ------------------------------------------
	# MOTORCYCLE MOVEMENT (Disabled if busted!)
	# ------------------------------------------
	var input_dir := 0.0
	
	if not is_busted:
		if Input.is_action_pressed("steer_left"):
			input_dir -= 1.0
		if Input.is_action_pressed("steer_right"):
			input_dir += 1.0
		
	# 1. LATERAL MOVEMENT
	velocity.x = input_dir * steer_speed
	velocity.z = 0.0
	move_and_slide()
	
	if position.x < -x_limit:
		position.x = -x_limit
		velocity.x = 0.0
	elif position.x > x_limit:
		position.x = x_limit
		velocity.x = 0.0
		
	if not is_busted and is_in_qte_window and not is_stumbling:
		if _qte_accepting_input:
			qte_timer += delta
			if hud:
				hud.update_qte_timer(qte_duration - qte_timer)
			
			# Debug: print timer every ~0.25s
			if int(qte_timer / 0.25) != int((qte_timer - delta) / 0.25):
				print("DEBUG QTE tick | timer=%.2f / %.2f" % [qte_timer, qte_duration])
			
			# Check if the user pressed ANY of the 4 directional keys
			for action in all_qte_actions:
				if Input.is_action_just_pressed(action):
					print("DEBUG key pressed: ", action, " | required: ", current_required_action, " | timer=%.3f" % qte_timer)
					if action == current_required_action:
						# CORRECT KEY PRESSED! Evaluate timing accuracy!
						evaluate_snatch_attempt()
					else:
						# WRONG KEY PRESSED! Instant punishment!
						miss_snatch("WRONG ARROW KEY!")
					break # Stop checking other keys this frame
			
			if qte_timer >= qte_duration:
				print("DEBUG QTE expired | timer=%.3f" % qte_timer)
				miss_snatch("TOO LATE!")


	# 2. HANDLEBAR STEERING
	var target_steer = -input_dir * max_steer_angle
	if fork:
		fork.rotation_degrees.z = lerp(fork.rotation_degrees.z, target_steer, 5.0 * delta)

	# 3. CHASSIS TILT
	rotation_degrees.z = lerp(rotation_degrees.z, -input_dir * 15.0, 10.0 * delta)

	# 4. SPIN THE WHEELS (Slows down to a stop if busted)
	var current_spin = wheel_spin_speed if not is_busted else 0.0
	if wheel_f:
		wheel_f.rotation_degrees.y -= current_spin * 360.0 * delta
	if wheel_r:
		wheel_r.rotation_degrees.y -= current_spin * 360.0 * delta

	# --- ARCADE SCREEN SHAKE JUICE ---
	if current_shake_strength > 0.0:
		current_shake_strength = lerpf(current_shake_strength, 0.0, shake_decay * delta)
		if camera:
			camera.h_offset = randf_range(-current_shake_strength, current_shake_strength)
			camera.v_offset = randf_range(-current_shake_strength, current_shake_strength)
	elif camera and (camera.h_offset != 0.0 or camera.v_offset != 0.0):
		camera.h_offset = 0.0
		camera.v_offset = 0.0

# ==========================================
# --- COLLISION & DAMAGE ---
# ==========================================
func _on_hurtbox_area_entered(area: Area3D) -> void:
	if area.name.contains("ObstacleCar") or area.is_in_group("obstacles"):
		take_crash_penalty()
		area.queue_free() 

func apply_screen_shake(strength: float = 0.4) -> void:
	current_shake_strength = strength

func take_crash_penalty() -> void:
	# Ignore hits if we are already out of gas or currently invincible!
	if is_busted or is_invincible:
		return
		
	print("CRASH DEBRIS! Lost ", crash_fuel_penalty, " Fuel!")
	
	# 1. INSTANT FUEL DEDUCTION
	current_fuel = maxf(0.0, current_fuel - crash_fuel_penalty)
	heat = minf(heat + 10.0, max_heat) # Crashing attracts police attention
	if hud:
		hud.update_gas(current_fuel, max_fuel, is_nitro_active)
		hud.update_heat(heat, max_heat)
		hud.show_feedback("💥 CRASHED! -20 FUEL 💥", Color.CORAL, 1.5)
	
	# 2. HEAVY SCREEN SHAKE JUICE
	apply_screen_shake(0.5) 
	
	# 3. CHECK FOR INSTANT GAME OVER
	if current_fuel <= 0.0:
		trigger_busted_sequence()
		if hud:
			hud.show_game_over(true) # True = Busted/Crashed Out
		return
		
	# 4. TRIGGER MERCY INVINCIBILITY & SPEED PENALTY
	start_crash_recovery()

func start_crash_recovery() -> void:
	is_invincible = true
	
	# The speed penalty is handled gracefully via target_speed interpolation in _physics_process()
	
	# Wait for the safety window to expire
	await get_tree().create_timer(invincibility_duration).timeout
	
	is_invincible = false
	print("RECOVERED - Vulnerable to impacts again!")
# ==========================================
# --- QTE SNATCH LOGIC ---
# ==========================================
func _on_snatch_zone_entered(area: Area3D) -> void:
	if is_stumbling or is_busted:
		return
	active_pedestrian = area
	is_in_qte_window = true
	qte_timer = 0.0
	
	# GRAB THE PEDESTRIAN'S RANDOM REQUIRED ARROW KEY!
	if area.get("required_action") != null:
		current_required_action = area.required_action
		print("QTE ZONE ENTERED | required=", current_required_action, " | is_stumbling=", is_stumbling)
		_qte_accepting_input = false # Block input until HUD signals ready
		if hud:
			hud.start_qte(current_required_action, qte_duration)
			hud.qte_ready.connect(_on_qte_hud_ready, CONNECT_ONE_SHOT)

func _on_snatch_zone_exited(area: Area3D) -> void:
	if area == active_pedestrian:
		print("DEBUG zone exited | cleanly closing QTE overlay")
		is_in_qte_window = false
		active_pedestrian = null
		current_required_action = ""
		_qte_accepting_input = false
		if hud:
			hud.hide_qte()

func _on_qte_hud_ready():
	# HUD pop-in finished — input is now live
	_qte_accepting_input = true
	print("DEBUG QTE READY | input now live | qte_timer reset to 0")
	qte_timer = 0.0 # Reset timer here so it starts from the moment input is live

func evaluate_snatch_attempt() -> void:
	is_in_qte_window = false
	
	# Score based on REACTION SPEED: how quickly did the player press after the prompt appeared?
	# qte_timer counts up from 0 once the HUD is ready, so lower = faster reaction.
	print("DEBUG evaluate_snatch_attempt | qte_timer=%.3f | qte_duration=%.3f" % [qte_timer, qte_duration])
	
	if qte_timer <= 0.4:
		print("PERFECT SNATCH! Reaction time: %.3fs" % qte_timer)
		refuel(snatch_fuel_reward * 1.2)
		cash += 500
		heat = min(heat + 15.0, max_heat)
		if hud:
			hud.update_loot(cash, 500)
			hud.update_heat(heat, max_heat)
			hud.show_feedback("⚡ PERFECT SNATCH! +₱500 ⚡", Color.GOLD, 1.8)
		successful_snatch_cleanup()
	else:
		print("GOOD SNATCH! Reaction time: %.3fs" % qte_timer)
		refuel(snatch_fuel_reward)
		cash += 250
		heat = min(heat + 10.0, max_heat)
		if hud:
			hud.update_loot(cash, 250)
			hud.update_heat(heat, max_heat)
			hud.show_feedback("💰 GOOD SNATCH! +₱250 💰", Color.SPRING_GREEN, 1.8)
		successful_snatch_cleanup()


func successful_snatch_cleanup() -> void:
	if active_pedestrian:
		active_pedestrian.queue_free()
		active_pedestrian = null
	_qte_accepting_input = false
	if hud:
		hud.hide_qte()

func miss_snatch(reason: String) -> void:
	print("SNATCH FAILED: ", reason, " - STUMBLE PENALTY ACTIVE!")
	is_in_qte_window = false
	is_stumbling = true
	_qte_accepting_input = false
	active_pedestrian = null
	current_required_action = ""
	
	if hud:
		hud.show_feedback("❌ SNATCH FAILED: " + reason + " ❌", Color.RED, 1.8)
		hud.hide_qte()
	
	# Lock out the snatch mechanic for 2 seconds
	await get_tree().create_timer(stumble_penalty_time).timeout
	is_stumbling = false
	print("RECOVERED FROM STUMBLE - SNATCH READY!")

func refuel(amount: float) -> void:
	current_fuel = min(current_fuel + amount, max_fuel)

func trigger_busted_sequence() -> void:
	is_busted = true
	current_fuel = 0.0
	print("GAME OVER - BUSTED!")
	apply_screen_shake(0.8) 
	
	# Stop the world from moving
	Global.road_speed = 0.0
	
func reset_game() -> void:
	current_fuel = max_fuel
	is_busted = false
	cash = 0
	heat = 0.0
	is_nitro_active = false
	is_invincible = false
	is_stumbling = false
	is_in_qte_window = false
	active_pedestrian = null
	Global.road_speed = 5.0
	
	# Clear active traffic and pedestrians
	get_tree().call_group("obstacles", "queue_free")
	get_tree().call_group("pedestrians", "queue_free")
	
	# Reset world spawner road segments
	var world_spawner = get_parent().get_node_or_null("WorldSpawner")
	if world_spawner and world_spawner.has_method("reset_spawner"):
		world_spawner.call("reset_spawner")
	elif world_spawner:
		world_spawner._ready()
		
	if hud:
		hud.reset_hud()
		hud.update_gas(current_fuel, max_fuel, false)
		hud.update_loot(0, 0)
		hud.update_heat(0.0, max_heat)
		
	print("GAME RESET - START RUN!")
