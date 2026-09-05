extends SceneTree

var failures: Array[String] = []

func _initialize():
	_run.call_deferred()

func _check(condition: bool, message: String):
	if not condition:
		failures.append(message)
		push_error(message)

func _run():
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i.ZERO
	root.notify_mouse_entered()
	var scene := load("res://scenes/main.tscn") as PackedScene
	for count in range(1, 5):
		var game = scene.instantiate()
		root.add_child(game)
		await process_frame
		var title = game.title_screen
		_check(is_instance_valid(title), "Title screen must initialize")
		if not is_instance_valid(title):
			game.queue_free()
			await process_frame
			continue
		_check(title.choices.size() == 4, "All four player counts must be visible")
		_check(game.grid.is_empty(), "Title scenery must not populate the gameplay board")
		var instance_count := 0
		for child in title.world.get_children():
			if child is MultiMeshInstance3D: instance_count += child.multimesh.instance_count
		_check(instance_count > 361, "Batched background must retain the terrain meshes")
		for dimensions in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1080), Vector2(390, 844), Vector2(844, 390)]:
			title.size = dimensions
			title._layout()
			var previous := Rect2()
			for button in title.choices:
				var bounds: Rect2 = button.get_rect()
				_check(Rect2(Vector2.ZERO, dimensions).encloses(bounds), "Player button exceeds viewport %s" % dimensions)
				_check(not previous.intersects(bounds), "Player buttons overlap at %s" % dimensions)
				_check(title.tagline.get_rect().end.y < bounds.position.y, "Title overlaps choices at %s" % dimensions)
				previous = bounds
			for viewport in title.previews:
				_check(viewport.size.x == viewport.size.y, "Preview models must keep square render targets")
		title._toggle_music(true)
		_check(game.get_node("BackgroundMusic").volume_db == -80.0, "Music must mute")
		title._toggle_music(false)
		_check(game.get_node("BackgroundMusic").volume_db == -12.0, "Music must restore volume")
		var old_world: Node3D = title.world
		title.size = root.get_visible_rect().size
		title._layout()
		if count == 1 or count == 4:
			var pointer: Vector2 = title.choices[count - 1].get_global_rect().get_center()
			var motion := InputEventMouseMotion.new()
			motion.position = pointer; motion.global_position = pointer
			root.push_input(motion, true)
			for pressed in [true, false]:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT; click.pressed = pressed
				click.position = pointer; click.global_position = pointer
				root.push_input(click, true)
		else:
			var key := InputEventKey.new()
			key.keycode = KEY_ENTER if count == 2 else KEY_3
			key.pressed = true
			root.push_input(key)
		_check(title.leaving, "Input must reach the %d-player start control" % count)
		title._choose(4 if count != 4 else 1)
		await create_timer(0.3).timeout
		_check(game.player_count == count, "Repeated click must not change the chosen player count")
		_check(game.state == game.S.DRAW_CARDS, "Start must enter the draw phase")
		_check(game.hands.size() == count, "Start must initialize the correct number of hands")
		_check(game.draws_remaining == 3, "First turn must allow three draws")
		_check(not is_instance_valid(old_world), "Title scenery must be freed on start")
		_check(not is_instance_valid(game.title_screen), "Title previews must be freed on start")
		game.get_node("BackgroundMusic").stop()
		await create_timer(0.1).timeout
		game.queue_free()
		await process_frame
		await process_frame
	print("Title smoke test: %d failure(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)
