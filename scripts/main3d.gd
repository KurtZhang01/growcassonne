extends Node3D

const TITLE_BACKGROUND: Texture2D = preload("res://assets/title-background.png")
const DYNAMIC_SKY_SHADER: Shader = preload("res://shaders/dynamic_sky.gdshader")
const WATER_TILE_SHADER: Shader = preload("res://shaders/water_tile.gdshader")

# ---- Config ----
const GRID_SIZE := 8
const TILE_SPACING := 1.25
const TOTAL_ROUNDS_PER_PLAYER := 10
const STARTING_SEED_CARDS := 5
const CARDS_DRAWN_PER_TURN := 3
const MARKET_SIZE := 3
const DIRS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

# ---- Terrain palette (Dorfromantik soft) ----
const TERRAIN_TOP := [
	Color("#5fae55"),  # GRASS
	Color("#3f94bd"),  # WATER
	Color("#2f7048"),  # FOREST
	Color("#c8944e"),  # DESERT
	Color("#c7352e"),  # PAVILION
	Color("#737a75"),  # MOUNTAIN
	Color(0.85, 0.95, 1.0, 0.20),  # GAP
]
const TERRAIN_MID := [
	Color("#40793a"),
	Color("#316b91"),
	Color("#214d34"),
	Color("#9f703a"),
	Color("#8f2427"),
	Color("#565d59"),
	Color(0.62, 0.76, 0.80, 0.18),
]
const TERRAIN_BOT := [
	Color("#29472c"),
	Color("#1f4661"),
	Color("#153324"),
	Color("#69462d"),
	Color("#5a1c21"),
	Color("#3f4542"),
	Color(0.36, 0.50, 0.54, 0.14),
]
const TERRAIN_NAMES := ["草地", "水域", "森林", "荒漠", "建筑", "山体", "缺口"]
const TERRAIN_CAPACITY := [50, 0, 100, 10, 0, 0, 0]
const TERRAIN_GROWTH := [0.3, 0.0, 0.5, 0.1, 0.0, 0.0, 0.0]
const TERRAIN_SPREAD := [0.3, 0.0, 0.5, 0.1, 0.0, 0.0, 0.0]
const T_GRASS := 0
const T_WATER := 1
const T_FOREST := 2
const T_DESERT := 3
const T_BUILDING := 4
const T_MOUNTAIN := 5
const T_GAP := 6

# ---- Player config ----
const PLAYER_COLORS := [
	Color("#d83232"),
	Color("#8c4edb"),
	Color("#e0802f"),
	Color("#1c497d"),
]
const PLAYER_NAMES := ["玩家1", "玩家2", "玩家3", "玩家4"]

# ---- State ----
enum S { TITLE, PLACE_TILE, PLACE_SEED, PLAY_CARDS, GAME_OVER }

var grid := []; var roads := []; var plants := []; var plant_age := []; var flowers := []
var tile_nodes := []; var plant_nodes := []; var decor_nodes := []
var edge_root: Node3D  # container for edge bridge pieces
var edge_materials := {}  # terrain_id -> StandardMaterial3D
var piece_market := []; var selected_market := 0; var piece_rotation := 0; var state := S.TITLE
var player_count := 2; var current_player := 0
var seeds := []; var total_turns := 0; var turns_played := 0
var scores := []; var group_counts := []; var largest_groups := []; var diversity_counts := []; var road_scores := []
var last_growth_count := 0
var closed_road_ids := {}; var closed_road_cells := {}; var last_road_event := ""
var hands := []; var current_hand := []; var selected_card := 0
var active_weather := {}; var rainbow_turns := 0; var last_settlement := ""
var hovered_cell := Vector2i(-1, -1); var pulse := 0.0
var flash_timer := 0.0; var flash_color := Color.WHITE

# Camera zoom/pan
var cam_zoom := 1.0; var cam_zoom_target := 1.0
const CAM_ZOOM_MIN := 0.5; const CAM_ZOOM_MAX := 2.5
const CAM_ZOOM_SPEED := 0.1
var cam_offset := Vector2.ZERO; var cam_offset_target := Vector2.ZERO
var is_panning := false; var pan_start := Vector2.ZERO
var cam_pan_start := Vector2.ZERO
const CAM_PAN_SPEED := 0.015
const CAM_BASE_SIZE := 14.5
const UI_DESIGN_SIZE := Vector2(1280.0, 720.0)
const UI_SIDEBAR_WIDTH := 350.0

# Nodes
var camera: Camera3D; var grid_root: Node3D; var plant_root: Node3D
var decor_root: Node3D; var piece_preview_root: Node3D
var hover_mesh: MeshInstance3D; var hover_material: StandardMaterial3D; var ui_ctrl: Control
var sky_root: Node3D; var drifting_clouds := []; var sky_motes := []

func _ready():
	_setup_scene()
	state = S.TITLE

# ================================================================
#  SCENE
# ================================================================
func _setup_scene():
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 18
	camera.position = Vector3(8, 16, 12)
	camera.rotation_degrees = Vector3(-42, 42, 0)
	camera.near = 0.1; camera.far = 200
	add_child(camera)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 0.82; sun.light_color = Color("#ffe8c4")
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.shadow_enabled = true; add_child(sun)

	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 150, 0)
	fill.light_energy = 0.22; fill.light_color = Color("#87c5c7")
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)

	var rim = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -120, 0)
	rim.light_energy = 0.10; rim.light_color = Color("#f5b766")
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(rim)

	var env = WorldEnvironment.new()
	var e = Environment.new()
	var sky_material = ShaderMaterial.new(); sky_material.shader = DYNAMIC_SKY_SHADER
	var sky = Sky.new(); sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_REALTIME; sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.background_mode = Environment.BG_SKY; e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#a7d6c4")
	e.ambient_light_energy = 0.60
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true; e.glow_intensity = 0.14; e.glow_bloom = 0.02
	env.environment = e; add_child(env)
	_setup_sky_world()

	grid_root = Node3D.new(); add_child(grid_root)
	edge_root = Node3D.new(); add_child(edge_root)
	plant_root = Node3D.new(); add_child(plant_root)
	decor_root = Node3D.new(); add_child(decor_root)
	piece_preview_root = Node3D.new(); add_child(piece_preview_root)

	# Pre-create edge materials
	for i in TERRAIN_TOP.size():
		var mat = StandardMaterial3D.new()
		mat.albedo_color = TERRAIN_TOP[i]
		mat.emission_enabled = true; mat.emission = TERRAIN_TOP[i].darkened(0.2)
		mat.emission_energy_multiplier = 0.15
		edge_materials[i] = mat

	# Hover
	hover_mesh = MeshInstance3D.new()
	var hbox = BoxMesh.new(); hbox.size = Vector3(1.20, 0.03, 1.20)
	hover_mesh.mesh = hbox
	hover_material = StandardMaterial3D.new()
	hover_material.albedo_color = Color(0.35, 1.0, 0.72, 0.38)
	hover_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hover_material.no_depth_test = true
	hover_mesh.material_override = hover_material; hover_mesh.visible = false
	add_child(hover_mesh)

	# UI
	ui_ctrl = Control.new()
	ui_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	var canvas = CanvasLayer.new(); canvas.layer = 10
	add_child(canvas); canvas.add_child(ui_ctrl)
	ui_ctrl.connect("draw", _draw_ui)

func _setup_sky_world():
	sky_root = Node3D.new(); sky_root.name = "LivingSky"; add_child(sky_root)
	_spawn_cloud_layer()
	_spawn_mist_banks()
	_spawn_sky_motes()

func _soft_material(color: Color, emission_energy: float = 0.0) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color; material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission_energy > 0.0:
		material.emission_enabled = true; material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = emission_energy
	return material

func _sky_prop_material(color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _spawn_cloud_layer():
	var grass_mat = _sky_prop_material(Color(0.58, 0.82, 0.46, 0.72))
	var earth_mat = _sky_prop_material(Color(0.34, 0.46, 0.30, 0.66))
	var trunk_mat = _sky_prop_material(Color(0.42, 0.29, 0.17, 0.70))
	var leaf_mat = _sky_prop_material(Color(0.22, 0.55, 0.36, 0.70))
	var islet_positions = [
		Vector3(-14, 2.3, -8), Vector3(-10, 3.8, 8), Vector3(-3, 5.2, -13),
		Vector3(8, 3.2, 10), Vector3(13, 4.7, -3), Vector3(15, 1.8, 6),
	]
	for islet_index in islet_positions.size():
		var islet = Node3D.new(); islet.position = islet_positions[islet_index]
		islet.set_meta("speed", randf_range(0.07, 0.14)); islet.set_meta("base_z", islet.position.z)
		islet.set_meta("base_y", islet.position.y); islet.set_meta("bob", randf_range(0.10, 0.22))
		islet.set_meta("phase", randf() * TAU); sky_root.add_child(islet); drifting_clouds.append(islet)
		islet.scale = Vector3.ONE * randf_range(0.55, 0.82)
		var top = MeshInstance3D.new(); var top_mesh = BoxMesh.new()
		top_mesh.size = Vector3(randf_range(0.95, 1.35), 0.12, randf_range(0.56, 0.86))
		top.mesh = top_mesh; top.material_override = grass_mat; top.position.y = 0.08; islet.add_child(top)
		var base = MeshInstance3D.new(); var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = randf_range(0.42, 0.62); base_mesh.bottom_radius = randf_range(0.18, 0.30)
		base_mesh.height = randf_range(0.45, 0.68); base_mesh.radial_segments = 6
		base.mesh = base_mesh; base.material_override = earth_mat; base.position.y = -0.25; islet.add_child(base)
		if islet_index % 2 == 0:
			var trunk = MeshInstance3D.new(); var trunk_mesh = CylinderMesh.new()
			trunk_mesh.top_radius = 0.025; trunk_mesh.bottom_radius = 0.035; trunk_mesh.height = 0.28; trunk_mesh.radial_segments = 6
			trunk.mesh = trunk_mesh; trunk.material_override = trunk_mat; trunk.position.y = 0.28; islet.add_child(trunk)
			var crown = MeshInstance3D.new(); var crown_mesh = SphereMesh.new()
			crown_mesh.radius = 0.18; crown_mesh.height = 0.26; crown_mesh.radial_segments = 8; crown_mesh.rings = 4
			crown.mesh = crown_mesh; crown.material_override = leaf_mat; crown.position.y = 0.50; crown.scale = Vector3(1.25, 0.75, 1.0); islet.add_child(crown)

func _spawn_mist_banks():
	var mist_material = _sky_prop_material(Color(0.88, 0.98, 0.88, 0.20))
	for i in 9:
		var mist = Node3D.new()
		var angle = TAU * float(i) / 9.0 + randf_range(-0.16, 0.16)
		var radius = randf_range(10.0, 17.0)
		mist.position = Vector3(cos(angle) * radius, randf_range(-2.4, -0.8), sin(angle) * radius)
		mist.set_meta("speed", randf_range(0.16, 0.26)); mist.set_meta("base_z", mist.position.z)
		mist.set_meta("base_y", mist.position.y); mist.set_meta("bob", randf_range(0.05, 0.12))
		mist.set_meta("phase", randf() * TAU); sky_root.add_child(mist); drifting_clouds.append(mist)
		var ribbon = MeshInstance3D.new(); var ribbon_mesh = BoxMesh.new()
		ribbon_mesh.size = Vector3(randf_range(3.8, 6.2), 0.018, randf_range(0.06, 0.10))
		ribbon.mesh = ribbon_mesh; ribbon.material_override = mist_material
		ribbon.rotation_degrees.y = randf_range(-18, 18); mist.add_child(ribbon)

func _spawn_sky_motes():
	var mote_material = _soft_material(Color(0.74, 1.0, 0.72, 0.72), 1.4)
	for i in 28:
		var mote = MeshInstance3D.new(); var mesh = SphereMesh.new()
		mesh.radius = randf_range(0.018, 0.038); mesh.height = mesh.radius * 2.0; mesh.radial_segments = 6; mesh.rings = 3
		mote.mesh = mesh; mote.material_override = mote_material
		var angle = randf() * TAU; var radius = randf_range(5.5, 12.0)
		mote.position = Vector3(cos(angle) * radius, randf_range(0.5, 4.5), sin(angle) * radius)
		mote.set_meta("base_y", mote.position.y); mote.set_meta("phase", randf() * TAU); mote.set_meta("speed", randf_range(0.35, 0.75))
		sky_root.add_child(mote); sky_motes.append(mote)

# ================================================================
#  GRID
# ================================================================
func _init_grid():
	for c in grid_root.get_children(): c.queue_free()
	for c in edge_root.get_children(): c.queue_free()
	for c in plant_root.get_children(): c.queue_free()
	for c in decor_root.get_children(): c.queue_free()
	grid = []; roads = []; plants = []; plant_age = []; flowers = []
	tile_nodes = []; plant_nodes = []; decor_nodes = []
	for x in GRID_SIZE:
		grid.append([]); roads.append([]); plants.append([]); plant_age.append([]); flowers.append([])
		tile_nodes.append([]); plant_nodes.append([]); decor_nodes.append([])
		for y in GRID_SIZE:
			grid[x].append(-1); roads[x].append(0); plants[x].append(0); plant_age[x].append(0)
			flowers[x].append([0, 0, 0, 0])
			tile_nodes[x].append(null); plant_nodes[x].append(null); decor_nodes[x].append(null)

func _world(pos: Vector2i) -> Vector3:
	var off = (GRID_SIZE - 1) * TILE_SPACING * 0.5
	return Vector3(pos.x * TILE_SPACING - off, 0, pos.y * TILE_SPACING - off)

func _draw_terrain() -> int:
	var roll = randf()
	if roll < 0.39: return T_FOREST
	if roll < 0.67: return T_GRASS
	if roll < 0.86: return T_DESERT
	if roll < 0.97: return T_WATER
	return T_BUILDING

func _shape_library() -> Array:
	return [
		{"name": "双生径", "cells": [Vector2i(0, 0), Vector2i(1, 0)]},
		{"name": "长渠", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]},
		{"name": "转角林", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]},
		{"name": "阶梯原", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]},
		{"name": "四方圃", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]},
		{"name": "三岔路", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)]},
		{"name": "蜿蜒带", "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)]},
		{"name": "长枝岛", "cells": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]},
	]

func _direction_index(delta: Vector2i) -> int:
	for i in DIRS.size():
		if DIRS[i] == delta: return i
	return -1

func _generate_piece() -> Dictionary:
	var templates = _shape_library()
	# Two- and three-cell pieces stay common so the board remains playable late.
	var pick = randi() % (templates.size() + 4)
	var template = templates[pick if pick < templates.size() else pick % 4]
	var cells: Array = template["cells"].duplicate()
	var terrains := []; var road_masks := []
	for i in cells.size():
		terrains.append(_draw_terrain()); road_masks.append(0)

	# Every adjacent pair inside the polyomino receives a two-way road.
	for i in cells.size():
		for j in range(i + 1, cells.size()):
			var dir_index = _direction_index(cells[j] - cells[i])
			if dir_index >= 0:
				road_masks[i] |= 1 << dir_index
				road_masks[j] |= 1 << ((dir_index + 2) % 4)

	# Add two outward gates so separate pieces can form longer road networks.
	var gates := []
	for i in cells.size():
		for dir_index in DIRS.size():
			if not cells.has(cells[i] + DIRS[dir_index]): gates.append([i, dir_index])
	gates.shuffle()
	for gate_index in mini(2, gates.size()):
		var gate = gates[gate_index]
		road_masks[gate[0]] |= 1 << gate[1]

	return {"name": template["name"], "cells": cells, "terrains": terrains, "roads": road_masks}

func _rotate_cell(cell: Vector2i, turns: int) -> Vector2i:
	var result = cell
	for i in posmod(turns, 4): result = Vector2i(-result.y, result.x)
	return result

func _rotate_road_mask(mask: int, turns: int) -> int:
	var result := 0
	for dir_index in DIRS.size():
		if (mask & (1 << dir_index)) != 0: result |= 1 << posmod(dir_index + turns, 4)
	return result

func _piece_cells(piece: Dictionary, rotation: int) -> Array:
	var result := []
	for cell in piece["cells"]: result.append(_rotate_cell(cell, rotation))
	return result

func _pick_tile():
	if piece_market.is_empty():
		for i in MARKET_SIZE: piece_market.append(_generate_piece())
	selected_market = clampi(selected_market, 0, piece_market.size() - 1)
	piece_rotation = 0
	state = S.PLACE_TILE
	if _has_any() and not _market_has_move():
		state = S.GAME_OVER; _calc_all_scores()
	hover_mesh.visible = false; _update_piece_preview()

func _select_market(index: int):
	if state != S.PLACE_TILE or index < 0 or index >= piece_market.size(): return
	selected_market = index
	piece_rotation = 0
	_update_piece_preview()
	ui_ctrl.queue_redraw()

func _consume_market_tile():
	piece_market.remove_at(selected_market)
	piece_market.append(_generate_piece())
	selected_market = 0
	piece_rotation = 0

func _has_any() -> bool:
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if grid[x][y] != -1: return true
	return false

func _can_place_piece_data(anchor: Vector2i, piece: Dictionary, rotation: int) -> bool:
	var piece_cells = _piece_cells(piece, rotation)
	var touches_board = not _has_any()
	for local_cell in piece_cells:
		var pos = anchor + local_cell
		if pos.x < 0 or pos.x >= GRID_SIZE or pos.y < 0 or pos.y >= GRID_SIZE: return false
		if grid[pos.x][pos.y] != -1: return false
		for dir in DIRS:
			var neighbor = pos + dir
			if neighbor.x >= 0 and neighbor.x < GRID_SIZE and neighbor.y >= 0 and neighbor.y < GRID_SIZE:
				if grid[neighbor.x][neighbor.y] != -1: touches_board = true
	return touches_board

func _market_has_move() -> bool:
	for piece in piece_market:
		for rotation in 4:
			for x in GRID_SIZE:
				for y in GRID_SIZE:
					if _can_place_piece_data(Vector2i(x, y), piece, rotation): return true
	return false

func _can_place_piece(anchor: Vector2i) -> bool:
	if piece_market.is_empty(): return false
	return _can_place_piece_data(anchor, piece_market[selected_market], piece_rotation)

func _place_piece(anchor: Vector2i) -> bool:
	var piece: Dictionary = piece_market[selected_market]
	if not _can_place_piece_data(anchor, piece, piece_rotation): return false
	var piece_cells = _piece_cells(piece, piece_rotation)
	for i in piece_cells.size():
		var pos: Vector2i = anchor + piece_cells[i]
		var terrain: int = piece["terrains"][i]
		var road_mask = _rotate_road_mask(piece["roads"][i], piece_rotation)
		grid[pos.x][pos.y] = terrain; roads[pos.x][pos.y] = road_mask
		_spawn_tile(pos, terrain, true, road_mask)
	for local_cell in piece_cells:
		_update_edge_bridges(anchor + local_cell)
		_update_road_bridges(anchor + local_cell)
	_refresh_road_effects()
	piece_preview_root.visible = false
	return true

func _force_tile(pos: Vector2i, terr: int, animate: bool, road_mask: int = 0):
	grid[pos.x][pos.y] = terr; roads[pos.x][pos.y] = road_mask
	_spawn_tile(pos, terr, animate, road_mask)
	_update_edge_bridges(pos)
	_update_road_bridges(pos)

func _set_tile_type(pos: Vector2i, terr: int, animate: bool = true, road_mask: int = -1):
	if pos.x < 0 or pos.x >= GRID_SIZE or pos.y < 0 or pos.y >= GRID_SIZE: return
	if grid[pos.x][pos.y] == T_BUILDING: return
	var next_road = roads[pos.x][pos.y] if road_mask < 0 else road_mask
	if tile_nodes[pos.x][pos.y] != null:
		tile_nodes[pos.x][pos.y].queue_free()
		tile_nodes[pos.x][pos.y] = null
	grid[pos.x][pos.y] = terr
	roads[pos.x][pos.y] = 0 if _is_developable(terr) else next_road
	_trim_flowers_to_capacity(pos)
	_spawn_tile(pos, terr, animate, roads[pos.x][pos.y])
	_update_edge_bridges(pos)
	_update_road_bridges(pos)

func _redraw_tile(pos: Vector2i):
	if not _in_bounds(pos): return
	if tile_nodes[pos.x][pos.y] != null:
		tile_nodes[pos.x][pos.y].queue_free()
		tile_nodes[pos.x][pos.y] = null
	_spawn_tile(pos, grid[pos.x][pos.y], false, roads[pos.x][pos.y])

func _is_plant_terrain(terr: int) -> bool:
	return terr == T_FOREST or terr == T_GRASS or terr == T_DESERT

func _is_bonus_terrain(terr: int) -> bool:
	return terr == T_WATER or terr == T_BUILDING

func _is_developable(terr: int) -> bool:
	return terr == T_MOUNTAIN or terr == T_GAP

func _tile_capacity(pos: Vector2i) -> int:
	var cap = TERRAIN_CAPACITY[grid[pos.x][pos.y]]
	if cap > 0 and _has_neighbor_bonus(pos, T_BUILDING): cap *= 2
	return cap

func _has_neighbor_bonus(pos: Vector2i, terr: int) -> bool:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0: continue
			var p = pos + Vector2i(dx, dy)
			if p.x >= 0 and p.x < GRID_SIZE and p.y >= 0 and p.y < GRID_SIZE:
				if grid[p.x][p.y] == terr: return true
	return false

func _trim_flowers_to_capacity(pos: Vector2i):
	var cap = _tile_capacity(pos)
	var total = _flower_total(pos)
	if total <= cap: return
	if cap <= 0:
		flowers[pos.x][pos.y] = [0, 0, 0, 0]
		_clear_plant_visual(pos)
		return
	var ratio = float(cap) / maxf(float(total), 1.0)
	for pid in 4:
		flowers[pos.x][pos.y][pid] = floori(flowers[pos.x][pos.y][pid] * ratio)
	_refresh_plant_visual(pos)

func _flower_total(pos: Vector2i) -> int:
	var total := 0
	for pid in 4: total += flowers[pos.x][pos.y][pid]
	return total

# ================================================================
#  EDGE BRIDGES — seamless terrain connections
# ================================================================
func _update_edge_bridges(pos: Vector2i):
	"""Spawn bridge pieces between pos and all matching neighbors."""
	var terr = grid[pos.x][pos.y]
	if terr < 0: return
	if _is_developable(terr): return

	var dirs = [
		[Vector2i.UP, Vector3(0, 0, -TILE_SPACING * 0.5), Vector3(TILE_SPACING * 0.7, 0.04, 0.12)],
		[Vector2i.DOWN, Vector3(0, 0, TILE_SPACING * 0.5), Vector3(TILE_SPACING * 0.7, 0.04, 0.12)],
		[Vector2i.LEFT, Vector3(-TILE_SPACING * 0.5, 0, 0), Vector3(0.12, 0.04, TILE_SPACING * 0.7)],
		[Vector2i.RIGHT, Vector3(TILE_SPACING * 0.5, 0, 0), Vector3(0.12, 0.04, TILE_SPACING * 0.7)],
	]

	for d in dirs:
		var dir: Vector2i = d[0]
		var offset: Vector3 = d[1]
		var size: Vector3 = d[2]
		var neighbor = pos + dir
		if neighbor.x >= 0 and neighbor.x < GRID_SIZE and neighbor.y >= 0 and neighbor.y < GRID_SIZE:
			if grid[neighbor.x][neighbor.y] == terr:
				_spawn_bridge(pos, terr, offset, size)

	# Also update all neighbors' bridges (they might now connect to this new tile)
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor = pos + dir
		if neighbor.x >= 0 and neighbor.x < GRID_SIZE and neighbor.y >= 0 and neighbor.y < GRID_SIZE:
			if grid[neighbor.x][neighbor.y] == terr:
				# Rebuild bridges for neighbor
				_rebuild_bridges_for(neighbor)

func _rebuild_bridges_for(pos: Vector2i):
	"""Remove old bridges for a tile and rebuild them."""
	# Remove existing bridge children from edge_root that belong to this position
	var to_remove := []
	for child in edge_root.get_children():
		if child.has_meta("bridge_owner") and child.get_meta("bridge_owner") == str(pos):
			to_remove.append(child)
	for child in to_remove:
		child.queue_free()

	var terr = grid[pos.x][pos.y]
	if terr < 0: return
	if _is_developable(terr): return

	var dirs = [
		[Vector2i.UP, Vector3(0, 0, -TILE_SPACING * 0.5), Vector3(TILE_SPACING * 0.7, 0.04, 0.12)],
		[Vector2i.DOWN, Vector3(0, 0, TILE_SPACING * 0.5), Vector3(TILE_SPACING * 0.7, 0.04, 0.12)],
		[Vector2i.LEFT, Vector3(-TILE_SPACING * 0.5, 0, 0), Vector3(0.12, 0.04, TILE_SPACING * 0.7)],
		[Vector2i.RIGHT, Vector3(TILE_SPACING * 0.5, 0, 0), Vector3(0.12, 0.04, TILE_SPACING * 0.7)],
	]

	for d in dirs:
		var dir: Vector2i = d[0]
		var offset: Vector3 = d[1]
		var size: Vector3 = d[2]
		var neighbor = pos + dir
		if neighbor.x >= 0 and neighbor.x < GRID_SIZE and neighbor.y >= 0 and neighbor.y < GRID_SIZE:
			if grid[neighbor.x][neighbor.y] == terr:
				_spawn_bridge(pos, terr, offset, size)

func _spawn_bridge(owner_pos: Vector2i, terr: int, offset: Vector3, size: Vector3):
	"""Spawn a single bridge piece connecting two tiles."""
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new(); bm.size = size
	mi.mesh = bm
	mi.material_override = edge_materials[terr]
	mi.position = _world(owner_pos) + offset + Vector3(0, 0.13, 0)
	mi.set_meta("bridge_owner", str(owner_pos))
	edge_root.add_child(mi)

func _road_pair_key(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var swap = a; a = b; b = swap
	return "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]

func _update_road_bridges(pos: Vector2i):
	if grid[pos.x][pos.y] < 0: return
	for dir in DIRS:
		var neighbor = pos + dir
		if neighbor.x < 0 or neighbor.x >= GRID_SIZE or neighbor.y < 0 or neighbor.y >= GRID_SIZE: continue
		if grid[neighbor.x][neighbor.y] < 0 or not _roads_connect(pos, neighbor): continue
		var key = _road_pair_key(pos, neighbor); var exists = false
		for child in edge_root.get_children():
			if child.has_meta("road_key") and child.get_meta("road_key") == key:
				exists = true; break
		if exists: continue
		var bridge = MeshInstance3D.new(); var mesh = BoxMesh.new()
		var horizontal = dir.x != 0
		mesh.size = Vector3(0.34 if horizontal else 0.16, 0.03, 0.16 if horizontal else 0.34)
		var bridge_material = _road_material(Color("#f2d99b"), 0.72)
		bridge_material.emission_enabled = true; bridge_material.emission = Color("#8be5d1")
		bridge_material.emission_energy_multiplier = 2.2
		bridge.mesh = mesh; bridge.material_override = bridge_material
		bridge.position = (_world(pos) + _world(neighbor)) * 0.5 + Vector3(0, 0.285, 0)
		bridge.set_meta("road_key", key); edge_root.add_child(bridge)
		var flash = create_tween()
		flash.tween_property(bridge_material, "emission_energy_multiplier", 0.08, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

func _refresh_road_effects():
	last_road_event = ""
	for child in edge_root.get_children():
		if child.has_meta("road_fx"): child.free()
	closed_road_cells.clear()
	var current_closed := {}

	var visited := {}
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var start := Vector2i(x, y)
			if grid[x][y] < 0 or visited.has(start) or roads[x][y] == 0: continue
			var component := _road_component(start, visited)
			var connected = component.size() > 1
			var closed = connected and _road_component_is_closed(component)
			for cell in component:
				_set_road_visual(cell, connected, closed)
				if closed: closed_road_cells[cell] = true
			if closed:
				var component_id = _road_component_key(component)
				current_closed[component_id] = true
				_spawn_closed_road_fx(component)
				if not closed_road_ids.has(component_id): last_road_event = "道路闭合！沿线生态获得奖励"
	closed_road_ids = current_closed

func _road_component(start: Vector2i, visited: Dictionary) -> Array:
	var component := []
	var pending := [start]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		if visited.has(cell): continue
		visited[cell] = true; component.append(cell)
		for dir in DIRS:
			var neighbor = cell + dir
			if neighbor.x >= 0 and neighbor.x < GRID_SIZE and neighbor.y >= 0 and neighbor.y < GRID_SIZE and not visited.has(neighbor) and _roads_connect(cell, neighbor):
				pending.append(neighbor)
	return component

func _road_component_is_closed(component: Array) -> bool:
	for cell in component:
		var mask: int = roads[cell.x][cell.y]
		for dir_index in DIRS.size():
			if (mask & (1 << dir_index)) == 0: continue
			var neighbor: Vector2i = cell + DIRS[dir_index]
			if neighbor.x < 0 or neighbor.x >= GRID_SIZE or neighbor.y < 0 or neighbor.y >= GRID_SIZE: return false
			if grid[neighbor.x][neighbor.y] < 0 or not _roads_connect(cell, neighbor): return false
	return true

func _road_component_key(component: Array) -> String:
	var labels := []
	for cell in component: labels.append("%02d,%02d" % [cell.x, cell.y])
	labels.sort()
	var key := ""
	for label in labels: key += label + "|"
	return key

func _set_road_visual(pos: Vector2i, connected: bool, closed: bool):
	var tile = tile_nodes[pos.x][pos.y]
	if tile == null or not tile.has_meta("road_material"): return
	var material: StandardMaterial3D = tile.get_meta("road_material")
	material.albedo_color = Color("#d8bd80")
	material.emission_enabled = connected
	material.emission = Color("#8be5d1") if not closed else Color("#ffd66b")
	material.emission_energy_multiplier = 0.16 if connected and not closed else (1.1 if closed else 0.0)

func _spawn_closed_road_fx(component: Array):
	for index in component.size():
		if index % 2 == 0: _spawn_road_fx(component[index])

func _spawn_road_fx(pos: Vector2i):
	var ring = MeshInstance3D.new()
	var mesh = TorusMesh.new(); mesh.inner_radius = 0.125; mesh.outer_radius = 0.16
	mesh.rings = 12; mesh.ring_segments = 16
	ring.mesh = mesh
	var material = _road_material(Color("#f7e6a5"), 0.35)
	material.emission_enabled = true; material.emission = Color("#ffd66b"); material.emission_energy_multiplier = 1.8
	ring.material_override = material; ring.position = _world(pos) + Vector3(0, 0.315, 0)
	ring.set_meta("road_fx", true); edge_root.add_child(ring)
	var tw = create_tween().set_loops()
	tw.tween_property(ring, "rotation:y", TAU, 2.4)
	var pulse_tw = create_tween().set_loops()
	pulse_tw.tween_property(ring, "scale", Vector3(1.18, 1.18, 1.18), 0.55).set_trans(Tween.TRANS_SINE)
	pulse_tw.tween_property(ring, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_SINE)

# ================================================================
#  STARTING BOARD
# ================================================================
func _generate_start_tiles():
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var pos = Vector2i(x, y)
			if x >= 2 and x <= 5 and y >= 2 and y <= 5:
				_force_tile(pos, _draw_terrain(), false, _random_road_mask())
			else:
				_force_tile(pos, T_MOUNTAIN, false, 0)
	_refresh_road_effects()

func _random_road_mask() -> int:
	if randf() > 0.28: return 0
	var dirs = [0, 1, 2, 3]; dirs.shuffle()
	var mask = 1 << dirs[0]
	if randf() < 0.55: mask |= 1 << dirs[1]
	return mask

# ================================================================
#  TILE MESH — rich 3D per terrain
# ================================================================
func _spawn_tile(pos: Vector2i, terr: int, animate: bool, road_mask: int = 0):
	var root = Node3D.new(); root.position = _world(pos)
	grid_root.add_child(root); tile_nodes[pos.x][pos.y] = root
	if terr != T_GAP:
		_spawn_island_base(root, terr)

	# --- Top surface with terrain-specific shape ---
	match terr:
		0: _tile_grass_surface(root, road_mask)
		1: _tile_water_surface(root, road_mask)
		2: _tile_forest_surface(root, road_mask)
		3: _tile_desert_surface(root, road_mask)
		4: _tile_pavilion_surface(root, road_mask)
		5: _tile_mountain_surface(root)
		6: _tile_gap_surface(root)

	if terr != T_GAP:
		_spawn_edge_trim(root, terr)

	# --- Decorations ---
	_spawn_decor(terr, root, road_mask)
	if road_mask != 0 and not _is_developable(terr): _spawn_road(root, road_mask)

	if animate:
		root.scale = Vector3(0.01, 0.01, 0.01)
		var tw = create_tween()
		tw.tween_property(root, "scale", Vector3(1, 1, 1), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

func _spawn_island_base(root: Node3D, terr: int):
	var layers = [
		[Vector3(1.06, 0.13, 1.06), 0.025, TERRAIN_MID[terr]],
		[Vector3(0.88, 0.12, 0.88), -0.095, TERRAIN_BOT[terr]],
		[Vector3(0.56, 0.16, 0.56), -0.225, TERRAIN_BOT[terr].darkened(0.20)],
	]
	for layer_data in layers:
		var layer = MeshInstance3D.new(); var mesh = BoxMesh.new()
		mesh.size = layer_data[0]; layer.mesh = mesh
		var material = StandardMaterial3D.new(); material.albedo_color = layer_data[2]; material.roughness = 0.94
		layer.material_override = material; layer.position.y = layer_data[1]; root.add_child(layer)
	var core = MeshInstance3D.new(); var core_mesh = CylinderMesh.new()
	core_mesh.top_radius = 0.32; core_mesh.bottom_radius = 0.16; core_mesh.height = 0.32; core_mesh.radial_segments = 6
	core.mesh = core_mesh
	var core_material = StandardMaterial3D.new(); core_material.albedo_color = TERRAIN_BOT[terr].darkened(0.30); core_material.roughness = 1.0
	core.material_override = core_material; core.position.y = -0.39; core.rotation_degrees.y = randf_range(0, 60)
	root.add_child(core)

func _spawn_edge_trim(root: Node3D, terr: int):
	var trim_material = StandardMaterial3D.new()
	trim_material.albedo_color = TERRAIN_TOP[terr].lightened(0.08)
	trim_material.roughness = 0.76
	for side in 4:
		var trim = MeshInstance3D.new(); var mesh = BoxMesh.new()
		var horizontal = side < 2
		mesh.size = Vector3(1.07 if horizontal else 0.035, 0.018, 0.035 if horizontal else 1.07)
		trim.mesh = mesh; trim.material_override = trim_material
		if horizontal: trim.position = Vector3(0, 0.172, -0.515 if side == 0 else 0.515)
		else: trim.position = Vector3(-0.515 if side == 2 else 0.515, 0.172, 0)
		root.add_child(trim)

func _feature_position(road_mask: int, extent: float = 0.34) -> Vector2:
	for attempt in 12:
		var candidate = Vector2(randf_range(-extent, extent), randf_range(-extent, extent))
		if _position_clear_of_road(candidate, road_mask): return candidate
	return Vector2(extent * 0.82, extent * 0.82)

func _position_clear_of_road(pos: Vector2, road_mask: int) -> bool:
	if road_mask == 0: return true
	if pos.length() < 0.20: return false
	for dir_index in DIRS.size():
		if (road_mask & (1 << dir_index)) == 0: continue
		var direction = Vector2(DIRS[dir_index])
		var along = pos.dot(direction)
		var across = absf(pos.x * direction.y - pos.y * direction.x)
		if along > -0.03 and across < 0.18: return false
	return true

func _road_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color; material.roughness = roughness
	return material

func _spawn_road(root: Node3D, road_mask: int):
	var under_material = _road_material(Color("#73583f"), 0.95)
	var road_material = _road_material(Color("#d8bd80"), 0.88)
	root.set_meta("road_material", road_material)
	for dir_index in DIRS.size():
		if (road_mask & (1 << dir_index)) == 0: continue
		var dir: Vector2i = DIRS[dir_index]
		var is_horizontal = dir.x != 0
		var length = 0.54
		var offset = Vector3(dir.x, 0, dir.y) * length * 0.5
		var under = MeshInstance3D.new(); var under_mesh = BoxMesh.new()
		under_mesh.size = Vector3(length if is_horizontal else 0.24, 0.026, 0.24 if is_horizontal else length)
		under.mesh = under_mesh; under.material_override = under_material
		under.position = offset + Vector3(0, 0.265, 0); root.add_child(under)
		var road = MeshInstance3D.new(); var road_mesh = BoxMesh.new()
		road_mesh.size = Vector3(length if is_horizontal else 0.16, 0.028, 0.16 if is_horizontal else length)
		road.mesh = road_mesh; road.material_override = road_material
		road.position = offset + Vector3(0, 0.285, 0); root.add_child(road)

	var hub_under = MeshInstance3D.new(); var hub_under_mesh = CylinderMesh.new()
	hub_under_mesh.top_radius = 0.16; hub_under_mesh.bottom_radius = 0.16; hub_under_mesh.height = 0.026
	hub_under.mesh = hub_under_mesh; hub_under.material_override = under_material
	hub_under.position.y = 0.265; root.add_child(hub_under)
	var hub = MeshInstance3D.new(); var hub_mesh = CylinderMesh.new()
	hub_mesh.top_radius = 0.115; hub_mesh.bottom_radius = 0.115; hub_mesh.height = 0.03
	hub.mesh = hub_mesh; hub.material_override = road_material
	hub.position.y = 0.285; root.add_child(hub)

# ---- Grass: gentle rolling hills ----
func _tile_grass_surface(root: Node3D, road_mask: int):
	# Main flat top
	var top = MeshInstance3D.new()
	var tm = BoxMesh.new(); tm.size = Vector3(0.95, 0.06, 0.95)
	top.mesh = tm
	var mat = StandardMaterial3D.new(); mat.albedo_color = TERRAIN_TOP[0]; mat.roughness = 0.92
	top.material_override = mat; top.position.y = 0.13
	root.add_child(top)

	# Soft clover patches break up the square surface without obscuring roads.
	for i in 2:
		var patch = MeshInstance3D.new(); var patch_mesh = CylinderMesh.new()
		patch_mesh.top_radius = randf_range(0.10, 0.18); patch_mesh.bottom_radius = patch_mesh.top_radius * 1.08
		patch_mesh.height = 0.012; patch_mesh.radial_segments = 12; patch.mesh = patch_mesh
		var patch_material = StandardMaterial3D.new(); patch_material.albedo_color = TERRAIN_TOP[0].lerp(Color("#b4d66a"), randf_range(0.18, 0.42))
		patch_material.roughness = 1.0; patch.material_override = patch_material
		var patch_pos = _feature_position(road_mask, 0.34); patch.position = Vector3(patch_pos.x, 0.166, patch_pos.y)
		patch.scale.z = randf_range(0.65, 1.2); root.add_child(patch)

	# Rounded hillocks give grass tiles a soft pastoral silhouette.
	for i in randi_range(1, 3):
		var bump = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = randf_range(0.10, 0.17); sm.height = sm.radius * 1.15
		sm.radial_segments = 16; sm.rings = 8
		bump.mesh = sm
		var bm2 = StandardMaterial3D.new()
		bm2.albedo_color = TERRAIN_TOP[0].lerp(Color(0.4, 0.75, 0.3), randf_range(0, 0.3))
		bump.material_override = bm2
		var feature_pos = _feature_position(road_mask, 0.32)
		bump.position = Vector3(feature_pos.x, 0.15, feature_pos.y)
		bump.scale = Vector3(randf_range(1.0, 1.35), randf_range(0.32, 0.48), randf_range(0.9, 1.25))
		root.add_child(bump)

# ---- Water: depressed pool with ripple rings ----
func _tile_water_surface(root: Node3D, road_mask: int):
	# Water surface (slightly lower)
	var top = MeshInstance3D.new()
	var tm = BoxMesh.new(); tm.size = Vector3(0.92, 0.04, 0.92)
	top.mesh = tm
	var mat = ShaderMaterial.new(); mat.shader = WATER_TILE_SHADER
	top.material_override = mat; top.position.y = 0.10
	root.add_child(top)

	# A submerged center creates depth beneath the animated surface.
	var depth = MeshInstance3D.new()
	var dm = CylinderMesh.new(); dm.top_radius = 0.30; dm.bottom_radius = 0.30; dm.height = 0.02
	depth.mesh = dm
	var dmat = StandardMaterial3D.new()
	dmat.albedo_color = TERRAIN_BOT[1].lerp(TERRAIN_MID[1], 0.5)
	depth.material_override = dmat; depth.position.y = 0.09
	root.add_child(depth)

	# Offset ripple rings keep neighboring water tiles from looking cloned.
	for i in randi_range(1, 3):
		var ripple = MeshInstance3D.new()
		var rm = TorusMesh.new()
		rm.inner_radius = 0.12 + i * 0.10; rm.outer_radius = rm.inner_radius + 0.02; rm.rings = 24
		ripple.mesh = rm
		var rmat = StandardMaterial3D.new()
		rmat.albedo_color = Color(0.68, 0.92, 1.0, 0.23 - i * 0.045)
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.emission_enabled = true; rmat.emission = Color(0.2, 0.5, 0.8)
		rmat.emission_energy_multiplier = 0.3
		ripple.material_override = rmat
		var ripple_pos = _feature_position(road_mask, 0.25)
		ripple.position = Vector3(ripple_pos.x, 0.13, ripple_pos.y)
		root.add_child(ripple)
		var ripple_tween = ripple.create_tween().set_loops()
		ripple_tween.tween_property(ripple, "scale", Vector3(1.10, 1.10, 1.10), randf_range(1.8, 2.8)).set_trans(Tween.TRANS_SINE)
		ripple_tween.tween_property(ripple, "scale", Vector3.ONE, randf_range(1.8, 2.8)).set_trans(Tween.TRANS_SINE)

	# Small reflected streak.
	var spec = MeshInstance3D.new()
	var sm = PlaneMesh.new(); sm.size = Vector2(0.25, 0.15)
	spec.mesh = sm
	var smat = StandardMaterial3D.new()
	smat.albedo_color = Color(0.8, 0.95, 1.0, 0.2)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.emission_enabled = true; smat.emission = Color(0.5, 0.8, 1.0)
	smat.emission_energy_multiplier = 0.4
	spec.material_override = smat
	var spec_pos = _feature_position(road_mask, 0.28)
	spec.position = Vector3(spec_pos.x, 0.14, spec_pos.y)
	spec.rotation_degrees.y = randf_range(0, 360)
	root.add_child(spec)

# ---- Forest: raised terrain with visible tree trunks ----
func _tile_forest_surface(root: Node3D, road_mask: int):
	# Raised forest floor remains square so connected tiles read as one biome.
	var top = MeshInstance3D.new()
	var tm = BoxMesh.new(); tm.size = Vector3(0.95, 0.075, 0.95)
	top.mesh = tm
	var mat = StandardMaterial3D.new(); mat.albedo_color = TERRAIN_MID[2]
	mat.roughness = 1.0; top.material_override = mat; top.position.y = 0.138
	root.add_child(top)

	# Moss layer on top
	var moss = MeshInstance3D.new()
	var mm2 = CylinderMesh.new()
	mm2.top_radius = 0.31; mm2.bottom_radius = 0.34; mm2.height = 0.025; mm2.radial_segments = 14
	moss.mesh = mm2
	var mmat2 = StandardMaterial3D.new()
	mmat2.albedo_color = TERRAIN_TOP[2]
	moss.material_override = mmat2; moss.position.y = 0.19
	root.add_child(moss)

	# Stumps and fallen timber make the forest floor legible between canopies.
	for i in 1:
		var stump = MeshInstance3D.new()
		var sm = CylinderMesh.new()
		sm.top_radius = randf_range(0.04, 0.07)
		sm.bottom_radius = sm.top_radius + 0.01
		sm.height = randf_range(0.08, 0.15)
		stump.mesh = sm
		var smat2 = StandardMaterial3D.new()
		smat2.albedo_color = Color(0.40, 0.28, 0.15).lerp(Color(0.55, 0.38, 0.22), randf())
		stump.material_override = smat2
		var feature_pos = _feature_position(road_mask, 0.28)
		stump.position = Vector3(feature_pos.x, 0.20, feature_pos.y)
		root.add_child(stump)

# ---- Desert: flat with dune ridges ----
func _tile_desert_surface(root: Node3D, road_mask: int):
	# Flat sand surface
	var top = MeshInstance3D.new()
	var tm = BoxMesh.new(); tm.size = Vector3(0.95, 0.05, 0.95)
	top.mesh = tm
	var mat = StandardMaterial3D.new(); mat.albedo_color = TERRAIN_TOP[3]; mat.roughness = 1.0
	top.material_override = mat; top.position.y = 0.13
	root.add_child(top)

	# Partially buried ellipsoids form smooth dune ridges instead of hard boxes.
	for i in randi_range(2, 3):
		var dune = MeshInstance3D.new()
		var dm = SphereMesh.new(); dm.radius = 0.16; dm.height = 0.20; dm.radial_segments = 18; dm.rings = 8
		dune.mesh = dm
		var dmat2 = StandardMaterial3D.new()
		dmat2.albedo_color = TERRAIN_TOP[3].lerp(Color(0.85, 0.72, 0.40), randf_range(0, 0.4))
		dune.material_override = dmat2
		var feature_pos = _feature_position(road_mask, 0.30)
		dune.position = Vector3(feature_pos.x, 0.135, feature_pos.y)
		dune.scale = Vector3(randf_range(0.55, 0.85), randf_range(0.22, 0.34), randf_range(1.25, 1.75))
		dune.rotation_degrees.y = randf_range(0, 360)
		root.add_child(dune)

	# Shadow pockets (darker flat planes)
	for i in randi_range(0, 2):
		var shadow = MeshInstance3D.new()
		var shm = PlaneMesh.new(); shm.size = Vector2(randf_range(0.1, 0.2), randf_range(0.15, 0.3))
		shadow.mesh = shm
		var shmat = StandardMaterial3D.new()
		shmat.albedo_color = Color(0, 0, 0, 0.08)
		shmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow.material_override = shmat
		var feature_pos = _feature_position(road_mask, 0.30)
		shadow.position = Vector3(feature_pos.x, 0.165, feature_pos.y)
		shadow.rotation_degrees.y = randf_range(0, 360)
		root.add_child(shadow)

func _tile_mountain_surface(root: Node3D):
	var top = MeshInstance3D.new(); var tm = BoxMesh.new()
	tm.size = Vector3(0.96, 0.08, 0.96); top.mesh = tm
	var mat = StandardMaterial3D.new(); mat.albedo_color = TERRAIN_TOP[T_MOUNTAIN]; mat.roughness = 1.0
	top.material_override = mat; top.position.y = 0.14; root.add_child(top)
	for i in 3:
		var rock = MeshInstance3D.new(); var rm = CylinderMesh.new()
		rm.top_radius = randf_range(0.04, 0.08); rm.bottom_radius = randf_range(0.10, 0.16)
		rm.height = randf_range(0.14, 0.24); rm.radial_segments = 5
		rock.mesh = rm; rock.material_override = mat
		rock.position = Vector3(randf_range(-0.25, 0.25), 0.22, randf_range(-0.25, 0.25))
		rock.rotation_degrees.y = randf_range(0, 360); root.add_child(rock)

func _tile_gap_surface(root: Node3D):
	var ring_material = StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.88, 0.98, 1.0, 0.30)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in 4:
		var edge = MeshInstance3D.new(); var mesh = BoxMesh.new()
		var horizontal = side < 2
		mesh.size = Vector3(0.88 if horizontal else 0.025, 0.018, 0.025 if horizontal else 0.88)
		edge.mesh = mesh; edge.material_override = ring_material
		if horizontal: edge.position = Vector3(0, 0.16, -0.44 if side == 0 else 0.44)
		else: edge.position = Vector3(-0.44 if side == 2 else 0.44, 0.16, 0)
		root.add_child(edge)

# ---- Pavilion: low-poly Yellow Crane Tower-inspired landmark ----
func _tile_pavilion_surface(root: Node3D, road_mask: int):
	var court = MeshInstance3D.new()
	var court_mesh = BoxMesh.new(); court_mesh.size = Vector3(0.94, 0.055, 0.94)
	court.mesh = court_mesh
	var court_material = StandardMaterial3D.new(); court_material.albedo_color = Color("#8f5f48"); court_material.roughness = 0.96
	court.material_override = court_material; court.position.y = 0.13
	root.add_child(court)

	var gold = StandardMaterial3D.new(); gold.albedo_color = Color("#d99a26"); gold.roughness = 0.70
	var gold_dark = StandardMaterial3D.new(); gold_dark.albedo_color = Color("#8d5a1f"); gold_dark.roughness = 0.86
	var red = StandardMaterial3D.new(); red.albedo_color = TERRAIN_TOP[4]; red.roughness = 0.88
	var dark_red = StandardMaterial3D.new(); dark_red.albedo_color = TERRAIN_MID[4]; dark_red.roughness = 0.92
	var wall = StandardMaterial3D.new(); wall.albedo_color = Color("#e2c08a"); wall.roughness = 0.86
	var shadow = StandardMaterial3D.new(); shadow.albedo_color = Color("#5b2b2b"); shadow.roughness = 0.94
	var plaque = StandardMaterial3D.new(); plaque.albedo_color = Color("#252014"); plaque.roughness = 0.92

	var tower = Node3D.new(); tower.position = Vector3.ZERO; root.add_child(tower)
	var tier_widths = [0.60, 0.52, 0.44, 0.35, 0.26]
	var tier_heights = [0.105, 0.095, 0.085, 0.078, 0.066]
	var base_y = 0.19
	for tier in tier_widths.size():
		var floor = MeshInstance3D.new(); var floor_mesh = BoxMesh.new()
		floor_mesh.size = Vector3(tier_widths[tier], tier_heights[tier], tier_widths[tier] * 0.72)
		floor.mesh = floor_mesh; floor.material_override = red
		floor.position.y = base_y + tier * 0.118
		tower.add_child(floor)

		var front_wall = MeshInstance3D.new(); var front_mesh = BoxMesh.new()
		front_mesh.size = Vector3(tier_widths[tier] * 0.55, tier_heights[tier] * 0.58, 0.014)
		front_wall.mesh = front_mesh; front_wall.material_override = wall
		front_wall.position = Vector3(0, floor.position.y + 0.005, -floor_mesh.size.z * 0.51)
		tower.add_child(front_wall)

		var eave = MeshInstance3D.new(); var eave_mesh = BoxMesh.new()
		eave_mesh.size = Vector3(tier_widths[tier] + 0.34, 0.030, tier_widths[tier] * 0.72 + 0.32)
		eave.mesh = eave_mesh; eave.material_override = gold
		eave.position.y = floor.position.y + tier_heights[tier] * 0.5 + 0.035
		tower.add_child(eave)

		var under_eave = MeshInstance3D.new(); var under_mesh = BoxMesh.new()
		under_mesh.size = Vector3(eave_mesh.size.x * 0.88, 0.018, eave_mesh.size.z * 0.86)
		under_eave.mesh = under_mesh; under_eave.material_override = gold_dark
		under_eave.position.y = eave.position.y - 0.026
		tower.add_child(under_eave)

		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var tip = MeshInstance3D.new(); var tip_mesh = BoxMesh.new()
			tip_mesh.size = Vector3(0.13, 0.026, 0.13)
			tip.mesh = tip_mesh; tip.material_override = gold
			tip.position = Vector3(corner.x * eave_mesh.size.x * 0.53, eave.position.y + 0.040, corner.y * eave_mesh.size.z * 0.53)
			tip.rotation_degrees = Vector3(11.0 * -corner.y, 45.0, 11.0 * corner.x)
			tower.add_child(tip)

		var rail = MeshInstance3D.new(); var rail_mesh = BoxMesh.new()
		rail_mesh.size = Vector3(tier_widths[tier] + 0.10, 0.020, 0.026)
		rail.mesh = rail_mesh; rail.material_override = dark_red
		rail.position = Vector3(0, floor.position.y - tier_heights[tier] * 0.18, -floor_mesh.size.z * 0.57)
		tower.add_child(rail)

		if tier == 4:
			var name_plaque = MeshInstance3D.new(); var plaque_mesh = BoxMesh.new()
			plaque_mesh.size = Vector3(0.18, 0.058, 0.018)
			name_plaque.mesh = plaque_mesh; name_plaque.material_override = plaque
			name_plaque.position = Vector3(0, eave.position.y - 0.055, -floor_mesh.size.z * 0.60)
			tower.add_child(name_plaque)

	for px in [-0.25, -0.13, 0.0, 0.13, 0.25]:
		for pz in [-0.17, 0.17]:
			var pillar = MeshInstance3D.new(); var pillar_mesh = CylinderMesh.new()
			pillar_mesh.top_radius = 0.012; pillar_mesh.bottom_radius = 0.016; pillar_mesh.height = 0.62; pillar_mesh.radial_segments = 7
			pillar.mesh = pillar_mesh; pillar.material_override = red
			pillar.position = Vector3(px, 0.50, pz); tower.add_child(pillar)

	var roof = MeshInstance3D.new(); var roof_mesh = CylinderMesh.new()
	roof_mesh.top_radius = 0.020; roof_mesh.bottom_radius = 0.17; roof_mesh.height = 0.12; roof_mesh.radial_segments = 4
	roof.mesh = roof_mesh; roof.material_override = gold
	roof.position.y = 0.83; roof.rotation_degrees.y = 45; tower.add_child(roof)

	var finial = MeshInstance3D.new(); var finial_mesh = CylinderMesh.new()
	finial_mesh.top_radius = 0.007; finial_mesh.bottom_radius = 0.017; finial_mesh.height = 0.13; finial_mesh.radial_segments = 6
	finial.mesh = finial_mesh; finial.material_override = dark_red
	finial.position.y = 0.96; tower.add_child(finial)

	for lantern_index in 2:
		var lantern = MeshInstance3D.new(); var lantern_mesh = SphereMesh.new()
		lantern_mesh.radius = 0.035; lantern_mesh.height = 0.05; lantern_mesh.radial_segments = 8; lantern_mesh.rings = 4
		lantern.mesh = lantern_mesh; lantern.material_override = red
		lantern.position = Vector3(-0.28 + lantern_index * 0.56, 0.25, -0.30)
		root.add_child(lantern)

# ================================================================
#  DECORATIONS
# ================================================================
func _spawn_decor(terr: int, parent: Node3D, road_mask: int):
	var d = Node3D.new(); parent.add_child(d)
	match terr:
		0: _decor_grass(d, road_mask)
		1: _decor_water(d, road_mask)
		2: _decor_forest(d, road_mask)
		3: _decor_desert(d, road_mask)
		4: pass

func _decor_grass(p: Node3D, road_mask: int):
	# Flowers
	for i in randi_range(2, 5):
		# Stem
		var stem = MeshInstance3D.new()
		var stm = CylinderMesh.new(); stm.top_radius = 0.008; stm.bottom_radius = 0.01; stm.height = randf_range(0.06, 0.12)
		stem.mesh = stm
		var stmat = StandardMaterial3D.new(); stmat.albedo_color = Color(0.3, 0.65, 0.2)
		stem.material_override = stmat
		var feature_pos = _feature_position(road_mask, 0.35)
		var sx = feature_pos.x; var sz = feature_pos.y
		stem.position = Vector3(sx, 0.18 + stm.height * 0.5, sz)
		p.add_child(stem)
		# Petal
		var petal = MeshInstance3D.new()
		var pm = SphereMesh.new(); pm.radius = randf_range(0.025, 0.05); pm.height = pm.radius * 2
		petal.mesh = pm
		var pmat = StandardMaterial3D.new()
		var r = randf()
		if r < 0.3: pmat.albedo_color = Color(1, 0.85, 0.2)    # yellow
		elif r < 0.6: pmat.albedo_color = Color(1, 0.45, 0.55)  # pink
		elif r < 0.8: pmat.albedo_color = Color(1, 1, 1)        # white
		else: pmat.albedo_color = Color(0.7, 0.4, 1)            # purple
		petal.material_override = pmat
		petal.position = Vector3(sx, 0.18 + stm.height + pm.radius, sz)
		p.add_child(petal)
	# Tufts add a readable grassy edge silhouette at game distance.
	var blade_material = StandardMaterial3D.new(); blade_material.albedo_color = Color("#4d9b43"); blade_material.roughness = 1.0
	for tuft_index in 2:
		var tuft_pos = _feature_position(road_mask, 0.36)
		for blade_index in 3:
			var blade = MeshInstance3D.new(); var blade_mesh = BoxMesh.new()
			var blade_height = randf_range(0.055, 0.105)
			blade_mesh.size = Vector3(0.012, blade_height, 0.018); blade.mesh = blade_mesh; blade.material_override = blade_material
			blade.position = Vector3(tuft_pos.x + (blade_index - 1) * 0.018, 0.18 + blade_height * 0.5, tuft_pos.y)
			blade.rotation_degrees.z = (blade_index - 1) * randf_range(10.0, 18.0)
			blade.rotation_degrees.y = randf_range(-25.0, 25.0); p.add_child(blade)

func _decor_water(p: Node3D, road_mask: int):
	# Lily pad
	var pad = MeshInstance3D.new()
	var pm2 = CylinderMesh.new(); pm2.top_radius = randf_range(0.08, 0.13); pm2.bottom_radius = pm2.top_radius; pm2.height = 0.012
	pad.mesh = pm2
	var pmat2 = StandardMaterial3D.new(); pmat2.albedo_color = Color(0.22, 0.65, 0.28)
	pad.material_override = pmat2
	var feature_pos = _feature_position(road_mask, 0.28)
	pad.position = Vector3(feature_pos.x, 0.12, feature_pos.y)
	p.add_child(pad)
	# Tiny lotus
	if randf() < 0.5:
		var lotus = MeshInstance3D.new()
		var lm = SphereMesh.new(); lm.radius = 0.03; lm.height = 0.05
		lotus.mesh = lm
		var lmat = StandardMaterial3D.new(); lmat.albedo_color = Color(1, 0.75, 0.88)
		lotus.material_override = lmat
		lotus.position = pad.position + Vector3(0, 0.03, 0)
		p.add_child(lotus)
	# A small reed cluster anchors the otherwise reflective surface.
	var reed_pos = _feature_position(road_mask, 0.37)
	var reed_material = StandardMaterial3D.new(); reed_material.albedo_color = Color("#6f8f47"); reed_material.roughness = 1.0
	for reed_index in 3:
		var reed = MeshInstance3D.new(); var reed_mesh = CylinderMesh.new()
		reed_mesh.top_radius = 0.006; reed_mesh.bottom_radius = 0.009; reed_mesh.height = randf_range(0.10, 0.17); reed_mesh.radial_segments = 6
		reed.mesh = reed_mesh; reed.material_override = reed_material
		reed.position = Vector3(reed_pos.x + (reed_index - 1) * 0.026, 0.12 + reed_mesh.height * 0.5, reed_pos.y + abs(reed_index - 1) * 0.012)
		reed.rotation_degrees.z = (reed_index - 1) * 5.0; p.add_child(reed)

func _decor_forest(p: Node3D, road_mask: int):
	# A compact grove with varied height reads as a forest rather than a lone tree.
	var tree_count = randi_range(2, 3)
	for tree_index in tree_count:
		var feature_pos = _feature_position(road_mask, 0.34)
		var tx = feature_pos.x; var tz = feature_pos.y
		var tree_height = randf_range(0.22, 0.38) * (1.0 if tree_index == 0 else 0.82)
		var trunk = MeshInstance3D.new(); var tm = CylinderMesh.new()
		tm.top_radius = 0.018; tm.bottom_radius = 0.030; tm.height = tree_height; tm.radial_segments = 7
		trunk.mesh = tm
		var tmat = StandardMaterial3D.new(); tmat.albedo_color = Color("#6d4828"); tmat.roughness = 1.0
		trunk.material_override = tmat; trunk.position = Vector3(tx, 0.20 + tree_height * 0.5, tz); p.add_child(trunk)
		for layer in 3:
			var fol = MeshInstance3D.new(); var fm = CylinderMesh.new()
			var layer_radius = (0.16 - layer * 0.032) * (tree_height / 0.32)
			fm.top_radius = 0.012; fm.bottom_radius = maxf(0.055, layer_radius); fm.height = 0.13; fm.radial_segments = 10
			fol.mesh = fm
			var fmat = StandardMaterial3D.new()
			fmat.albedo_color = Color("#236a3f").lerp(Color("#55a84f"), float(layer) * 0.18 + randf_range(0.0, 0.12)); fmat.roughness = 0.94
			fol.material_override = fmat
			fol.position = Vector3(tx, 0.20 + tree_height * 0.43 + layer * 0.075, tz); p.add_child(fol)

func _decor_desert(p: Node3D, road_mask: int):
	# Faceted, partially buried stones replace the previous box-like rubble.
	for i in randi_range(1, 3):
		var rock = MeshInstance3D.new()
		var rm = SphereMesh.new(); rm.radius = randf_range(0.055, 0.10); rm.height = rm.radius * 1.45; rm.radial_segments = 7; rm.rings = 4
		rock.mesh = rm
		var rmat = StandardMaterial3D.new()
		rmat.albedo_color = Color(0.62, 0.52, 0.35).lerp(Color(0.78, 0.68, 0.48), randf())
		rock.material_override = rmat
		var feature_pos = _feature_position(road_mask, 0.31)
		rock.position = Vector3(feature_pos.x, 0.17, feature_pos.y)
		rock.scale = Vector3(randf_range(0.75, 1.25), randf_range(0.55, 0.85), randf_range(0.75, 1.20))
		rock.rotation_degrees = Vector3(randf_range(-10, 10), randf_range(0, 360), randf_range(-10, 10))
		p.add_child(rock)
	# Branched cactus creates a distinctive desert silhouette.
	if randf() < 0.52:
		var cac = MeshInstance3D.new()
		var cm = CylinderMesh.new(); cm.top_radius = 0.025; cm.bottom_radius = 0.030; cm.height = randf_range(0.16, 0.24); cm.radial_segments = 8
		cac.mesh = cm
		var cmat = StandardMaterial3D.new(); cmat.albedo_color = Color(0.28, 0.58, 0.22)
		cac.material_override = cmat
		var cactus_pos = _feature_position(road_mask, 0.29)
		cac.position = Vector3(cactus_pos.x, 0.18 + cm.height * 0.5, cactus_pos.y)
		p.add_child(cac)
		for arm_side in [-1, 1]:
			if randf() > 0.72: continue
			var arm = MeshInstance3D.new(); var arm_mesh = CylinderMesh.new()
			arm_mesh.top_radius = 0.014; arm_mesh.bottom_radius = 0.018; arm_mesh.height = randf_range(0.065, 0.095); arm_mesh.radial_segments = 7
			arm.mesh = arm_mesh; arm.material_override = cmat
			arm.position = cac.position + Vector3(arm_side * 0.035, randf_range(-0.02, 0.035), 0)
			arm.rotation_degrees.z = 90.0; p.add_child(arm)

# ================================================================
#  PLANT — per-player distinct 3D model
# ================================================================
func _place_seed(pos: Vector2i) -> bool:
	if not _can_seed(pos): return false
	if not _add_flowers(pos, current_player, 10): return false
	seeds[current_player] -= 1
	flash_timer = 0.2; flash_color = PLAYER_COLORS[current_player]
	return true

func _can_seed(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= GRID_SIZE or pos.y < 0 or pos.y >= GRID_SIZE: return false
	return _is_plant_terrain(grid[pos.x][pos.y]) and _flower_total(pos) < _tile_capacity(pos) and seeds[current_player] > 0

func _add_flowers(pos: Vector2i, pid: int, amount: int) -> bool:
	if not _is_plant_terrain(grid[pos.x][pos.y]): return false
	var capacity = _tile_capacity(pos)
	var free = capacity - _flower_total(pos)
	if free <= 0: return false
	flowers[pos.x][pos.y][pid] += mini(amount, free)
	plant_age[pos.x][pos.y] = 0
	_refresh_plant_visual(pos)
	return true

func _dominant_flower_player(pos: Vector2i) -> int:
	var best_pid := -1; var best_amount := 0
	for pid in player_count:
		if flowers[pos.x][pos.y][pid] > best_amount:
			best_amount = flowers[pos.x][pos.y][pid]; best_pid = pid
	return best_pid

func _clear_plant_visual(pos: Vector2i):
	plants[pos.x][pos.y] = 0
	if plant_nodes[pos.x][pos.y] != null:
		plant_nodes[pos.x][pos.y].queue_free()
		plant_nodes[pos.x][pos.y] = null

func _refresh_plant_visual(pos: Vector2i):
	var pid = _dominant_flower_player(pos)
	if pid < 0:
		_clear_plant_visual(pos)
		return
	plants[pos.x][pos.y] = pid + 1
	if plant_nodes[pos.x][pos.y] == null:
		_spawn_plant(pos, pid)
	else:
		var fullness = float(_flower_total(pos)) / maxf(float(_tile_capacity(pos)), 1.0)
		_animate_plant_growth(plant_nodes[pos.x][pos.y], clampf(0.32 + fullness * 0.72, 0.32, 1.08), pos, pid, 1)

func _spawn_plant(pos: Vector2i, pid: int):
	var root = Node3D.new()
	root.position = _world(pos); root.position.y = 0.06
	plant_root.add_child(root)
	plant_nodes[pos.x][pos.y] = root

	var col = PLAYER_COLORS[pid]
	# Player-specific plant shape
	match pid:
		0: _plant_mushroom(root, col)    # P1: mushroom
		1: _plant_flower(root, col)      # P2: flower bud
		2: _plant_crystal(root, col)     # P3: crystal
		3: _plant_star(root, col)        # P4: star

	var mature_scale = _plant_mature_scale(pos)
	root.scale = Vector3(0.01, 0.01, 0.01)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "scale", Vector3.ONE * mature_scale, 0.72).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(root, "position:y", 0.18, 0.72).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(root, "rotation:y", 0.24, 0.72).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_spawn_growth_burst(pos, pid, 0.72)

func _plant_mature_scale(pos: Vector2i) -> float:
	return minf(1.0, 0.36 + plant_age[pos.x][pos.y] * 0.22)

func _animate_plant_growth(root: Node3D, mature_scale: float, pos: Vector2i, pid: int, age: int):
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "scale", Vector3.ONE * mature_scale, 0.58).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(root, "position:y", 0.18 + minf(age, 3) * 0.018, 0.58).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(root, "rotation:y", root.rotation.y + 0.16, 0.58).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	var settle = create_tween()
	settle.tween_property(root, "rotation:z", deg_to_rad(3.5), 0.18).set_trans(Tween.TRANS_SINE)
	settle.tween_property(root, "rotation:z", deg_to_rad(-2.0), 0.20).set_trans(Tween.TRANS_SINE)
	settle.tween_property(root, "rotation:z", 0.0, 0.18).set_trans(Tween.TRANS_SINE)
	if age == 2: _spawn_growth_burst(pos, pid, 0.62)

func _spawn_growth_burst(pos: Vector2i, pid: int, duration: float):
	var burst = Node3D.new(); burst.position = _world(pos) + Vector3(0, 0.28, 0)
	plant_root.add_child(burst)
	for i in 6:
		var mote = MeshInstance3D.new(); var mesh = SphereMesh.new()
		mesh.radius = 0.022; mesh.height = 0.044; mote.mesh = mesh
		var material = StandardMaterial3D.new(); material.albedo_color = PLAYER_COLORS[pid].lightened(0.32)
		material.emission_enabled = true; material.emission = PLAYER_COLORS[pid]; material.emission_energy_multiplier = 1.2
		mote.material_override = material; burst.add_child(mote)
		var angle = TAU * float(i) / 6.0 + randf_range(-0.18, 0.18)
		var target = Vector3(cos(angle) * 0.18, randf_range(0.14, 0.26), sin(angle) * 0.18)
		var mote_tw = create_tween(); mote_tw.set_parallel(true)
		mote_tw.tween_property(mote, "position", target, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		mote_tw.tween_property(mote, "scale", Vector3.ZERO, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	var cleanup = create_tween()
	cleanup.tween_interval(duration + 0.05)
	cleanup.tween_callback(burst.queue_free)

# P1: Mushroom
func _plant_mushroom(root: Node3D, col: Color):
	# Stem
	var stem = MeshInstance3D.new()
	var sm = CylinderMesh.new(); sm.top_radius = 0.04; sm.bottom_radius = 0.05; sm.height = 0.14
	stem.mesh = sm
	var smat = StandardMaterial3D.new(); smat.albedo_color = col.lightened(0.4)
	stem.material_override = smat; stem.position.y = 0.07
	root.add_child(stem)
	# Cap
	var cap = MeshInstance3D.new()
	var cm = SphereMesh.new(); cm.radius = 0.14; cm.height = 0.16
	cap.mesh = cm
	var cmat = StandardMaterial3D.new()
	cmat.albedo_color = col; cmat.emission_enabled = true; cmat.emission = col.darkened(0.3)
	cmat.emission_energy_multiplier = 1.0
	cap.material_override = cmat; cap.position.y = 0.18
	cap.scale = Vector3(1, 0.6, 1)
	root.add_child(cap)
	# Spots
	for i in randi_range(2, 4):
		var spot = MeshInstance3D.new()
		var spm = SphereMesh.new(); spm.radius = 0.025; spm.height = 0.05
		spot.mesh = spm
		var spmat = StandardMaterial3D.new(); spmat.albedo_color = col.lightened(0.5)
		spot.material_override = spmat
		var a = randf() * TAU; var r = randf_range(0.05, 0.10)
		spot.position = Vector3(cos(a) * r, 0.20, sin(a) * r)
		root.add_child(spot)

# P2: Flower bud
func _plant_flower(root: Node3D, col: Color):
	# Stem
	var stem = MeshInstance3D.new()
	var sm = CylinderMesh.new(); sm.top_radius = 0.02; sm.bottom_radius = 0.03; sm.height = 0.18
	stem.mesh = sm
	var smat = StandardMaterial3D.new(); smat.albedo_color = Color(0.2, 0.6, 0.2)
	stem.material_override = smat; stem.position.y = 0.09
	root.add_child(stem)
	# Petals (5 around center)
	for i in 5:
		var petal = MeshInstance3D.new()
		var pm = SphereMesh.new(); pm.radius = 0.06; pm.height = 0.08
		petal.mesh = pm
		var pmat = StandardMaterial3D.new()
		pmat.albedo_color = col; pmat.emission_enabled = true; pmat.emission = col.darkened(0.2)
		pmat.emission_energy_multiplier = 0.8
		petal.material_override = pmat
		var a = i * TAU / 5.0
		petal.position = Vector3(cos(a) * 0.07, 0.22, sin(a) * 0.07)
		petal.scale = Vector3(0.8, 0.5, 0.8)
		root.add_child(petal)
	# Center
	var center = MeshInstance3D.new()
	var cem = SphereMesh.new(); cem.radius = 0.04; cem.height = 0.06
	center.mesh = cem
	var cemat = StandardMaterial3D.new(); cemat.albedo_color = Color(1, 0.9, 0.3)
	center.material_override = cemat; center.position.y = 0.23
	root.add_child(center)

# P3: Crystal
func _plant_crystal(root: Node3D, col: Color):
	# Main crystal (elongated box, tilted)
	var crystal = MeshInstance3D.new()
	var cm = BoxMesh.new(); cm.size = Vector3(0.06, 0.25, 0.06)
	crystal.mesh = cm
	var cmat = StandardMaterial3D.new()
	cmat.albedo_color = col; cmat.metallic = 0.6; cmat.roughness = 0.15
	cmat.emission_enabled = true; cmat.emission = col.darkened(0.2)
	cmat.emission_energy_multiplier = 1.2
	crystal.material_override = cmat
	crystal.position = Vector3(0, 0.15, 0)
	crystal.rotation_degrees = Vector3(randf_range(-15, 15), randf_range(0, 360), randf_range(-15, 15))
	root.add_child(crystal)
	# Smaller crystals
	for i in randi_range(1, 3):
		var sc = MeshInstance3D.new()
		var scm = BoxMesh.new(); scm.size = Vector3(0.04, randf_range(0.10, 0.18), 0.04)
		sc.mesh = scm
		var scmat = StandardMaterial3D.new()
		scmat.albedo_color = col.lightened(0.2); scmat.metallic = 0.5; scmat.roughness = 0.2
		scmat.emission_enabled = true; scmat.emission = col; scmat.emission_energy_multiplier = 0.8
		sc.material_override = scmat
		sc.position = Vector3(randf_range(-0.06, 0.06), 0.10, randf_range(-0.06, 0.06))
		sc.rotation_degrees = Vector3(randf_range(-25, 25), randf_range(0, 360), randf_range(-25, 25))
		root.add_child(sc)

# P4: Star
func _plant_star(root: Node3D, col: Color):
	# Center sphere
	var center = MeshInstance3D.new()
	var cem = SphereMesh.new(); cem.radius = 0.06; cem.height = 0.12
	center.mesh = cem
	var cmat = StandardMaterial3D.new()
	cmat.albedo_color = col; cmat.emission_enabled = true; cmat.emission = col.darkened(0.3)
	cmat.emission_energy_multiplier = 1.0
	center.material_override = cmat; center.position.y = 0.12
	root.add_child(center)
	# 5 points
	for i in 5:
		var point = MeshInstance3D.new()
		var pm = CylinderMesh.new(); pm.top_radius = 0.005; pm.bottom_radius = 0.03; pm.height = 0.12
		point.mesh = pm
		var pmat = StandardMaterial3D.new()
		pmat.albedo_color = col; pmat.emission_enabled = true; pmat.emission = col
		pmat.emission_energy_multiplier = 0.7
		point.material_override = pmat
		var a = i * TAU / 5.0 - PI / 2
		point.position = Vector3(cos(a) * 0.06, 0.18, sin(a) * 0.06)
		point.rotation_degrees = Vector3(0, 0, rad_to_deg(a) + 90)
		point.look_at(point.position + Vector3(cos(a), 0.5, sin(a)), Vector3.UP)
		root.add_child(point)

# ================================================================
#  GAME FLOW
# ================================================================
func _make_seed_card(level: int = 1) -> Dictionary:
	return {"kind": "seed", "name": "%d级播种" % level, "level": level, "deck": "播种"}

func _draw_public_card() -> Dictionary:
	var deck = randi() % 3
	if deck == 0:
		if randf() < 0.18:
			var building_level = randi_range(1, 2)
			return {"kind": "building_develop", "name": "%d级建筑开发" % building_level, "level": building_level, "deck": "开发"}
		var level = randi_range(1, 4)
		return {"kind": "develop", "name": "%d级山体开发" % level, "level": level, "deck": "开发"}
	if deck == 1:
		var level = randi_range(1, 3)
		return {"kind": "road", "name": "%d级道路" % level, "level": level, "deck": "道路"}
	var weather_names = ["台风", "沙尘暴", "雨季", "旱季", "彩虹"]
	var weather = weather_names[randi() % weather_names.size()]
	return {"kind": "weather", "name": weather, "level": 1, "deck": "天气", "weather": weather}

func _start_player_turn():
	current_hand = hands[current_player]
	for i in CARDS_DRAWN_PER_TURN:
		current_hand.append(_draw_public_card())
	selected_card = 0
	state = S.PLAY_CARDS
	hover_mesh.visible = false
	piece_preview_root.visible = false
	_calc_all_scores()
	ui_ctrl.queue_redraw()

func _start_game():
	_init_grid()
	current_player = randi() % player_count; turns_played = 0
	total_turns = TOTAL_ROUNDS_PER_PLAYER * player_count
	seeds = []; scores = []; group_counts = []; largest_groups = []; diversity_counts = []; road_scores = []
	hands = []; current_hand = []; selected_card = 0
	piece_market = []; selected_market = 0; piece_rotation = 0; last_growth_count = 0
	closed_road_ids = {}; closed_road_cells = {}; last_road_event = ""; last_settlement = ""
	active_weather = {}; rainbow_turns = 0
	for i in player_count:
		seeds.append(STARTING_SEED_CARDS); scores.append(0); group_counts.append(0)
		largest_groups.append(0); diversity_counts.append(0); road_scores.append(0)
		var hand := []
		for card_index in STARTING_SEED_CARDS:
			hand.append(_make_seed_card(card_index + 1))
		hands.append(hand)
	_generate_start_tiles()
	_start_player_turn()

func _end_turn():
	_settle_turn()
	turns_played += 1
	_calc_all_scores()
	if turns_played >= total_turns:
		state = S.GAME_OVER; _calc_all_scores(); ui_ctrl.queue_redraw(); return
	current_player = (current_player + 1) % player_count
	_start_player_turn()

func _selected_card() -> Dictionary:
	if selected_card < 0 or selected_card >= current_hand.size(): return {}
	return current_hand[selected_card]

func _can_play_selected_card(pos: Vector2i) -> bool:
	if not _in_bounds(pos): return false
	var card = _selected_card()
	if card.is_empty(): return false
	match card["kind"]:
		"seed":
			return seeds[current_player] > 0 and _is_plant_terrain(grid[pos.x][pos.y]) and _flower_total(pos) < _tile_capacity(pos)
		"develop":
			for cell in _develop_card_cells(pos, int(card["level"]), piece_rotation):
				if not _in_bounds(cell) or not _is_developable(grid[cell.x][cell.y]): return false
			return true
		"building_develop":
			var cells = [pos] if int(card["level"]) == 1 else [pos, pos + DIRS[piece_rotation]]
			for cell in cells:
				if not _in_bounds(cell) or grid[cell.x][cell.y] != T_GAP: return false
			return true
		"road":
			for i in range(int(card["level"]) + 1):
				var cell = pos + DIRS[piece_rotation] * i
				if not _in_bounds(cell) or _is_developable(grid[cell.x][cell.y]): return false
			return true
		"weather":
			return true
	return false

func _play_selected_card(pos: Vector2i) -> bool:
	var card = _selected_card()
	if card.is_empty(): return false
	var ok := false
	match card["kind"]:
		"seed":
			ok = _add_flowers(pos, current_player, int(card["level"]) * 10)
			if ok: seeds[current_player] = maxi(0, seeds[current_player] - 1)
		"develop":
			ok = _apply_develop_card(pos, int(card["level"]))
		"building_develop":
			ok = _apply_building_develop_card(pos, int(card["level"]))
		"road":
			ok = _apply_road_card(pos, int(card["level"]))
		"weather":
			ok = _apply_weather_card(card)
	if ok:
		current_hand.remove_at(selected_card)
		selected_card = clampi(selected_card, 0, maxi(current_hand.size() - 1, 0))
		flash_timer = 0.18; flash_color = PLAYER_COLORS[current_player]
		_calc_all_scores(); ui_ctrl.queue_redraw()
	return ok

func _apply_develop_card(pos: Vector2i, level: int) -> bool:
	var cells = _develop_card_cells(pos, level, piece_rotation)
	if cells.is_empty(): return false
	for cell in cells:
		if not _in_bounds(cell) or not _is_developable(grid[cell.x][cell.y]): return false
	for cell in cells:
		_set_tile_type(cell, _draw_terrain(), true, _random_road_mask())
	_update_gaps()
	_refill_mountain_border()
	_refresh_road_effects()
	last_settlement = "开发了 %d 格新地块" % cells.size()
	return true

func _apply_building_develop_card(pos: Vector2i, level: int) -> bool:
	var cells = [pos] if level == 1 else [pos, pos + DIRS[piece_rotation]]
	for cell in cells:
		if not _in_bounds(cell) or grid[cell.x][cell.y] != T_GAP: return false
	for cell in cells:
		_set_tile_type(cell, T_BUILDING, true, 0)
	_refill_mountain_border()
	last_settlement = "缺口变为建筑"
	return true

func _develop_card_cells(pos: Vector2i, level: int, rotation: int = 0) -> Array:
	match level:
		1: return [pos]
		2: return [pos, pos + _rotate_cell(Vector2i.RIGHT, rotation)]
		3: return [pos, pos + _rotate_cell(Vector2i.RIGHT, rotation), pos + _rotate_cell(Vector2i.DOWN, rotation)]
		4:
			var shapes = [
				[Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1)],
				[Vector2i.ZERO, Vector2i.RIGHT, Vector2i(1, 1), Vector2i(2, 1)],
				[Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN],
			]
			var result := []
			for cell in shapes[randi() % shapes.size()]:
				result.append(pos + _rotate_cell(cell, rotation))
			return result
	return []

func _apply_road_card(pos: Vector2i, level: int) -> bool:
	var cells := []
	for i in range(level + 1):
		cells.append(pos + DIRS[piece_rotation] * i)
	for cell in cells:
		if not _in_bounds(cell) or _is_developable(grid[cell.x][cell.y]): return false
	for i in cells.size() - 1:
		var a: Vector2i = cells[i]; var b: Vector2i = cells[i + 1]
		_connect_road(a, b)
	for cell in cells:
		_update_road_bridges(cell)
	_refresh_road_effects()
	last_settlement = "修建了长度%d道路" % level
	return true

func _connect_road(a: Vector2i, b: Vector2i):
	var dir_index = _direction_index(b - a)
	if dir_index < 0: return
	roads[a.x][a.y] |= 1 << dir_index
	roads[b.x][b.y] |= 1 << ((dir_index + 2) % 4)
	_redraw_tile(a)
	_redraw_tile(b)

func _apply_weather_card(card: Dictionary) -> bool:
	var weather: String = card["weather"]
	if weather == "彩虹":
		active_weather.clear()
		rainbow_turns = 1
		last_settlement = "彩虹清除了极端天气"
	else:
		active_weather[weather] = 3
		last_settlement = "%s将持续3回合" % weather
	return true

func _settle_turn():
	_apply_weather_tile_changes()
	_apply_neighbor_terrain_changes()
	_grow_flowers()
	_spread_flowers()
	_tick_weather()
	_refresh_all_plants()
	_calc_all_scores()

func _tick_weather():
	var expired := []
	for weather in active_weather.keys():
		active_weather[weather] = int(active_weather[weather]) - 1
		if active_weather[weather] <= 0: expired.append(weather)
	for weather in expired: active_weather.erase(weather)
	if rainbow_turns > 0: rainbow_turns -= 1

func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_SIZE and pos.y >= 0 and pos.y < GRID_SIZE

func _apply_weather_tile_changes():
	if active_weather.has("台风"):
		var waters := []
		for x in GRID_SIZE:
			for y in GRID_SIZE:
				if grid[x][y] == T_WATER: waters.append(Vector2i(x, y))
		for pos in waters:
			_weather_convert_neighbor(pos, T_WATER)
	if active_weather.has("沙尘暴"):
		var deserts := []
		for x in GRID_SIZE:
			for y in GRID_SIZE:
				if grid[x][y] == T_DESERT: deserts.append(Vector2i(x, y))
		for pos in deserts:
			_weather_convert_neighbor(pos, T_DESERT)

func _weather_convert_neighbor(pos: Vector2i, terr: int):
	var options := []
	for dir in DIRS:
		var p = pos + dir
		if _in_bounds(p) and not _is_developable(grid[p.x][p.y]) and grid[p.x][p.y] != T_BUILDING:
			options.append(p)
	if options.is_empty(): return
	_set_tile_type(options[randi() % options.size()], terr, true)

func _apply_neighbor_terrain_changes():
	var changes := []
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var pos = Vector2i(x, y)
			var terr = grid[x][y]
			if not _is_plant_terrain(terr): continue
			var chance := 0.0
			for dir in DIRS:
				var n = pos + dir
				if not _in_bounds(n): continue
				match grid[n.x][n.y]:
					T_WATER: chance += 0.20
					T_FOREST: chance += 0.10
					T_DESERT: chance -= 0.10
			if chance > 0.0 and _has_neighbor_bonus(pos, T_WATER): chance *= 2.0
			if active_weather.has("雨季") and chance > 0.0: chance *= 2.0
			if active_weather.has("旱季") and chance < 0.0: chance *= 2.0
			if chance > 0.0 and randf() < chance:
				if terr == T_DESERT: changes.append([pos, T_GRASS])
				elif terr == T_GRASS: changes.append([pos, T_FOREST])
			elif chance < 0.0 and randf() < absf(chance):
				if terr == T_FOREST: changes.append([pos, T_GRASS])
				elif terr == T_GRASS: changes.append([pos, T_DESERT])
	for change in changes:
		_set_tile_type(change[0], change[1], true)

func _grow_flowers():
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var pos = Vector2i(x, y)
			if not _is_plant_terrain(grid[x][y]): continue
			var cap = _tile_capacity(pos)
			var total = _flower_total(pos)
			if total <= 0 or total >= cap: continue
			var rate: float = TERRAIN_GROWTH[grid[x][y]]
			if _has_extreme_weather(): rate *= 0.5
			if rainbow_turns > 0: rate *= 2.0
			var free = cap - total
			var planned = [0, 0, 0, 0]
			var planned_total := 0
			for pid in player_count:
				var amount: int = flowers[x][y][pid]
				if amount <= 0: continue
				planned[pid] = floori(amount * rate)
				planned_total += planned[pid]
			if planned_total <= 0: continue
			for pid in player_count:
				var add = planned[pid] if planned_total <= free else floori(float(free) * float(planned[pid]) / float(planned_total))
				flowers[x][y][pid] += add

func _spread_flowers():
	var additions := []
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			var pos = Vector2i(x, y)
			if not _is_plant_terrain(grid[x][y]) or roads[x][y] != 0: continue
			var cap = _tile_capacity(pos)
			if _flower_total(pos) >= cap: continue
			var neighbor_capacity := 0
			for dir in DIRS:
				var n = pos + dir
				if _in_bounds(n) and _is_plant_terrain(grid[n.x][n.y]):
					neighbor_capacity += _tile_capacity(n)
			if neighbor_capacity <= 0: continue
			var prob = 1.0
			if rainbow_turns > 0: prob = 2.0
			var add_for_tile = [0, 0, 0, 0]
			for dir in DIRS:
				var n = pos + dir
				if not _in_bounds(n) or not _is_plant_terrain(grid[n.x][n.y]): continue
				for pid in player_count:
					var amount: int = flowers[n.x][n.y][pid]
					if amount > 0:
						add_for_tile[pid] += floori(float(amount * amount) / float(neighbor_capacity) * prob)
			additions.append([pos, add_for_tile])
	for entry in additions:
		var pos: Vector2i = entry[0]
		var add_for_tile: Array = entry[1]
		var free = _tile_capacity(pos) - _flower_total(pos)
		var add_total := 0
		for pid in player_count: add_total += add_for_tile[pid]
		if add_total <= 0: continue
		for pid in player_count:
			var add = add_for_tile[pid] if add_total <= free else floori(float(free) * float(add_for_tile[pid]) / float(add_total))
			flowers[pos.x][pos.y][pid] += add

func _has_extreme_weather() -> bool:
	return active_weather.has("台风") or active_weather.has("沙尘暴") or active_weather.has("雨季") or active_weather.has("旱季")

func _refresh_all_plants():
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			_refresh_plant_visual(Vector2i(x, y))

func _update_gaps():
	for x in range(1, GRID_SIZE - 1):
		for y in range(1, GRID_SIZE - 1):
			if grid[x][y] != T_MOUNTAIN: continue
			var surrounded := true
			for dir in DIRS:
				var n = Vector2i(x, y) + dir
				if _is_developable(grid[n.x][n.y]):
					surrounded = false; break
			if surrounded: _set_tile_type(Vector2i(x, y), T_GAP, true, 0)

func _refill_mountain_border():
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if x == 0 or y == 0 or x == GRID_SIZE - 1 or y == GRID_SIZE - 1:
				if grid[x][y] == T_GAP:
					_set_tile_type(Vector2i(x, y), T_MOUNTAIN, true, 0)

func _do_grow():
	var new_p := []; var new_a := []
	last_growth_count = 0
	for x in GRID_SIZE:
		new_p.append([]); new_a.append([])
		for y in GRID_SIZE:
			new_p[x].append(plants[x][y]); new_a[x].append(plant_age[x][y])

	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if plants[x][y] == current_player + 1:
				for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var nx = x + d.x; var ny = y + d.y
					if nx >= 0 and nx < GRID_SIZE and ny >= 0 and ny < GRID_SIZE:
						var neighbor = Vector2i(nx, ny)
						var connected = grid[nx][ny] == grid[x][y] or _roads_connect(Vector2i(x, y), neighbor)
						if connected and plants[nx][ny] == 0:
							# Established plants become a little more reliable without removing risk.
							var maturity_bonus = minf(0.12, plant_age[x][y] * 0.02)
							var spread_chance = TERRAIN_SPREAD[grid[x][y]] + maturity_bonus
							if _roads_connect(Vector2i(x, y), neighbor): spread_chance += 0.12
							if randf() < spread_chance:
								new_p[nx][ny] = current_player + 1; new_a[nx][ny] = 0

	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if new_p[x][y] != 0 and new_p[x][y] != plants[x][y]:
				plants[x][y] = new_p[x][y]; plant_age[x][y] = 0
				last_growth_count += 1
				_spawn_plant(Vector2i(x, y), plants[x][y] - 1)
			elif plants[x][y] != 0:
				plant_age[x][y] = new_a[x][y] + 1
				if plant_nodes[x][y] != null and plant_age[x][y] <= 3:
					var pos = Vector2i(x, y)
					_animate_plant_growth(plant_nodes[x][y], _plant_mature_scale(pos), pos, plants[x][y] - 1, plant_age[x][y])

func _calc_all_scores():
	for pid in player_count:
		var flower_score := 0
		var occupied_tiles := 0
		for x in GRID_SIZE:
			for y in GRID_SIZE:
				var amount: int = flowers[x][y][pid]
				if amount > 0:
					flower_score += amount
					if _is_plant_terrain(grid[x][y]): occupied_tiles += 1
		var vis := []
		for x in GRID_SIZE:
			vis.append([])
			for y in GRID_SIZE: vis[x].append(false)
		var groups := 0; var largest := 0
		for x in GRID_SIZE:
			for y in GRID_SIZE:
				if flowers[x][y][pid] > 0 and not vis[x][y]:
					groups += 1
					largest = maxi(largest, _flood_p(x, y, vis, pid + 1))
		var road_score = _player_road_score(pid + 1)
		scores[pid] = flower_score
		group_counts[pid] = groups; largest_groups[pid] = largest; diversity_counts[pid] = occupied_tiles
		road_scores[pid] = road_score

func _roads_connect(from: Vector2i, to: Vector2i) -> bool:
	var dir_index = _direction_index(to - from)
	if dir_index < 0: return false
	return (roads[from.x][from.y] & (1 << dir_index)) != 0 and (roads[to.x][to.y] & (1 << ((dir_index + 2) % 4))) != 0

func _player_road_score(pid: int) -> int:
	var connections := 0
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if flowers[x][y][pid - 1] <= 0: continue
			var pos = Vector2i(x, y)
			if closed_road_cells.has(pos): connections += 2
			for dir in [Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor = pos + dir
				if neighbor.x < GRID_SIZE and neighbor.y < GRID_SIZE and flowers[neighbor.x][neighbor.y][pid - 1] > 0:
					if _roads_connect(pos, neighbor): connections += 1
	return connections

func _flood_p(x: int, y: int, v: Array, pid: int) -> int:
	if x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE: return 0
	if v[x][y] or flowers[x][y][pid - 1] <= 0: return 0
	v[x][y] = true
	return 1 + _flood_p(x+1,y,v,pid) + _flood_p(x-1,y,v,pid) + _flood_p(x,y+1,v,pid) + _flood_p(x,y-1,v,pid)

# ================================================================
#  MOUSE
# ================================================================
func _mouse_to_grid(mp: Vector2) -> Vector2i:
	var from = camera.project_ray_origin(mp)
	var dir = camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001: return Vector2i(-1, -1)
	var t = -from.y / dir.y
	if t < 0: return Vector2i(-1, -1)
	var hit = from + dir * t
	var off = (GRID_SIZE - 1) * TILE_SPACING * 0.5
	var gx = roundi((hit.x + off) / TILE_SPACING)
	var gy = roundi((hit.z + off) / TILE_SPACING)
	if gx >= 0 and gx < GRID_SIZE and gy >= 0 and gy < GRID_SIZE: return Vector2i(gx, gy)
	return Vector2i(-1, -1)

func _update_piece_preview():
	for child in piece_preview_root.get_children(): child.free()
	if state != S.PLACE_TILE or hovered_cell.x < 0 or piece_market.is_empty():
		piece_preview_root.visible = false; return
	var piece: Dictionary = piece_market[selected_market]
	var cells = _piece_cells(piece, piece_rotation)
	var valid = _can_place_piece_data(hovered_cell, piece, piece_rotation)
	piece_preview_root.visible = true
	for i in cells.size():
		var root = Node3D.new(); root.position = _world(hovered_cell + cells[i]); root.position.y = 0.20
		piece_preview_root.add_child(root)
		var mesh_instance = MeshInstance3D.new(); var box = BoxMesh.new()
		box.size = Vector3(1.06, 0.06, 1.06); mesh_instance.mesh = box
		var material = StandardMaterial3D.new()
		var color = TERRAIN_TOP[piece["terrains"][i]] if valid else Color("#e34b43")
		color.a = 0.58; material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.no_depth_test = true
		mesh_instance.material_override = material; mesh_instance.position.y = 0.28; root.add_child(mesh_instance)
		_spawn_road(root, _rotate_road_mask(piece["roads"][i], piece_rotation))

func _rotate_selected_piece(delta: int):
	if state != S.PLACE_TILE: return
	piece_rotation = posmod(piece_rotation + delta, 4)
	_update_piece_preview(); ui_ctrl.queue_redraw()

# ================================================================
#  LOOP
# ================================================================
func _process(delta):
	pulse += delta
	if flash_timer > 0: flash_timer = max(0, flash_timer - delta * 2.5)
	_animate_sky_world(delta)

	var viewport_size = get_viewport().get_visible_rect().size
	var interface_scale = _ui_scale(viewport_size)
	var panel_width = UI_SIDEBAR_WIDTH * interface_scale
	var play_width = maxf(viewport_size.x - panel_width, viewport_size.x * 0.45)
	var play_aspect = maxf(play_width / maxf(viewport_size.y, 1.0), 0.35)
	var camera_fit = maxf(1.0, 1.05 / play_aspect)

	# Smooth zoom interpolation while keeping the board inside the free play area.
	cam_zoom = lerp(cam_zoom, cam_zoom_target, delta * 10.0)
	camera.size = CAM_BASE_SIZE * camera_fit / cam_zoom

	# Smooth pan interpolation
	cam_offset = cam_offset.lerp(cam_offset_target, delta * 10.0)
	var base_pos = Vector3(7.2, 14.2, 10.8)
	# Convert 2D offset to 3D (isometric axes)
	var ortho_width = camera.size * viewport_size.x / maxf(viewport_size.y, 1.0)
	var panel_ratio = panel_width / maxf(viewport_size.x, 1.0)
	var camera_shift = camera.transform.basis.x * ortho_width * panel_ratio * 0.42
	camera.position = base_pos + Vector3(cam_offset.x, 0, cam_offset.y) + camera_shift

	ui_ctrl.queue_redraw()

func _animate_sky_world(delta: float):
	for cloud in drifting_clouds:
		cloud.position.x += cloud.get_meta("speed") * delta
		cloud.position.z = cloud.get_meta("base_z") + sin(pulse * 0.32 + cloud.get_meta("phase")) * 0.62
		cloud.position.y = cloud.get_meta("base_y") + sin(pulse * 0.28 + cloud.get_meta("phase")) * cloud.get_meta("bob")
		cloud.rotation.y = sin(pulse * 0.10 + cloud.get_meta("phase")) * 0.035
		if cloud.position.x > 18.0: cloud.position.x = -18.0
	for mote in sky_motes:
		var mote_speed: float = mote.get_meta("speed")
		mote.position.y = mote.get_meta("base_y") + sin(pulse * mote_speed + mote.get_meta("phase")) * 0.32
		mote.rotation.y += delta * mote_speed

func _ui_scale(viewport_size: Vector2) -> float:
	return clampf(minf(viewport_size.x / UI_DESIGN_SIZE.x, viewport_size.y / UI_DESIGN_SIZE.y), 0.35, 1.5)

func _ui_point(screen_point: Vector2) -> Vector2:
	return screen_point / _ui_scale(get_viewport().get_visible_rect().size)

func _cover_source_rect(texture: Texture2D, target_size: Vector2) -> Rect2:
	var source_size = texture.get_size()
	var source_aspect = source_size.x / source_size.y
	var target_aspect = target_size.x / maxf(target_size.y, 1.0)
	if source_aspect > target_aspect:
		var crop_width = source_size.y * target_aspect
		return Rect2(Vector2((source_size.x - crop_width) * 0.5, 0.0), Vector2(crop_width, source_size.y))
	var crop_height = source_size.x / target_aspect
	return Rect2(Vector2(0.0, (source_size.y - crop_height) * 0.5), Vector2(source_size.x, crop_height))

func _input(event):
	if state == S.TITLE:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_2: player_count = 2; state = S.PLAY_CARDS; _start_game()
			elif event.keycode == KEY_3: player_count = 3; state = S.PLAY_CARDS; _start_game()
			elif event.keycode == KEY_4: player_count = 4; state = S.PLAY_CARDS; _start_game()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var vp = get_viewport().get_visible_rect().size / _ui_scale(get_viewport().get_visible_rect().size)
			var ui_pointer = _ui_point(event.position)
			for i in 3:
				var button_rect = Rect2(vp.x * 0.5 - 110 + i * 130.0, vp.y * 0.53, 100, 50)
				if button_rect.has_point(ui_pointer):
					player_count = i + 2; state = S.PLAY_CARDS; _start_game(); return
		return

	# ---- Zoom: scroll wheel ----
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom_target = clamp(cam_zoom_target + CAM_ZOOM_SPEED, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom_target = clamp(cam_zoom_target - CAM_ZOOM_SPEED, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
			return

	# ---- Zoom: trackpad pinch (macOS MagnifyGesture) ----
	if event is InputEventMagnifyGesture:
		cam_zoom_target = clamp(cam_zoom_target + event.factor * 0.5, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
		return

	# ---- Pan: middle mouse button drag ----
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_panning = true; pan_start = event.position; cam_pan_start = cam_offset_target
			else:
				is_panning = false
			return

	if event is InputEventMouseMotion:
		if is_panning:
			var delta_pos = (event.position - pan_start) * CAM_PAN_SPEED / cam_zoom
			cam_offset_target = cam_pan_start + Vector2(-delta_pos.x, -delta_pos.y)
			return
		var nc = _mouse_to_grid(event.position)
		if nc != hovered_cell:
			hovered_cell = nc
			if state == S.PLACE_TILE:
				hover_mesh.visible = false; _update_piece_preview()
			elif state == S.PLAY_CARDS and hovered_cell.x >= 0:
				hover_mesh.visible = true
				hover_mesh.position = _world(hovered_cell); hover_mesh.position.y = 0.52
				hover_material.albedo_color = Color(0.35, 1.0, 0.72, 0.30) if _can_play_selected_card(hovered_cell) else Color(1.0, 0.28, 0.24, 0.24)
			elif hovered_cell.x >= 0:
				hover_mesh.visible = true
				hover_mesh.position = _world(hovered_cell); hover_mesh.position.y = 0.48
				var valid = _can_seed(hovered_cell)
				hover_material.albedo_color = Color(0.35, 1.0, 0.72, 0.38) if valid else Color(1.0, 0.28, 0.24, 0.28)
			else:
				hover_mesh.visible = false; piece_preview_root.visible = false

	# ---- Pan: trackpad two-finger scroll (PanGesture) ----
	if event is InputEventPanGesture:
		cam_offset_target += Vector2(-event.delta.x, -event.delta.y) * CAM_PAN_SPEED * 2.0 / cam_zoom
		return

	if event is InputEventMouseButton and event.pressed:
		var cell = _mouse_to_grid(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if state == S.PLAY_CARDS:
				_play_selected_card(cell)
			elif state == S.PLACE_TILE:
				if _place_piece(cell): _consume_market_tile(); state = S.PLACE_SEED; ui_ctrl.queue_redraw()
			elif state == S.PLACE_SEED:
				if _place_seed(cell): _end_turn()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if state == S.PLAY_CARDS or state == S.PLACE_SEED: _end_turn()

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R: get_tree().reload_current_scene()
		elif state == S.PLAY_CARDS and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			selected_card = clampi(event.keycode - KEY_1, 0, maxi(current_hand.size() - 1, 0)); ui_ctrl.queue_redraw()
		elif state == S.PLAY_CARDS and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE):
			_end_turn()
		elif state == S.PLAY_CARDS and event.keycode == KEY_Q:
			piece_rotation = posmod(piece_rotation - 1, 4); ui_ctrl.queue_redraw()
		elif state == S.PLAY_CARDS and event.keycode == KEY_E:
			piece_rotation = posmod(piece_rotation + 1, 4); ui_ctrl.queue_redraw()
		elif state == S.PLACE_TILE and event.keycode >= KEY_1 and event.keycode <= KEY_3:
			_select_market(event.keycode - KEY_1)
		elif event.keycode == KEY_Q: _rotate_selected_piece(-1)
		elif event.keycode == KEY_E: _rotate_selected_piece(1)
		# Reset camera with C key
		elif event.keycode == KEY_C:
			cam_zoom_target = 1.0; cam_offset_target = Vector2.ZERO

# ================================================================
#  UI
# ================================================================
func _draw_ui():
	var font = ThemeDB.fallback_font
	var screen_size = get_viewport().get_visible_rect().size
	var interface_scale = _ui_scale(screen_size)
	ui_ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * interface_scale)
	var vp = screen_size / interface_scale
	var ux = vp.x - 320.0; var uy = 30.0
	var glass = Color(0.96, 0.99, 0.96, 0.48)
	var glass_strong = Color(1.00, 1.00, 0.98, 0.58)
	var glass_soft = Color(0.86, 0.95, 0.92, 0.38)
	var glass_line = Color(1.00, 1.00, 1.00, 0.52)
	var ink = Color(0.08, 0.14, 0.13)
	var muted = Color(0.36, 0.48, 0.45)

	if state == S.TITLE: _draw_title(vp, font); return
	if state == S.GAME_OVER: _draw_gameover(vp, font); return

	var pcol = PLAYER_COLORS[current_player]
	_draw_glass_card(Rect2(ux, uy, 270, 54), glass_strong, pcol.lightened(0.10))
	var st := "出牌阶段"
	ui_ctrl.draw_circle(Vector2(ux + 24, uy + 27), 8, pcol)
	ui_ctrl.draw_string(font, Vector2(ux + 42, uy + 23), PLAYER_NAMES[current_player], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, pcol.darkened(0.16))
	ui_ctrl.draw_string(font, Vector2(ux + 128, uy + 23), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)

	var sy = uy + 70
	_draw_glass_card(Rect2(ux, sy - 6, 270, 112), glass, glass_line)
	ui_ctrl.draw_string(font, Vector2(ux + 12, sy + 2), "守育进度", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, muted)
	ui_ctrl.draw_string(font, Vector2(ux + 12, sy + 27), "%d / %d" % [turns_played + 1, total_turns], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	var bp = float(turns_played) / total_turns
	ui_ctrl.draw_rect(Rect2(ux + 12, sy + 40, 246, 8), Color(1.0, 1.0, 1.0, 0.38), 0, true, 4.0)
	ui_ctrl.draw_rect(Rect2(ux + 12, sy + 40, 246 * bp, 8), pcol, 0, true, 4.0)

	ui_ctrl.draw_string(font, Vector2(ux + 12, sy + 70), "播种卡", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, muted)
	ui_ctrl.draw_string(font, Vector2(ux + 54, sy + 71), str(seeds[current_player]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	ui_ctrl.draw_string(font, Vector2(ux + 120, sy + 70), "花朵总数", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, muted)
	for i in player_count:
		ui_ctrl.draw_circle(Vector2(ux + 125, sy + 92 + i * 21 - 3), 5, PLAYER_COLORS[i])
		ui_ctrl.draw_string(font, Vector2(ux + 136, sy + 92 + i * 21), PLAYER_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PLAYER_COLORS[i].darkened(0.18))
		ui_ctrl.draw_string(font, Vector2(ux + 226, sy + 92 + i * 21), str(scores[i]), HORIZONTAL_ALIGNMENT_RIGHT, 30, 14, ink)

	var iy = sy + 192
	_draw_glass_card(Rect2(ux, iy - 8, 270, 170), glass, glass_line)
	ui_ctrl.draw_string(font, Vector2(ux + 12, iy + 4), "手牌 · 数字键选择", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, muted)
	for i in mini(current_hand.size(), 6):
		var card: Dictionary = current_hand[i]
		var cy = iy + 28 + i * 21
		var line_color = pcol if i == selected_card else Color(1, 1, 1, 0.28)
		ui_ctrl.draw_rect(Rect2(ux + 10, cy - 14, 250, 18), Color(1, 1, 1, 0.34) if i == selected_card else Color(1, 1, 1, 0.16), 0, true, 8.0)
		ui_ctrl.draw_rect(Rect2(ux + 12, cy - 12, 3, 14), line_color, 0, true, 2.0)
		ui_ctrl.draw_string(font, Vector2(ux + 22, cy), "%d  %s  [%s]" % [i + 1, card["name"], card["deck"]], HORIZONTAL_ALIGNMENT_LEFT, 220, 12, ink)
	if current_hand.size() > 6:
		ui_ctrl.draw_string(font, Vector2(ux + 18, iy + 156), "+%d 张未显示" % (current_hand.size() - 6), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, muted)
	else:
		var dir_names = ["上", "右", "下", "左"]
		ui_ctrl.draw_string(font, Vector2(ux + 18, iy + 156), "左键使用 · Q/E方向:%s · 右键结算" % dir_names[piece_rotation], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#746239"))

	var wy = iy + 182
	_draw_glass_card(Rect2(ux, wy - 8, 270, 62), glass_soft, glass_line)
	var weather_text := "天气："
	if active_weather.is_empty() and rainbow_turns <= 0:
		weather_text += "平稳"
	else:
		for weather in active_weather.keys():
			weather_text += "%s%d " % [weather, active_weather[weather]]
		if rainbow_turns > 0: weather_text += "彩虹 "
	ui_ctrl.draw_string(font, Vector2(ux + 12, wy + 4), weather_text, HORIZONTAL_ALIGNMENT_LEFT, 248, 13, ink)
	ui_ctrl.draw_string(font, Vector2(ux + 12, wy + 29), last_settlement, HORIZONTAL_ALIGNMENT_LEFT, 248, 12, muted)

	var ly = vp.y - 250.0
	_draw_glass_card(Rect2(ux, ly - 10, 270, 174), glass_soft, glass_line)
	ui_ctrl.draw_string(font, Vector2(ux + 12, ly), "地形", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, muted)
	for i in TERRAIN_TOP.size():
		ui_ctrl.draw_rect(Rect2(ux + 12, ly + 14 + i * 24, 14, 14), TERRAIN_TOP[i], 0, true, 4.0)
		ui_ctrl.draw_string(font, Vector2(ux + 32, ly + 26 + i * 24), TERRAIN_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	ui_ctrl.draw_string(font, Vector2(ux + 120, ly), "玩家", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, muted)
	for i in player_count:
		ui_ctrl.draw_circle(Vector2(ux + 128, ly + 20 + i * 24), 6, PLAYER_COLORS[i])
		ui_ctrl.draw_string(font, Vector2(ux + 140, ly + 26 + i * 24), PLAYER_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PLAYER_COLORS[i].darkened(0.18))
	ui_ctrl.draw_line(Vector2(ux + 4, vp.y - 55), Vector2(ux + 266, vp.y - 55), Color(1.0, 1.0, 1.0, 0.28), 1.0)
	ui_ctrl.draw_string(font, Vector2(ux + 12, vp.y - 36), "缩放/平移照旧 · R 重开", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, muted)

func _draw_glass_card(rect: Rect2, fill: Color, line: Color = Color(1.0, 1.0, 1.0, 0.45), radius: float = 18.0):
	var shadow = StyleBoxFlat.new()
	shadow.bg_color = Color(0.02, 0.06, 0.05, 0.11)
	shadow.corner_radius_top_left = int(radius); shadow.corner_radius_top_right = int(radius)
	shadow.corner_radius_bottom_left = int(radius); shadow.corner_radius_bottom_right = int(radius)
	ui_ctrl.draw_style_box(shadow, Rect2(rect.position + Vector2(0, 8), rect.size))
	var frost = StyleBoxFlat.new()
	frost.bg_color = fill
	frost.border_color = line; frost.set_border_width_all(1)
	frost.corner_radius_top_left = int(radius); frost.corner_radius_top_right = int(radius)
	frost.corner_radius_bottom_left = int(radius); frost.corner_radius_bottom_right = int(radius)
	ui_ctrl.draw_style_box(frost, rect)
	var sheen = StyleBoxFlat.new()
	sheen.bg_color = Color(1.0, 1.0, 1.0, 0.13)
	sheen.corner_radius_top_left = int(radius); sheen.corner_radius_top_right = int(radius)
	sheen.corner_radius_bottom_left = int(radius); sheen.corner_radius_bottom_right = int(radius)
	ui_ctrl.draw_style_box(sheen, Rect2(rect.position + Vector2(1, 1), Vector2(rect.size.x - 2, rect.size.y * 0.45)))
	ui_ctrl.draw_rect(Rect2(rect.position + Vector2(8, 6), Vector2(rect.size.x - 16, 1.2)), Color(1.0, 1.0, 1.0, 0.42))

func _draw_title(vp: Vector2, font: Font):
	ui_ctrl.draw_texture_rect_region(TITLE_BACKGROUND, Rect2(Vector2.ZERO, vp), _cover_source_rect(TITLE_BACKGROUND, vp))
	ui_ctrl.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.008, 0.035, 0.04, 0.27))
	ui_ctrl.draw_rect(Rect2(0, 0, vp.x, vp.y * 0.46), Color(0.01, 0.06, 0.065, 0.28))

	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 140, vp.y * 0.20), "蔓  延", HORIZONTAL_ALIGNMENT_LEFT, -1, 90, Color(0.94, 1.0, 0.93))
	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 170, vp.y * 0.20 + 68), "G R O W  C A S S O N N E", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.55, 0.92, 0.68))
	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 120, vp.y * 0.22 + 108), "抽牌开发 · 道路天气 · 花朵蔓延", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.65, 0.62))

	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 120, vp.y * 0.48), "选择玩家人数:", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.85, 0.85, 0.85))
	for i in 3:
		var np = i + 2
		var bx = vp.x * 0.5 - 110 + i * 130.0; var by = vp.y * 0.53
		ui_ctrl.draw_rect(Rect2(bx, by, 100, 50), Color(0.02, 0.09, 0.09, 0.88), 0, true, 6.0)
		ui_ctrl.draw_rect(Rect2(bx, by + 46, 100, 4), PLAYER_COLORS[np - 2])
		ui_ctrl.draw_string(font, Vector2(bx + 25, by + 34), "%d 人" % np, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, PLAYER_COLORS[np - 2].lightened(0.2))

	var blink = sin(pulse * 2.2) * 0.3 + 0.7
	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 140, vp.y * 0.64), "按 2 / 3 / 4 或点击选择人数", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, blink))

	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 165, vp.y * 0.75), "使用开发、道路、天气和播种卡，经营中心花朵网络", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.50, 0.56, 0.54))
	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 165, vp.y * 0.79), "花朵总数最高获胜，平局比较占据植物地块数", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.44, 0.50, 0.48))
	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 90, vp.y * 0.90), "GGJ 2025  ·  GROW Theme", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.22, 0.22, 0.22))

func _draw_gameover(vp: Vector2, font: Font):
	ui_ctrl.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.85))
	var cx = vp.x * 0.5
	ui_ctrl.draw_string(font, Vector2(cx - 130, vp.y * 0.12), "游戏结束", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color.WHITE)

	var max_s = -1; var winner = 0
	for i in player_count:
		var wins_tie = scores[i] == max_s and diversity_counts[i] > diversity_counts[winner]
		if scores[i] > max_s or wins_tie: max_s = scores[i]; winner = i

	for i in player_count:
		var py = vp.y * 0.24 + i * 90.0
		var is_w = (i == winner)
		if is_w: ui_ctrl.draw_rect(Rect2(cx - 200, py - 18, 400, 72), PLAYER_COLORS[i].darkened(0.6), 0, true, 12.0)
		ui_ctrl.draw_circle(Vector2(cx - 165, py + 16), 14, PLAYER_COLORS[i])
		ui_ctrl.draw_string(font, Vector2(cx - 140, py + 24), PLAYER_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, PLAYER_COLORS[i])
		var pc := 0
		for x in GRID_SIZE:
			for y in GRID_SIZE:
				if plants[x][y] == i + 1: pc += 1
		ui_ctrl.draw_string(font, Vector2(cx - 20, py + 10), "%d 花" % scores[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.YELLOW if is_w else Color(0.8, 0.8, 0.8))
		ui_ctrl.draw_string(font, Vector2(cx + 90, py + 10), "占据%d格 · 最大%d格 · 路%d" % [diversity_counts[i], largest_groups[i], road_scores[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.5, 0.5, 0.5))
		if is_w: ui_ctrl.draw_string(font, Vector2(cx + 80, py + 32), "★ 胜利!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, PLAYER_COLORS[i].lightened(0.3))

	var blink = sin(pulse * 2.5) * 0.3 + 0.7
	ui_ctrl.draw_string(font, Vector2(cx - 75, vp.y * 0.88), "按 R 重新开始", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, blink))
