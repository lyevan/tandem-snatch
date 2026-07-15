extends Node

# A dedicated player for background music so it can loop seamlessly
var _bgm_player: AudioStreamPlayer = AudioStreamPlayer.new()

func _ready() -> void:
	add_child(_bgm_player)
	_bgm_player.bus = "Music" # Optional: Change to "Master" if you haven't set up buses yet

## Plays a sound effect once and automatically cleans up the player when finished.
## Returns the AudioStreamPlayer so you can store a reference to stop/fade it later!
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0, pitch_variance: float = 0.0) -> AudioStreamPlayer:
	if not stream:
		return null
		
	var sfx_player := AudioStreamPlayer.new()
	sfx_player.stream = stream
	sfx_player.volume_db = volume_db
	
	if pitch_variance > 0.0:
		sfx_player.pitch_scale = pitch_scale + randf_range(-pitch_variance, pitch_variance)
	else:
		sfx_player.pitch_scale = pitch_scale
		
	sfx_player.bus = "SFX"
	
	add_child(sfx_player)
	sfx_player.play()
	
	# Automatically delete the node once the audio finishes playing naturally
	sfx_player.finished.connect(sfx_player.queue_free)
	
	return sfx_player

## Stops a specific sound effect with an optional fade-out duration (in seconds).
func stop_sfx(player: AudioStreamPlayer, fade_duration: float = 0.5) -> void:
	# Safety check: ensure the node still exists and is currently playing
	if not is_instance_valid(player) or not player.playing:
		return
		
	# If no fade is requested, snap it off instantly
	if fade_duration <= 0.0:
		player.stop()
		player.queue_free()
		return
		
	# Create a tween to smoothly fade volume_db down to silence (-50 dB is practically silent)
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -50.0, fade_duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_callback(player.stop)
	tween.tween_callback(player.queue_free)

## Stops ALL currently playing sound effects with an optional fade-out.
func stop_all_sfx(fade_duration: float = 0.5) -> void:
	for child in get_children():
		# Ignore the BGM player, only target temporary SFX players
		if child is AudioStreamPlayer and child != _bgm_player:
			stop_sfx(child, fade_duration)

## Plays background music. If the same track is already playing, it won't restart.
func play_bgm(stream: AudioStream, volume_db: float = 0.0) -> void:
	if not stream:
		return
		
	if _bgm_player.stream == stream and _bgm_player.playing:
		return
		
	_bgm_player.stream = stream
	_bgm_player.volume_db = volume_db
	_bgm_player.play()

## Stops the currently playing background music with an optional fade-out.
func stop_bgm(fade_duration: float = 0.0) -> void:
	if not _bgm_player.playing:
		return
		
	if fade_duration <= 0.0:
		_bgm_player.stop()
	else:
		var tween := create_tween()
		tween.tween_property(_bgm_player, "volume_db", -50.0, fade_duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		tween.tween_callback(_bgm_player.stop)

## Instantly restarts whatever background music is currently loaded from timestamp 0:00.
func restart_bgm() -> void:
	if _bgm_player.stream:
		_bgm_player.play(0.0)
