extends SceneTree

func _initialize():
	_run.call_deferred()

func _run():
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.game_audio.persist_settings = false
	var title_world = game.title_screen.world
	await game._start_game_from_title(2)
	assert(not is_instance_valid(title_world), "Title scenery must be freed before play")
	var cell := Vector2i(3, 3)
	var position: Vector3 = game._world(cell)
	for index in 3:
		game._expand_board_ring()
		cell += Vector2i.ONE
		assert(game._world(cell).is_equal_approx(position), "Expansion moved world coordinates")
	game.state = game.S.PLAY_CARDS
	game.current_hand = [{"kind": "develop", "level": 2, "shape": 0, "name": "Test", "deck": "Test"}]
	game._begin_card_drag(0)
	game._update_card_drag_preview(cell)
	assert(game.piece_preview_root.get_child_count() == 2)
	var first = game.piece_preview_root.get_child(0)
	for index in 20: game._update_card_drag_preview(cell)
	assert(game.piece_preview_root.get_child(0) == first, "Unchanged preview rebuilt models")
	game.pending_develop = {"terrains": [], "roads": []}
	assert(not game._apply_pending_develop(cell, game.current_hand[0]), "Incomplete preview data accepted")
	game._cancel_armed_card()
	game.game_audio.music.stop()
	await create_timer(0.1).timeout
	game.queue_free()
	await process_frame
	await process_frame
	print("Placement regression passed")
	quit()
