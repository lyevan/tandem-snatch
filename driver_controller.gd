extends CharacterBody3D

@export var steer_speed: float = 8.0
@export var x_limit: float = 4.0
@export var max_steer_angle: float = 25.0 
@export var wheel_spin_speed: float = 18.0 
@export var fuel_gauge: ProgressBar

# ==========================================
# --- CRASH & FUEL PENALTY VARIABLES ---
# ==========================================
@export var crash_fuel_penalty: float = 20.0 
@export var invincibility_duration: float = 1.5 
var is_invincible: bool = false

@export var camera: Camera3D 
@export var shake_decay: float = 6.0 
var current_shake_strength: float = 0.0
var is_recovering: bool = false

@export var fork: Node3D 
@export var wheel_f: Node3D
@export var wheel_r: Node3D

# --- QTE VARIABLES ---
var current_required_action: String = ""
var all_qte_actions: Array[String] = ["ui_up", "ui_down", "ui_left", "ui_right"]

@export var qte_duration: float = 1.0          
@export var perfect_threshold: float = 0.05    
@export var good_threshold: float = 0.15      
var qte_timer: float = 0
var _qte_accepting_input: bool = false 

# ==========================================
# --- FUEL ECONOMY & SHOP VARIABLES ---
# ==========================================
@export var max_fuel: float = 100.0
@export var base_fuel_drain: float = 6.0 
@export var nitro_multiplier: float = 2.0 

@export_group("Gas Station Economy")
@export var gas_refill_price: int = 500        # Costs 300 cash per refill
@export var gas_refill_amount: float = 40.0    # Restores 40% gas
@export var gas_purchase_cooldown: float = 3.0 # Wait 5 seconds between refills
var _gas_cooldown_timer: float = 0.0

var current_fuel: float = 100.0
var is_nitro_active: bool = false
var is_busted: bool = false

# --- CUSTOM GAME STATS & HUD ---
var cash: int = 0
var heat: float = 0.0
var max_heat: float = 100.0
var hud = null

# --- POLICE EVASION VARIABLES ---
@export var full_heat_duration: float = 15.0 # How many seconds the police chase lasts

@export var stumble_penalty_time: float = 2.0
var active_pedestrian: Area3D = null
var is_in_qte_window: bool = false
var is_stumbling: bool = false

@onready var snatch_zone: Area3D = $SnatchZone 

func _ready() -> void:
	add_to_group("player")
	current_fuel = max_fuel
	
	hud = get_parent().get_node_or_null("HUD")
	if not hud:
		hud = get_tree().current_scene.get_node_or_null("HUD")
		
	if snatch_zone:
		snatch_zone.area_entered.connect(_on_snatch_zone_entered)
		snatch_zone.area_exited.connect(_on_snatch_zone_exited)
		
	if hud:
		hud.update_gas(current_fuel, max_fuel, false)
		hud.update_loot(0, 0)
		hud.update_heat(0.0, max_heat)
		hud.update_gas_shop(gas_refill_price, 0.0, gas_purchase_cooldown)
		if hud.has_method("set_snatch_status"):
			hud.set_snatch_status(true) # <-- Set initial HUD status to READY!
		
	# Dynamically instantiate PauseMenu overlay
	var pause_menu_scene = load("res://scenes/ui/pause_menu.tscn")
	if pause_menu_scene:
		var pause_menu_instance = pause_menu_scene.instantiate()
		get_tree().current_scene.add_child.call_deferred(pause_menu_instance)
		
	# Play gameplay BGM (engine sound loop)
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		audio_mgr.play_bgm("game")

func _physics_process(delta: float) -> void:
	# 1. RESET & NITRO INPUT LISTENERS
	if Input.is_action_just_pressed("restart"):
		reset_game()
		return
			
	if not is_busted:
		is_nitro_active = Input.is_key_pressed(KEY_SHIFT)
		var target_speed = 15.0 if is_nitro_active else 5.0 
		var target_fov = 100.0 if is_nitro_active else 75.0
		
		camera.fov = lerpf(camera.fov, target_fov, 8.0 * delta)
		if hud:
			hud.set_speed_lines_active(is_nitro_active)
		if is_invincible:
			target_speed = maxf(1.0, target_speed - 4.0) 
			
		Global.road_speed = lerpf(Global.road_speed, target_speed, 4.0 * delta)
	else:
		is_nitro_active = false
		if hud:
			hud.set_speed_lines_active(false) # Ensure lines turn off if busted!
		
	# 2. FUEL DRAIN & COOLDOWNS
	if not is_busted:
		var current_drain = base_fuel_drain * (nitro_multiplier if is_nitro_active else 1.0)
		current_fuel -= current_drain * delta
		
		# Process Shop Cooldown
		if _gas_cooldown_timer > 0.0:
			_gas_cooldown_timer = maxf(0.0, _gas_cooldown_timer - delta)
			if hud:
				hud.update_gas_shop(gas_refill_price, _gas_cooldown_timer, gas_purchase_cooldown, true)
				
		# Check Gas Purchase Input
		if Input.is_action_just_pressed("buy_gas"):
			_handle_gas_purchase()
		
		if hud:
			hud.update_gas(current_fuel, max_fuel, is_nitro_active)
			hud.update_speed(Global.road_speed)
			
		if current_fuel <= 0.0:
			trigger_busted_sequence()
			if hud:
				hud.show_game_over(false) 
	
	# ==========================================
	# 2.5 POLICE CHASE TIMER & HEAT DRAIN
	# ==========================================
	if Global.is_police_heat_full and not is_busted:
		var drain_rate = max_heat / full_heat_duration
		heat -= drain_rate * delta
		
		if hud:
			hud.update_heat(heat, max_heat)
			
		# When the bar hits 0, the player has survived!
		if heat <= 0.0:
			heat = 0.0
			Global.is_police_heat_full = false
			
			if hud:
				hud.update_heat(0.0, max_heat)
				hud.show_feedback("🛡️ COPS EVADED! BACK TO NORMAL 🛡️", Color.GREEN, 2.5)
			print("🛡️ POLICE CHASE ENDED - NORMAL TRAFFIC RESUMED")

	# 3. MOTORCYCLE MOVEMENT
	var input_dir := 0.0
	if not is_busted:
		if Input.is_action_pressed("steer_left"):
			input_dir -= 1.0
		if Input.is_action_pressed("steer_right"):
			input_dir += 1.0
		
	velocity.x = input_dir * steer_speed
	velocity.z = 0.0
	move_and_slide()
	
	if position.x < -x_limit:
		position.x = -x_limit
		velocity.x = 0.0
	elif position.x > x_limit:
		position.x = x_limit
		velocity.x = 0.0
		
	# 4. QTE INPUT LISTENER & ANTI-MASHING
	if not is_busted and is_in_qte_window and not is_stumbling:
		if not _qte_accepting_input:
			for action in all_qte_actions:
				if Input.is_action_just_pressed(action):
					miss_snatch("FALSE START! DON'T MASH!")
					break
		else:
			qte_timer += delta
			if hud:
				hud.update_qte_timer(qte_duration - qte_timer)
			
			for action in all_qte_actions:
				if Input.is_action_just_pressed(action):
					if action == current_required_action:
						evaluate_snatch_attempt()
					else:
						miss_snatch("WRONG ARROW KEY!")
					break
			
			if qte_timer >= qte_duration:
				miss_snatch("TOO LATE!")

	# 5. HANDLEBAR STEERING & TILT
	var target_steer = input_dir * max_steer_angle
	var target_z = -input_dir * 0.003
	if fork:
		fork.rotation_degrees.y = lerp(fork.rotation_degrees.y, target_steer, 5.0 * delta)
		fork.position.z = lerp(fork.position.z, target_z, 5.0 * delta)
	rotation_degrees.z = lerp(rotation_degrees.z, -input_dir * 15.0, 10.0 * delta)

	# 6. SPIN THE WHEELS
	var current_spin = wheel_spin_speed if not is_busted else 0.0
	if wheel_f:
		wheel_f.rotation_degrees.z -= current_spin * 360.0 * delta
	if wheel_r:
		wheel_r.rotation_degrees.z -= current_spin * 360.0 * delta

	# 7. SCREEN SHAKE JUICE
	if current_shake_strength > 0.0:
		current_shake_strength = lerpf(current_shake_strength, 0.0, shake_decay * delta)
		if camera:
			camera.h_offset = randf_range(-current_shake_strength, current_shake_strength)
			camera.v_offset = randf_range(-current_shake_strength, current_shake_strength)
	elif camera and (camera.h_offset != 0.0 or camera.v_offset != 0.0):
		camera.h_offset = 0.0
		camera.v_offset = 0.0

# ==========================================
# --- GAS SHOP LOGIC ---
# ==========================================
func _handle_gas_purchase() -> void:
	if is_busted:
		return
		
	# Check Cooldown
	if _gas_cooldown_timer > 0.0:
		Audio.play_sfx(preload("res://assets/sfx/snatch_failed.wav"), 25)
		if hud:
			hud.show_feedback("⏳ GAS COOLDOWN! Wait %.1fs ⏳" % _gas_cooldown_timer, Color.ORANGE, 1.0)
		return
		
	# Check Cash
	if cash < gas_refill_price:
		Audio.play_sfx(preload("res://assets/sfx/snatch_failed.wav"), 25)
		if hud:
			hud.show_feedback("❌ NOT ENOUGH CASH! Needs ₱%d ❌" % gas_refill_price, Color.RED, 1.2)
		return
		
	# Check Tank Fullness
	if current_fuel >= max_fuel:
		if hud:
			hud.show_feedback("⚠️ GAS TANK ALREADY FULL! ⚠️", Color.YELLOW, 1.0)
		return
		
	# Process Transaction
	cash -= gas_refill_price
	current_fuel = minf(current_fuel + gas_refill_amount, max_fuel)
	_gas_cooldown_timer = gas_purchase_cooldown
	
	Audio.play_sfx(preload("res://assets/sfx/buy_gas.wav"), 20)
	print("BOUGHT GAS! -₱%d | Added +%d Gas" % [gas_refill_price, gas_refill_amount])
	
	if hud:
		hud.update_loot(cash, 0)
		hud.update_gas(current_fuel, max_fuel, is_nitro_active)
		hud.update_gas_shop(gas_refill_price, _gas_cooldown_timer, gas_purchase_cooldown, true)
		hud.show_feedback("⛽ REFILLED GAS! -₱%d (+40%%) ⛽" % gas_refill_price, Color.CYAN, 2.0)

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
	if is_busted or is_invincible:
		return
		
	current_fuel = maxf(0.0, current_fuel - crash_fuel_penalty)
	
	if hud:
		hud.update_gas(current_fuel, max_fuel, is_nitro_active)
		hud.show_feedback("💥 CRASHED! -20 FUEL 💥", Color.CORAL, 1.5)
		
	add_heat(10.0)
	Audio.play_sfx(preload("res://assets/sfx/crash.mp3"), 15)
	apply_screen_shake(0.5) 
	
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		audio_mgr.play_sfx("crash")
	
	if current_fuel <= 0.0:
		trigger_busted_sequence()
		if hud:
			hud.show_game_over(true) 
		return
	is_stumbling = true
	if hud:
		if hud.has_method("set_snatch_status"):
			hud.set_snatch_status(false) # Turns the hand icon RED ✋
	start_crash_recovery()

func start_crash_recovery() -> void:
	is_invincible = true
	await get_tree().create_timer(invincibility_duration).timeout
	is_stumbling = false
	is_invincible = false
	# Turn the HUD hand icon back to GREEN ✋ once the penalty is over!
	if hud and hud.has_method("set_snatch_status") and not is_busted:
		hud.set_snatch_status(true)

# ==========================================
# --- QTE SNATCH LOGIC ---
# ==========================================
func _on_snatch_zone_exited(area: Area3D) -> void:
	if area != active_pedestrian:
		return
		
	if hud and hud.qte_ready.is_connected(_on_qte_hud_ready):
		hud.qte_ready.disconnect(_on_qte_hud_ready)
		
	is_in_qte_window = false
	active_pedestrian = null
	current_required_action = ""
	_qte_accepting_input = false
	if hud:
		hud.hide_qte()

func _on_snatch_zone_entered(area: Area3D) -> void:
	if is_stumbling or is_busted or is_in_qte_window:
		return
		
	active_pedestrian = area
	is_in_qte_window = true
	_qte_accepting_input = false 
	
	if area.get("required_action") != null:
		current_required_action = area.required_action
		if hud:
			hud.start_qte(current_required_action, qte_duration)
			hud.qte_ready.connect(_on_qte_hud_ready, CONNECT_ONE_SHOT)

func _on_qte_hud_ready():
	if is_in_qte_window and not is_stumbling:
		_qte_accepting_input = true
		qte_timer = 0.0 

func evaluate_snatch_attempt() -> void:
	is_in_qte_window = false
	Audio.play_sfx(preload("res://assets/sfx/snatch.mp3"))
	
	var is_ped_on_left: bool = false
	if is_instance_valid(active_pedestrian):
		is_ped_on_left = active_pedestrian.global_position.x < global_position.x
	
	# --- TIER 1: PERFECT SNATCH ---
	if qte_timer <= perfect_threshold:
		cash += 500
		add_heat(15)
		if hud:
			hud.update_loot(cash, 500)
			hud.show_qte_feedback("⚡ PERFECT SNATCH! +₱500 ⚡", Color.GOLD, 1.5)
			hud.play_snatch_hand(is_ped_on_left)
		Audio.play_sfx(preload("res://assets/sfx/magnanakaw.mp3"))
			
	# --- TIER 2: GOOD SNATCH ---
	elif qte_timer <= good_threshold:
		cash += 250
		add_heat(10)
		if hud:
			hud.update_loot(cash, 250)
			hud.show_qte_feedback("💰 GOOD SNATCH! +₱250 💰", Color.SPRING_GREEN, 1.5)
			hud.play_snatch_hand(is_ped_on_left)
		Audio.play_sfx(preload("res://assets/sfx/habulin_nyo.mp3"))
			
	# --- TIER 3: SLOPPY / LATE SNATCH ---
	else:
		cash += 100
		add_heat(5)
		if hud:
			hud.update_loot(cash, 100)
			hud.show_qte_feedback("⚠️ SLOPPY GRAB! +₱100 ⚠️", Color.YELLOW, 1.5)
		Audio.play_sfx(preload("res://assets/sfx/hoy.mp3"))
			
	successful_snatch_cleanup()

func successful_snatch_cleanup() -> void:
	if active_pedestrian:
		active_pedestrian.queue_free()
		active_pedestrian = null
	_qte_accepting_input = false
	if hud:
		hud.hide_qte()

func miss_snatch(reason: String) -> void:
	is_in_qte_window = false
	is_stumbling = true
	_qte_accepting_input = false
	active_pedestrian = null
	current_required_action = ""
	
	if hud:
		hud.show_qte_feedback("❌ SNATCH FAILED: " + reason + " ❌", Color.RED, 1.5)
		hud.hide_qte()
		if hud.has_method("set_snatch_status"):
			hud.set_snatch_status(false) # <-- TELL HUD COOLDOWN STARTED!
	Audio.play_sfx(preload("res://assets/sfx/snatch_failed.wav"), 25)
	await get_tree().create_timer(stumble_penalty_time).timeout
	is_stumbling = false
	if hud and hud.has_method("set_snatch_status"):
		hud.set_snatch_status(true) # <-- TELL HUD COOLDOWN ENDED!

func trigger_busted_sequence() -> void:
	is_busted = true
	current_fuel = 0.0
	apply_screen_shake(0.8) 
	Global.road_speed = 0.0
	if hud and hud.has_method("set_snatch_status"):
		hud.set_snatch_status(false) # <-- Turn off status when busted
	
func reset_game() -> void:
	current_fuel = max_fuel
	is_busted = false
	cash = 0
	heat = 0.0
	Global.is_police_heat_full = false
	_gas_cooldown_timer = 0.0
	is_nitro_active = false
	is_invincible = false
	is_stumbling = false
	is_in_qte_window = false
	active_pedestrian = null
	Global.road_speed = 5.0
	
	get_tree().call_group("obstacles", "queue_free")
	get_tree().call_group("pedestrians", "queue_free")
	
	var world_spawner = get_parent().get_node_or_null("WorldSpawner")
	if world_spawner and world_spawner.has_method("reset_spawner"):
		world_spawner.call("reset_spawner")
	elif world_spawner:
		world_spawner._ready()
		
	if hud:
		hud.reset_hud()
		hud.set_speed_lines_active(false)
		hud.update_gas(current_fuel, max_fuel, false)
		hud.update_loot(0, 0)
		hud.update_heat(0.0, max_heat)
		hud.update_gas_shop(gas_refill_price, 0.0, gas_purchase_cooldown)
		hud.stop_siren()
		if hud.has_method("set_snatch_status"):
			hud.set_snatch_status(true) # <-- Reset status back to ready!
	Audio.restart_bgm()

# ==========================================
# --- CENTRAL HEAT & POLICE MANAGER ---
# ==========================================
func add_heat(amount: float) -> void:
	# 1. Ignore heat additions if we are already busted OR currently escaping a full police chase
	if is_busted or Global.is_police_heat_full:
		return
		
	# 2. Increase heat and clamp it between 0 and max_heat
	heat = clampf(heat + amount, 0.0, max_heat)
	
	if hud:
		hud.update_heat(heat, max_heat)
		
	# 3. Check if Heat just hit 100% to trigger the 15-second chase!
	if heat >= max_heat and not Global.is_police_heat_full:
		Global.is_police_heat_full = true
		
		if hud:
			hud.show_feedback("🚨 POLICE CHASE! SURVIVE 15 SECONDS! 🚨", Color.RED, 2.5)
		var audio_mgr = get_node_or_null("/root/AudioManager")
		if audio_mgr and audio_mgr.has_method("play_sfx"):
			audio_mgr.play_sfx("police_siren")
