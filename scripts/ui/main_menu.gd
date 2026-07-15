extends Control

# --- Node References ---
@onready var main_buttons_container = $CenterContainer/MainButtons
@onready var play_button = $CenterContainer/MainButtons/PlayButton
@onready var controls_button = $CenterContainer/MainButtons/ControlsButton
@onready var settings_button = $CenterContainer/MainButtons/SettingsButton
@onready var credits_button = $CenterContainer/MainButtons/CreditsButton
@onready var quit_button = $CenterContainer/MainButtons/QuitButton

@onready var settings_overlay = $SettingsOverlay
@onready var master_slider = $SettingsOverlay/VBox/SliderGrid/MasterSlider
@onready var music_slider = $SettingsOverlay/VBox/SliderGrid/MusicSlider
@onready var sfx_slider = $SettingsOverlay/VBox/SliderGrid/SFXSlider
@onready var settings_back_button = $SettingsOverlay/VBox/BackButton

@onready var credits_overlay = $CreditsOverlay
@onready var credits_back_button = $CreditsOverlay/VBox/BackButton

@onready var tutorial_overlay = $TutorialOverlay
@onready var tutorial_back_button = $TutorialOverlay/VBox/BackButton

@onready var quit_confirm_overlay = $QuitConfirmOverlay
@onready var quit_yes_button = $QuitConfirmOverlay/VBox/HBox/YesButton
@onready var quit_no_button = $QuitConfirmOverlay/VBox/HBox/NoButton

@onready var transition_overlay = $TransitionOverlay

# Cache AudioManager locally if it is loaded
var _audio_mgr = null

func _ready() -> void:
	# Lookup AudioManager autoload safely without crashing if it's not registered
	_audio_mgr = get_node_or_null("/root/AudioManager")
	Audio.play_bgm(preload("res://assets/bgm/main_menu.mp3"))
	# Hide sub-panels by default
	settings_overlay.visible = false
	credits_overlay.visible = false
	tutorial_overlay.visible = false
	quit_confirm_overlay.visible = false
	main_buttons_container.visible = true
	
	# Transition overlay setup: start fully transparent and visible
	transition_overlay.visible = true
	transition_overlay.color.a = 0.0
	
	# Connect signals
	play_button.pressed.connect(_on_play_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	settings_back_button.pressed.connect(_on_settings_back_pressed)
	credits_back_button.pressed.connect(_on_credits_back_pressed)
	tutorial_back_button.pressed.connect(_on_tutorial_back_pressed)
	
	quit_yes_button.pressed.connect(_on_quit_confirmed)
	quit_no_button.pressed.connect(_on_quit_cancelled)
	
	# Set up volume slider defaults
	_init_volume_sliders()
	
	# Hook up button sound effects recursively
	_setup_button_sounds(self)
	
	# Grab initial focus for keyboard control
	play_button.grab_focus()
	
	# Start Main Menu BGM
	if _audio_mgr:
		_audio_mgr.play_bgm("menu")

func _setup_button_sounds(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.mouse_entered.connect(func(): if _audio_mgr: _audio_mgr.play_sfx("hover"))
			child.focus_entered.connect(func(): if _audio_mgr: _audio_mgr.play_sfx("hover"))
			if child != play_button: # Play button has press sound on transition
				child.pressed.connect(func(): if _audio_mgr: _audio_mgr.play_sfx("press"))
		elif child.get_child_count() > 0:
			_setup_button_sounds(child)

func _init_volume_sliders() -> void:
	if _audio_mgr:
		master_slider.value = _audio_mgr._get_bus_volume("Master")
		music_slider.value = _audio_mgr._get_bus_volume("Music")
		sfx_slider.value = _audio_mgr._get_bus_volume("SFX")
	
	master_slider.value_changed.connect(func(val): if _audio_mgr: _audio_mgr._set_bus_volume("Master", val))
	music_slider.value_changed.connect(func(val): if _audio_mgr: _audio_mgr._set_bus_volume("Music", val))
	sfx_slider.value_changed.connect(func(val): if _audio_mgr: _audio_mgr._set_bus_volume("SFX", val))

# --- Button Handlers ---

func _on_play_pressed() -> void:
	# Block button focus inputs during transition
	play_button.release_focus()
	
	# Play select/start SFX and stop BGM
	if _audio_mgr:
		_audio_mgr.play_sfx("press")
		_audio_mgr.stop_bgm()
	
	Audio.stop_bgm()
	Audio.play_bgm(preload("res://assets/bgm/main.mp3"))
	# Fade-out screen transition
	var tween = create_tween()
	tween.tween_property(transition_overlay, "color:a", 1.0, 0.5)
	tween.tween_callback(func(): get_tree().change_scene_to_file("res://main.tscn"))

func _on_controls_pressed() -> void:
	main_buttons_container.visible = false
	tutorial_overlay.visible = true
	tutorial_back_button.grab_focus()

func _on_tutorial_back_pressed() -> void:
	tutorial_overlay.visible = false
	main_buttons_container.visible = true
	controls_button.grab_focus()

func _on_settings_pressed() -> void:
	main_buttons_container.visible = false
	settings_overlay.visible = true
	settings_back_button.grab_focus()

func _on_settings_back_pressed() -> void:
	settings_overlay.visible = false
	main_buttons_container.visible = true
	settings_button.grab_focus()

func _on_credits_pressed() -> void:
	main_buttons_container.visible = false
	credits_overlay.visible = true
	credits_back_button.grab_focus()

func _on_credits_back_pressed() -> void:
	credits_overlay.visible = false
	main_buttons_container.visible = true
	credits_button.grab_focus()

func _on_quit_pressed() -> void:
	main_buttons_container.visible = false
	quit_confirm_overlay.visible = true
	quit_no_button.grab_focus()

func _on_quit_confirmed() -> void:
	if _audio_mgr:
		_audio_mgr.play_sfx("press")
	get_tree().quit()

func _on_quit_cancelled() -> void:
	quit_confirm_overlay.visible = false
	main_buttons_container.visible = true
	quit_button.grab_focus()
