extends Node

signal settings_changed

const CUES := ["select", "draw", "cancel", "rotate", "seed", "develop", "build", "road", "weather", "rainbow", "warning", "reward", "turn", "victory", "thunder"]
const LOOPS := ["rain", "storm", "sand", "dry"]
const PRIORITY := {"select": 0, "rotate": 0, "draw": 1, "cancel": 1, "warning": 3, "reward": 4, "victory": 5}
const SETTINGS_PATH := "user://audio_settings.cfg"

var suspended := false
var persist_settings := true
var music_muted := false
var muted := false
var music_volume := db_to_linear(-12.0)
var effects_volume := 0.7
var ambience_volume := 0.65
var streams: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var ambience: Dictionary = {}
var fades: Dictionary = {}
var last_played: Dictionary = {}
var weather: Dictionary = {}
var music: AudioStreamPlayer
var thunder: AudioStreamPlayer
var thunder_time := 12.0
var rng := RandomNumberGenerator.new()
var settings_button: Button
var panel: PanelContainer
var settings_layer: CanvasLayer
var sliders: Dictionary = {}

func _ready():
	name = "GameAudio"
	rng.randomize()
	_load_settings()
	for cue in CUES:
		streams[cue] = load("res://assets/audio/%s.wav" % cue)
	for index in 6:
		var voice := AudioStreamPlayer.new()
		add_child(voice); voices.append(voice)
	for key in LOOPS:
		var player := AudioStreamPlayer.new()
		var stream := load("res://assets/audio/%s.wav" % key) as AudioStreamWAV
		var sample_count: int = roundi(stream.get_length() * stream.mix_rate)
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		# Imported WAVs may be compressed; loop points count decoded samples, not bytes.
		stream.loop_end = sample_count
		player.stream = stream; player.volume_db = -80.0
		add_child(player); ambience[key] = player
	thunder = AudioStreamPlayer.new(); thunder.stream = streams["thunder"]
	add_child(thunder)
	_build_settings()

func attach_music(player: AudioStreamPlayer):
	music = player
	_refresh_volumes()

func play_cue(cue: String) -> bool:
	if suspended or muted or effects_volume <= 0.0 or not streams.has(cue): return false
	var now := Time.get_ticks_msec() * 0.001
	var cooldown := 0.65 if cue == "warning" else (0.28 if cue == "reward" else 0.075)
	if now - float(last_played.get(cue, -10.0)) < cooldown: return false
	var priority: int = PRIORITY.get(cue, 2)
	var available: AudioStreamPlayer
	for voice in voices:
		if not voice.playing:
			available = voice
			break
		if int(voice.get_meta("priority", 0)) <= priority:
			if available == null or float(voice.get_meta("started", 0.0)) < float(available.get_meta("started", 0.0)):
				available = voice
	if available == null: return false
	last_played[cue] = now
	available.stop()
	available.stream = streams[cue]
	available.volume_db = linear_to_db(effects_volume) - 8.0
	available.pitch_scale = 1.0 if cue in ["warning", "reward", "turn", "victory", "rainbow"] else rng.randf_range(0.96, 1.04)
	available.set_meta("priority", priority); available.set_meta("started", now)
	available.play()
	return true

func play_card(card: Dictionary):
	var kind := str(card.get("kind", ""))
	if kind == "weather":
		play_cue("rainbow" if card.get("weather", "") == "彩虹" else "weather")
	else:
		play_cue(str({"seed": "seed", "develop": "develop", "building_develop": "build", "road": "road"}.get(kind, "select")))

func set_weather(active: Dictionary):
	weather = active.duplicate()
	if not weather.has("台风"):
		thunder.stop()
		thunder_time = rng.randf_range(12.0, 20.0)
	_refresh_ambience()

func _refresh_ambience():
	var targets := {
		"rain": -8.0 if weather.has("台风") else -11.0,
		"storm": -10.0, "sand": -10.0, "dry": -12.0,
	}
	var enabled := {
		"rain": weather.has("雨季") or weather.has("台风"),
		"storm": weather.has("台风"), "sand": weather.has("沙尘暴"), "dry": weather.has("旱季"),
	}
	for key in LOOPS:
		var player: AudioStreamPlayer = ambience[key]
		if fades.has(key):
			var previous: Tween = fades[key]
			if previous.is_valid(): previous.kill()
		if muted:
			player.stop()
			player.volume_db = -80.0
			continue
		var audible: bool = enabled[key] and not muted and ambience_volume > 0.0
		var target: float = float(targets[key]) + linear_to_db(maxf(ambience_volume, 0.001)) if audible else -80.0
		if audible and not player.playing:
			player.volume_db = -80.0
			player.play(rng.randf_range(0.0, 6.0))
		var fade := create_tween()
		fades[key] = fade
		fade.tween_property(player, "volume_db", target, 0.8).set_trans(Tween.TRANS_SINE)
		if not audible: fade.tween_callback(player.stop)

func _process(delta: float):
	_layout_settings()
	if weather.has("台风") and not muted and ambience_volume > 0.0:
		thunder_time -= delta
		if thunder_time <= 0.0:
			thunder.volume_db = linear_to_db(ambience_volume) - 8.0
			thunder.play()
			thunder_time = rng.randf_range(18.0, 34.0)

func set_music_muted(value: bool):
	music_muted = value
	if not value and music_volume <= 0.0:
		music_volume = db_to_linear(-12.0)
		sliders["music"].set_value_no_signal(music_volume * 100.0)
	_refresh_volumes()
	_save_settings()

func set_volume(category: String, value: float):
	value = clampf(value, 0.0, 1.0)
	match category:
		"music": music_volume = value; music_muted = false
		"effects": effects_volume = value
		"ambience": ambience_volume = value
	_refresh_volumes()
	_save_settings()

func _refresh_volumes():
	if is_instance_valid(music):
		music.volume_db = -80.0 if muted or music_muted or music_volume <= 0.0 else linear_to_db(music_volume)
	for voice in voices:
		if muted or effects_volume <= 0.0: voice.stop()
		else: voice.volume_db = linear_to_db(effects_volume) - 8.0
	if muted or ambience_volume <= 0.0: thunder.stop()
	else: thunder.volume_db = linear_to_db(ambience_volume) - 8.0
	_refresh_ambience()
	settings_changed.emit()

func _load_settings():
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK: return
	music_volume = clampf(float(config.get_value("audio", "music", music_volume)), 0.0, 1.0)
	effects_volume = clampf(float(config.get_value("audio", "effects", effects_volume)), 0.0, 1.0)
	ambience_volume = clampf(float(config.get_value("audio", "ambience", ambience_volume)), 0.0, 1.0)
	music_muted = bool(config.get_value("audio", "music_muted", false))
	muted = bool(config.get_value("audio", "muted", false))

func _save_settings():
	if not persist_settings: return
	var config := ConfigFile.new()
	for key in ["music", "effects", "ambience"]:
		config.set_value("audio", key, get(key + "_volume"))
	config.set_value("audio", "music_muted", music_muted)
	config.set_value("audio", "muted", muted)
	config.save(SETTINGS_PATH)

func _build_settings():
	settings_layer = CanvasLayer.new(); settings_layer.layer = 30
	add_child(settings_layer)
	settings_button = Button.new()
	settings_button.icon = preload("res://assets/ui/audio-settings.svg")
	settings_button.tooltip_text = "声音设置"
	settings_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	settings_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	settings_button.pressed.connect(func(): panel.visible = not panel.visible)
	settings_layer.add_child(settings_button)
	panel = PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.22, 0.22, 0.22, 0.96)
	background.set_corner_radius_all(8)
	background.content_margin_left = 18.0; background.content_margin_right = 18.0
	background.content_margin_top = 14.0; background.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", background)
	settings_layer.add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var heading := Label.new(); heading.text = "声音设置"; column.add_child(heading)
	for category in ["music", "effects", "ambience"]:
		var label := Label.new()
		label.text = {"music": "背景音乐", "effects": "操作与提示", "ambience": "天气环境"}[category]
		column.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0; slider.max_value = 100; slider.step = 1
		slider.value = float(get(category + "_volume")) * 100.0
		slider.custom_minimum_size = Vector2(204, 22)
		slider.value_changed.connect(_on_slider_changed.bind(category))
		sliders[category] = slider; column.add_child(slider)
	var mute := CheckButton.new(); mute.text = "全部静音"; mute.button_pressed = muted
	mute.toggled.connect(func(value: bool): muted = value; _refresh_volumes(); _save_settings())
	column.add_child(mute)
	panel.hide()

func _on_slider_changed(value: float, category: String):
	set_volume(category, value / 100.0)

func _layout_settings():
	var viewport_size := get_viewport().get_visible_rect().size
	var game = get_parent()
	var title: bool = game.state == game.S.TITLE
	var scale: float = 1.0 if title else game._ui_scale(viewport_size)
	settings_button.scale = Vector2.ONE * scale
	settings_button.size = Vector2(36, 36)
	settings_button.position = Vector2(viewport_size.x - (120.0 if title else 59.0 * scale), 20.0 if title else 27.0 * scale)
	panel.scale = Vector2.ONE * scale
	panel.position = Vector2(maxf(8.0, viewport_size.x - 258.0 * scale), settings_button.position.y + 42.0 * scale)

func pointer_over_settings(point: Vector2) -> bool:
	return settings_button.get_global_rect().has_point(point) or (panel.visible and panel.get_global_rect().has_point(point))

func _input(event: InputEvent):
	if not panel.visible: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		panel.hide(); get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not pointer_over_settings(event.position):
		panel.hide()
		get_viewport().set_input_as_handled()

func _exit_tree():
	for voice in voices: voice.stop()
	for player in ambience.values(): player.stop()
	if is_instance_valid(thunder): thunder.stop()
