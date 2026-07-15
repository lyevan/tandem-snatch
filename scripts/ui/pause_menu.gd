extends Control

# --- Node References ---
@onready var pause_container = $PanelContainer
@onready var resume_button = $PanelContainer/VBox/ResumeButton
@onready var restart_button = $PanelContainer/VBox/RestartButton
@onready var menu_button = $PanelContainer/VBox/MenuButton
@onready var quit_button = $PanelContainer/VBox/QuitButton

@onready var confirm_overlay = $ConfirmOverlay
@onready var confirm_prompt = $ConfirmOverlay/VBox/ConfirmPrompt
@onready var yes_button = $ConfirmOverlay/VBox/HBox/YesButton
@onready var no_button = $ConfirmOverlay/VBox/HBox/NoButton

# Tracks what action we are confirming: "menu" or "quit"
var _pending_action: String = ""

# Cache AudioManager locally if it is loaded
var _audio_mgr = null

func _ready() -> void:
	# Lookup AudioManager autoload safely without crashing if it's not registered
	_audio_mgr = get_node_or_null("/root/AudioManager")

	# Hide by default
	visible = false
	confirm_overlay.visible = false
	pause_container.visible = true
	process_mode = Node.PROCESS_MODE_ALWAYS # Crucial: runs when game is paused
	
	# Connect signals
	resume_button.pressed.connect(resume_game)
	restart_button.pressed.connect(restart_game)
	menu_button.pressed.connect(_on_menu_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	yes_button.pressed.connect(_on_confirm_yes)
	no_button.pressed.connect(_on_confirm_no)
	
	# Hook up button sound effects recursively
	_setup_button_sounds(self)

func _setup_button_sounds(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.mouse_entered.connect(func(): if _audio_mgr: _audio_mgr.play_sfx("hover"))
			child.focus_entered.connect(func(): if _audio_mgr: _audio_mgr.play_sfx("hover"))
			if child != resume_button: # Resume will play press on unpause
				child.pressed.connect(func(): if _audio_mgr: _audio_mgr.play_sfx("press"))
		elif child.get_child_count() > 0:
			_setup_button_sounds(child)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		var hud = get_tree().current_scene.get_node_or_null("HUD")
		if hud and hud.has_node("GameOverPanel") and hud.get_node("GameOverPanel").visible:
			return
			
		if visible:
			if confirm_overlay.visible:
				_on_confirm_no()
			else:
				resume_game()
		else:
			pause_game()

func pause_game() -> void:
	var player = get_tree().current_scene.get_node_or_null("Motorcycle")
	if player and player.get("is_busted"):
		return
		
	get_tree().paused = true
	visible = true
	confirm_overlay.visible = false
	pause_container.visible = true
	resume_button.grab_focus()
	if _audio_mgr:
		_audio_mgr.play_sfx("press")

func resume_game() -> void:
	if _audio_mgr:
		_audio_mgr.play_sfx("press")
	get_tree().paused = false
	visible = false

func restart_game() -> void:
	get_tree().paused = false
	visible = false
	
	var player = get_tree().current_scene.get_node_or_null("Motorcycle")
	if player and player.has_method("reset_game"):
		player.call("reset_game")
	else:
		get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	_pending_action = "menu"
	confirm_prompt.text = "BABALIK SA MENU?"
	pause_container.visible = false
	confirm_overlay.visible = true
	no_button.grab_focus()

func _on_quit_pressed() -> void:
	_pending_action = "quit"
	confirm_prompt.text = "SIGURADO KA BA?"
	pause_container.visible = false
	confirm_overlay.visible = true
	no_button.grab_focus()

func _on_confirm_yes() -> void:
	if _audio_mgr:
		_audio_mgr.play_sfx("press")
		
	get_tree().paused = false
	if _pending_action == "menu":
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	elif _pending_action == "quit":
		get_tree().quit()

func _on_confirm_no() -> void:
	confirm_overlay.visible = false
	pause_container.visible = true
	if _pending_action == "menu":
		menu_button.grab_focus()
	elif _pending_action == "quit":
		quit_button.grab_focus()
	_pending_action = ""
