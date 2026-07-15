extends CanvasLayer

# --- Node References ---
@onready var gas_meter = $Dashboard/VBox/GasMeter
@onready var speed_label = $Dashboard/VBox/SpeedLabel

@onready var heat_meter = $WantedLevel/VBox/HeatMeter
@onready var wanted_level_panel = $WantedLevel

@onready var cash_label = $LootSack/VBox/CashLabel
@onready var last_item_label = $LootSack/VBox/LastItemLabel

@onready var game_over_panel = $GameOverPanel
@onready var game_over_message = $GameOverPanel/VBox/MessageLabel
@onready var game_over_restart_btn = $GameOverPanel/VBox/RestartButton if has_node("GameOverPanel/VBox/RestartButton") else null
@onready var game_over_menu_btn = $GameOverPanel/VBox/MainMenuButton if has_node("GameOverPanel/VBox/MainMenuButton") else null
@onready var feedback_label = $FeedbackLabel
@onready var qte_feedback_label = $QTEFeedbackLabel
@onready var qte_panel = $QTEPanel
@onready var qte_prompt = $QTEPanel/VBox/ArrowBox/QTEPrompt
@onready var qte_timer = $QTEPanel/VBox/TimerContainer/QTETimer
@onready var qte_arrow_box = $QTEPanel/VBox/ArrowBox

# --- Optional Gas Shop UI References ---
@onready var gas_shop_panel = $GasShopPanel if has_node("GasShopPanel") else null
@onready var gas_shop_label = $GasShopPanel/VBox/PriceLabel if has_node("GasShopPanel/VBox/PriceLabel") else null
@onready var gas_cooldown_bar = $GasShopPanel/VBox/CooldownBar if has_node("GasShopPanel/VBox/CooldownBar") else null

signal qte_ready 

# --- Internal State Tracking ---
var _previous_heat_level: int = 0
var _strobe_timer: float = 0.0
var _is_max_heat: bool = false
var _is_gas_shaking: bool = false
var _gas_meter_original_x: float = 0.0
var _feedback_tween: Tween = null
var _last_fuel_warning_time: float = 0.0
var _feedback_queue: Array[Dictionary] = []
var _is_displaying_feedback: bool = false
var _qte_panel_original_x: float = 0.0
var _is_qte_panel_shaking: bool = false
var _is_qte_pulsing: bool = false
var _qte_feedback_tween: Tween = null

func _ready() -> void:
	# Connect Game Over screen buttons if they exist
	if game_over_restart_btn:
		game_over_restart_btn.pressed.connect(_on_game_over_restart_pressed)
	if game_over_menu_btn:
		game_over_menu_btn.pressed.connect(_on_game_over_menu_pressed)
		
	# Setup UI hover/press sound effects for the game HUD buttons recursively
	_setup_button_sounds(self)

func _setup_button_sounds(node: Node) -> void:
	var audio_mgr = get_node_or_null("/root/AudioManager")
	for child in node.get_children():
		if child is Button:
			child.mouse_entered.connect(func(): if audio_mgr: audio_mgr.play_sfx("hover"))
			child.focus_entered.connect(func(): if audio_mgr: audio_mgr.play_sfx("hover"))
			child.pressed.connect(func(): if audio_mgr: audio_mgr.play_sfx("press"))
		elif child.get_child_count() > 0:
			_setup_button_sounds(child)

func _process(delta: float):
	# Handle rapid police strobe lights on Max Heat (100%)
	if _is_max_heat:
		_strobe_timer += delta
		if _strobe_timer >= 0.15: 
			_strobe_timer = 0.0
			
			var style = wanted_level_panel.get_theme_stylebox("panel").duplicate()
			if style is StyleBoxFlat:
				style.border_width_left = 3
				style.border_width_top = 3
				style.border_width_right = 3
				style.border_width_bottom = 3
				
				if heat_meter.modulate == Color.RED:
					heat_meter.modulate = Color.CORNFLOWER_BLUE # Blue strobe
					style.border_color = Color.CORNFLOWER_BLUE
					style.shadow_color = Color(0.0, 0.5, 1.0, 0.45)
				else:
					heat_meter.modulate = Color.RED # Red strobe
					style.border_color = Color.RED
					style.shadow_color = Color(1.0, 0.0, 0.0, 0.45)
				wanted_level_panel.add_theme_stylebox_override("panel", style)
	else:
		# Reset stylebox override if heat drops below max
		wanted_level_panel.remove_theme_stylebox_override("panel")

# --- Update Functions ---

func update_gas(current_gas: float, max_gas: float, is_nitro_active: bool):
	if not is_node_ready():
		await ready
		
	gas_meter.max_value = max_gas
	gas_meter.value = current_gas
	gas_meter.pivot_offset = gas_meter.size / 2.0
	
	if current_gas < (max_gas * 0.2):
		gas_meter.modulate = Color(1.0, 0.0, 0.0)
		_shake_gas_meter()
		_show_low_fuel_warning()
	elif is_nitro_active:
		gas_meter.modulate = Color(1.0, 0.5, 0.0)
		_shake_gas_meter_nitro()
	else:
		gas_meter.modulate = Color(0.0, 1.0, 0.0)

func update_speed(current_speed: float):
	if not is_node_ready():
		await ready
	speed_label.text = "SPEED: " + str(round(current_speed)) + " m/s"

func update_heat(current_heat: float, max_heat: float):
	if not is_node_ready():
		await ready
		
	heat_meter.max_value = max_heat
	heat_meter.value = current_heat
	
	var heat_percentage = current_heat / max_heat
	var current_heat_level = 0
	
	if heat_percentage <= 0.25:
		current_heat_level = 0 
	elif heat_percentage <= 0.60:
		current_heat_level = 1 
	elif heat_percentage < 1.0:
		current_heat_level = 2 
	else:
		current_heat_level = 3 
		
	if current_heat_level > _previous_heat_level:
		_pulse_alert_ui()
		match current_heat_level:
			1:
				show_feedback("🚨 WANTED: MAY SUMISIGAW! 🚨", Color.ORANGE, 2.0)
			2:
				show_feedback("🚓 WANTED: HIGH CHASE! 🚓", Color.RED, 2.0)
			3:
				show_feedback("⚠️ WIDE ALERT: INTERCEPTS ACTIVE! ⚠️", Color.DEEP_PINK, 2.5)
				var audio_mgr = get_node_or_null("/root/AudioManager")
				if audio_mgr:
					audio_mgr.play_sfx("siren")
		
	_previous_heat_level = current_heat_level
	_is_max_heat = (current_heat_level == 3)
	
	match current_heat_level:
		0:
			heat_meter.modulate = Color(0.0, 1.0, 0.0) 
		1:
			heat_meter.modulate = Color(1.0, 0.5, 0.0) 
		2:
			heat_meter.modulate = Color(1.0, 0.0, 0.0) 
		3:
			heat_meter.modulate = Color(1.0, 0.0, 0.0) 

func update_loot(total_cash: int, change_amount: int):
	if not is_node_ready():
		await ready
		
	cash_label.text = "CASH: ₱" + str(total_cash)
	if change_amount > 0:
		last_item_label.text = "LAST SNATCH: +₱" + str(change_amount) + " Cash!"
	elif change_amount == 0:
		pass # Retain last message when buying gas
	else:
		last_item_label.text = "LAST SNATCH: None"
	
	var parent_loot_node = $LootSack
	parent_loot_node.pivot_offset = parent_loot_node.size / 2.0
	
	var tween = create_tween()
	tween.tween_property(parent_loot_node, "scale", Vector2(1.1, 1.1), 0.08)
	tween.tween_property(parent_loot_node, "scale", Vector2.ONE, 0.08)

func update_gas_shop(price: int, cooldown_remaining: float, max_cooldown: float):
	if not is_node_ready():
		await ready
		
	if gas_shop_label:
		if cooldown_remaining > 0.0:
			gas_shop_label.text = "REFUEL [SPACE]: %.1fs" % cooldown_remaining
			gas_shop_label.modulate = Color.ORANGE
		else:
			gas_shop_label.text = "REFUEL [SPACE]: ₱%d" % price
			gas_shop_label.modulate = Color.CYAN
			
	if gas_cooldown_bar:
		gas_cooldown_bar.max_value = max_cooldown
		gas_cooldown_bar.value = cooldown_remaining
		gas_cooldown_bar.visible = (cooldown_remaining > 0.0)

func show_game_over(busted: bool):
	if not is_node_ready():
		await ready
		
	game_over_panel.visible = true
	if busted:
		game_over_message.text = "CRASHED OUT! BUSTED!"
	else:
		game_over_message.text = "OUT OF GAS!"
		
	if game_over_restart_btn:
		game_over_restart_btn.grab_focus()

func _on_game_over_restart_pressed() -> void:
	var player = get_tree().current_scene.get_node_or_null("Motorcycle")
	if player and player.has_method("reset_game"):
		player.call("reset_game")
	else:
		get_tree().reload_current_scene()

func _on_game_over_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func reset_hud():
	if not is_node_ready():
		await ready
		
	game_over_panel.visible = false
	_previous_heat_level = 0
	_is_max_heat = false
	feedback_label.text = ""
	_feedback_queue.clear()
	_is_displaying_feedback = false
	qte_panel.visible = false
	if _feedback_tween:
		_feedback_tween.kill()
		
	qte_feedback_label.text = ""
	qte_feedback_label.visible = false
	if _qte_feedback_tween:
		_qte_feedback_tween.kill()  
	update_loot(0, 0)
	update_heat(0, 100)

# --- Visual Juice Helpers (Tweens) ---

func _pulse_alert_ui():
	wanted_level_panel.pivot_offset = wanted_level_panel.size / 2.0
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(wanted_level_panel, "scale", Vector2(1.15, 1.15), 0.15)
	tween.tween_property(wanted_level_panel, "scale", Vector2.ONE, 0.1)

func _shake_gas_meter():
	if _is_gas_shaking:
		return
	_is_gas_shaking = true
	
	if _gas_meter_original_x == 0.0:
		_gas_meter_original_x = gas_meter.position.x
		
	var tween = create_tween()
	tween.tween_property(gas_meter, "position:x", _gas_meter_original_x + 10.0, 0.03)
	tween.tween_property(gas_meter, "position:x", _gas_meter_original_x - 10.0, 0.03)
	tween.tween_property(gas_meter, "position:x", _gas_meter_original_x + 5.0, 0.03)
	tween.tween_property(gas_meter, "position:x", _gas_meter_original_x - 5.0, 0.03)
	tween.tween_property(gas_meter, "position:x", _gas_meter_original_x, 0.03)
	
	await tween.finished
	_is_gas_shaking = false

func _shake_gas_meter_nitro():
	if _is_gas_shaking:
		return
	_is_gas_shaking = true
	
	if _gas_meter_original_x == 0.0:
		_gas_meter_original_x = gas_meter.position.x
		
	var tween = create_tween()
	tween.tween_property(gas_meter, "position:x", _gas_meter_original_x + 2.0, 0.02)
	tween.tween_property(gas_meter, "position:x", _gas_meter_original_x - 2.0, 0.02)
	tween.tween_property(gas_meter, "position:x", _gas_meter_original_x, 0.02)
	
	await tween.finished
	_is_gas_shaking = false

# --- Central Alert & QTE Feedback Banner ---

func show_feedback(text: String, color: Color = Color.WHITE, duration: float = 1.8):
	if not is_node_ready():
		await ready
	_feedback_queue.append({"text": text, "color": color, "duration": duration})
	if not _is_displaying_feedback:
		_process_feedback_queue()

func _process_feedback_queue():
	if _feedback_queue.is_empty():
		_is_displaying_feedback = false
		return
		
	_is_displaying_feedback = true
	var msg = _feedback_queue.pop_front()
	
	feedback_label.text = msg.text
	feedback_label.modulate = msg.color
	feedback_label.modulate.a = 1.0
	
	if _feedback_tween:
		_feedback_tween.kill()
		
	feedback_label.scale = Vector2(1.2, 1.2)
	feedback_label.pivot_offset = feedback_label.size / 2.0
	
	var active_duration = msg.duration
	if _feedback_queue.size() > 0:
		active_duration = clampf(msg.duration * 0.6, 0.8, 1.2)
		
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(feedback_label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_interval(active_duration - 0.45)
	_feedback_tween.tween_property(feedback_label, "modulate:a", 0.0, 0.3)
	
	await _feedback_tween.finished
	_process_feedback_queue()

func show_qte_feedback(text: String, color: Color = Color.WHITE, duration: float = 1.3):
	if not is_node_ready():
		await ready
		
	if _qte_feedback_tween:
		_qte_feedback_tween.kill()
		
	qte_feedback_label.text = text
	qte_feedback_label.modulate = color
	qte_feedback_label.modulate.a = 1.0
	qte_feedback_label.visible = true
	
	qte_feedback_label.pivot_offset = qte_feedback_label.size / 2.0
	qte_feedback_label.scale = Vector2(1.3, 1.3)
	
	_qte_feedback_tween = create_tween()
	_qte_feedback_tween.tween_property(qte_feedback_label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_qte_feedback_tween.tween_interval(duration - 0.3)
	_qte_feedback_tween.tween_property(qte_feedback_label, "modulate:a", 0.0, 0.2)
	_qte_feedback_tween.tween_callback(func(): qte_feedback_label.visible = false)

func _show_low_fuel_warning():
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_fuel_warning_time > 3.0: 
		_last_fuel_warning_time = now
		show_feedback("⚠️ WARNING: LOW GAS TANK! ⚠️", Color.RED, 1.5)

# --- QTE 2D Overlays ---

func start_qte(action_name: String, duration: float):
	if not is_node_ready():
		await ready
		
	var arrow_glyph = ""
	match action_name:
		"ui_up":    arrow_glyph = "↑"
		"ui_down":  arrow_glyph = "↓"
		"ui_left":  arrow_glyph = "←"
		"ui_right": arrow_glyph = "→"
		_:          arrow_glyph = "?"
		
	qte_prompt.text = arrow_glyph
	qte_timer.max_value = duration
	qte_timer.value = duration
	
	_set_qte_color(Color(0.0, 0.9, 1.0))
	qte_panel.visible = true
	
	qte_panel.pivot_offset = qte_panel.size / 2.0
	qte_panel.scale = Vector2(0.3, 0.3)
	qte_panel.modulate.a = 0.0
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(qte_panel, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(qte_panel, "modulate:a", 1.0, 0.08)
	
	await tween.finished
	await get_tree().process_frame
	_qte_panel_original_x = qte_panel.position.x
	
	emit_signal("qte_ready")

func update_qte_timer(time_left: float):
	if not is_node_ready():
		await ready
		
	qte_timer.value = time_left
	var pct = time_left / qte_timer.max_value
	if pct > 0.5:
		_set_qte_color(Color(0.0, 0.9, 1.0))  
	elif pct > 0.2:
		_set_qte_color(Color(1.0, 0.78, 0.0)) 
		_shake_qte_panel(2.0) 
	else:
		_set_qte_color(Color(1.0, 0.15, 0.15))
		_shake_qte_panel(6.0) 
		_pulse_qte_panel_critical()

func _set_qte_color(color: Color):
	qte_arrow_box.modulate = color
	var style = qte_panel.get_theme_stylebox("panel").duplicate()
	style.border_color = color
	style.shadow_color = Color(color.r, color.g, color.b, 0.35)
	qte_panel.add_theme_stylebox_override("panel", style)

func _shake_qte_panel(amplitude: float):
	if _is_qte_panel_shaking:
		return
	_is_qte_panel_shaking = true
	
	if _qte_panel_original_x == 0.0:
		_qte_panel_original_x = qte_panel.position.x
		
	var tween = create_tween()
	tween.tween_property(qte_panel, "position:x", _qte_panel_original_x + amplitude, 0.03)
	tween.tween_property(qte_panel, "position:x", _qte_panel_original_x - amplitude, 0.03)
	tween.tween_property(qte_panel, "position:x", _qte_panel_original_x, 0.03)
	
	await tween.finished
	_is_qte_panel_shaking = false

func _pulse_qte_panel_critical():
	if _is_qte_pulsing:
		return
	_is_qte_pulsing = true
	
	var tween = create_tween()
	tween.tween_property(qte_panel, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(qte_panel, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	await tween.finished
	_is_qte_pulsing = false

func hide_qte():
	if not is_node_ready():
		await ready
		
	_is_qte_panel_shaking = false
	_is_qte_pulsing = false
	if _qte_panel_original_x != 0.0:
		qte_panel.position.x = _qte_panel_original_x
		
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(qte_panel, "scale", Vector2(0.5, 0.5), 0.1)
	await tween.finished
	
	if qte_panel.scale.x < 0.6:
		qte_panel.visible = false
		qte_panel.scale = Vector2.ONE
