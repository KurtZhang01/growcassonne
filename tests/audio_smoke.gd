extends SceneTree

var failures: Array[String] = []

func _initialize():
	_run.call_deferred()

func _check(value: bool, message: String):
	if not value:
		failures.append(message)
		push_error(message)

func _arm(game, card: Dictionary):
	game.current_hand.clear()
	game.current_hand.append(card)
	game._begin_card_drag(0)
	game.dragging_card = false
	game.card_armed = true

func _run():
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var sound = game.game_audio
	sound.persist_settings = false
	sound.muted = false
	sound.effects_volume = 0.7
	sound.ambience_volume = 0.65
	await game._start_game_from_title(2)
	await process_frame
	root.notify_mouse_entered()
	var before_history: int = game.action_history.size()
	var pointer: Vector2 = sound.settings_button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = pointer; root.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = pointer; click.button_index = MOUSE_BUTTON_LEFT; click.pressed = pressed
		root.push_input(click, true)
	_check(sound.panel.visible, "Sound settings button must open its panel")
	_check(game.action_history.size() == before_history, "Sound settings must not trigger a board warning")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	root.push_input(escape)
	_check(not sound.panel.visible, "Escape must dismiss sound settings")
	sound.sliders["music"].value = 30.0
	_check(is_equal_approx(sound.music_volume, 0.3), "Music slider must update music volume")
	_check(is_equal_approx(sound.effects_volume, 0.7), "Music slider must not change effects volume")
	_check(sound.streams.size() == 15, "All operation cues must load")
	for stream in sound.streams.values(): _check(stream != null, "Cue resource must exist")
	for player in sound.ambience.values():
		_check(player.stream.loop_end == 12 * player.stream.mix_rate, "Ambience must loop all decoded samples, including compressed imports")
	sound.last_played.clear()
	_check(sound.play_cue("warning"), "First warning must play")
	_check(not sound.play_cue("warning"), "Repeated warnings must be throttled")
	game._take_card_from_deck(0)
	_check(sound.last_played.has("draw"), "Successful draw must play a cue")
	game.state = game.S.PLAY_CARDS
	var target := Vector2i(3, 3)
	game._set_tile_type(target, game.T_GRASS, false, 0)
	sound.last_played.clear()
	_arm(game, game._make_seed_card(1))
	game._finish_card_drag(target)
	_check(sound.last_played.has("seed"), "Successful sowing must play seed audio")
	sound.last_played.clear()
	_arm(game, game._make_seed_card(1))
	game._finish_card_drag(Vector2i(0, 0))
	_check(not sound.last_played.has("seed"), "Invalid sowing must not sound successful")
	_check(sound.last_played.has("warning"), "Invalid sowing must warn")
	game._cancel_armed_card()
	game._set_tile_type(target, game.T_GAP, false, 0)
	sound.last_played.clear()
	_arm(game, {"kind": "building_develop", "name": "图书馆", "level": 1, "landmark": "library"})
	game._finish_card_drag(target)
	_check(sound.last_played.has("build"), "Successful building must play construction audio")
	_check(sound.last_played.has("reward"), "Building reward must have a notification")
	game._apply_weather_card({"weather": "雨季"})
	await create_timer(0.9).timeout
	_check(sound.ambience["rain"].playing, "Rain must loop while the rainy season is active")
	game._apply_weather_card({"weather": "台风"})
	await create_timer(0.9).timeout
	_check(sound.ambience["rain"].playing and sound.ambience["storm"].playing, "Typhoon layers rain and wind")
	game._apply_weather_card({"weather": "旱季"})
	await create_timer(0.9).timeout
	_check(not sound.ambience["rain"].playing and not sound.ambience["storm"].playing, "Drought must remove wet ambience")
	_check(sound.ambience["dry"].playing, "Drought must have its own ambience")
	game._apply_weather_card({"weather": "彩虹"})
	await create_timer(0.9).timeout
	for player in sound.ambience.values(): _check(not player.playing, "Rainbow must fade all extreme-weather loops")
	game._apply_weather_card({"weather": "沙尘暴"})
	game._apply_weather_card({"weather": "雨季"})
	await create_timer(0.9).timeout
	_check(sound.ambience["rain"].playing and sound.ambience["sand"].playing, "Compatible weather must retain both layers")
	sound.set_volume("ambience", 0.0)
	await create_timer(0.9).timeout
	for player in sound.ambience.values(): _check(not player.playing, "Zero ambience volume must stop loops")
	sound.set_volume("ambience", 0.65)
	await create_timer(0.9).timeout
	_check(sound.ambience["sand"].playing, "Restoring volume must resume current weather")
	for turn in 3: game._tick_weather()
	await create_timer(0.9).timeout
	for player in sound.ambience.values(): _check(not player.playing, "Expired weather must stop ambience")
	sound.set_weather({"雨季": 3})
	await create_timer(0.1).timeout
	sound.muted = true
	sound._refresh_volumes()
	for player in sound.ambience.values(): _check(not player.playing, "Master mute must stop weather immediately")
	_check(not sound.play_cue("seed"), "Master mute must suppress operation cues")
	_check(game.get_node("BackgroundMusic").volume_db == -80.0, "Master mute must suppress music")
	sound.set_weather({})
	game.get_node("BackgroundMusic").stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await process_frame
	print("Audio smoke test: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
