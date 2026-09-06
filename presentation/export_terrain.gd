extends SceneTree

class AssetGame:
	extends "res://scripts/main3d.gd"
	func _ready(): pass

func _initialize():
	_run.call_deferred()

func _collect(node: Node3D, transform: Transform3D, output: Array):
	var world := transform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var color := Color("#3f94bd")
		if node.material_override is StandardMaterial3D:
			color = node.material_override.albedo_color
		var faces: PackedVector3Array = node.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var triangle := []
			for j in 3:
				var point: Vector3 = world * faces[i + j]
				triangle.append([point.x, point.y, point.z])
			output.append([triangle, [color.r, color.g, color.b, color.a]])
	for child in node.get_children():
		if child is Node3D: _collect(child, world, output)

func _run():
	seed(42)
	var game = AssetGame.new()
	root.add_child(game)
	game.set_process(false)
	for i in 7:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = game.TERRAIN_TOP[i]
		game.edge_materials[i] = mat
	var models := {}
	for terrain in [0, 1, 2, 3, 4, 5, 6]:
		var model := Node3D.new()
		root.add_child(model)
		game._spawn_island_base(model, terrain)
		match terrain:
			0: game._tile_grass_surface(model, 0)
			1: game._tile_water_surface(model, 0)
			2: game._tile_forest_surface(model, 0)
			3: game._tile_desert_surface(model, 0)
			5: game._tile_mountain_surface(model)
			6: game._tile_gap_surface(model)
		game._spawn_decor(terrain, model, 0)
		var triangles := []
		_collect(model, Transform3D.IDENTITY, triangles)
		models[str(terrain)] = triangles
		model.free()
	var road_model := Node3D.new()
	root.add_child(road_model)
	game._spawn_island_base(road_model, 0)
	game._tile_grass_surface(road_model, 10)
	game._spawn_decor(0, road_model, 10)
	game._spawn_road(road_model, 10)
	var road_faces := []
	_collect(road_model, Transform3D.IDENTITY, road_faces)
	models["road"] = road_faces
	road_model.free()
	game.roads = [[0]]
	for owner in 4:
		var container := Node3D.new()
		root.add_child(container)
		var flower: Node3D = game._create_flower_instance(Vector2i.ZERO, owner, container)
		container.add_child(flower)
		flower.position = Vector3.ZERO
		flower.scale = Vector3.ONE
		var triangles := []
		_collect(container, Transform3D.IDENTITY, triangles)
		models["flower" + str(owner)] = triangles
		for tween in get_processed_tweens(): tween.kill()
		container.free()
	var file := FileAccess.open("res://presentation/terrain_meshes.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(models))
	file.close()
	game.free()
	print("Exported source terrain meshes: ", models.size())
	quit()
