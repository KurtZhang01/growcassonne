extends SceneTree

class TestGame:
	extends "res://scripts/main3d.gd"
	var grants := 0
	func _grant_seed_card(_player_id: int, _level: int = 1, _reason: String = ""):
		grants += 1

func _initialize():
	var game := TestGame.new()
	for x in range(7):
		var column := []
		for y in range(7): column.append(game.T_MOUNTAIN)
		game.grid.append(column)
	var shape := [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3)]
	assert(not game._can_develop_cells(shape), "Isolated L must be rejected")
	game.grid[1][2] = -1
	assert(not game._can_develop_cells(shape), "Empty cells are not developed neighbors")
	game.grid[1][2] = game.T_MOUNTAIN
	game.grid[1][1] = game.T_GRASS
	assert(not game._can_develop_cells(shape), "Diagonal contact is insufficient")
	game.grid[1][2] = game.T_GRASS
	assert(game._can_develop_cells(shape), "Shared edge with grass permits L placement")
	game.grid[2][2] = game.T_GAP
	assert(not game._can_develop_cells(shape), "Development cannot overwrite a gap")
	game.grid[2][2] = game.T_GRASS
	game._reward_developed_buildings(shape)
	assert(game.grants == 0, "Ordinary terrain must not award seed cards")
	game.grid[2][2] = game.T_BUILDING
	game._reward_developed_buildings(shape)
	assert(game.grants == 1, "A generated building awards one card")
	game.ui_preview_mode = "tile"
	game.selected_tile = Vector2i(2, 2)
	assert(not game._flower_chart_visible(), "Buildings have no flower chart")
	game.grid[2][2] = game.T_FOREST
	assert(game._flower_chart_visible(), "Plant terrain retains the flower chart")
	assert(game._landmark_name("hust") == "华中科技大学")
	assert(game._landmark_name("wuhan_university") == "武汉大学")
	game.free()
	print("Building rule regressions passed")
	quit()
