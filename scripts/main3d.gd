extends Node3D

const WATER_TILE_SHADER: Shader = preload("res://shaders/water_tile.gdshader")
const UI_FROSTED_GLASS_SHADER: Shader = preload("res://shaders/ui_frosted_glass.gdshader")

# ---- Config ----
const GRID_SIZE := 8
const BOARD_GROW_MARGIN := 2
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
enum S { TITLE, DRAW_CARDS, PLACE_TILE, PLACE_SEED, PLAY_CARDS, GAME_OVER }

var grid := []; var roads := []; var plants := []; var plant_age := []; var flowers := []
var grid_origin := Vector2i.ZERO
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
var special_buildings := {}
var draws_remaining := 0
var dragging_card := false; var drag_card_index := -1; var drag_pointer := Vector2.ZERO
var card_drag_origin := Vector2.ZERO
var card_armed := false; var road_drawing := false
var hovered_card_index := -1
var hovered_deck_index := -1
var pending_develop := {}; var develop_preview_cells := []
var road_drag_cells := []; var road_drag_level := 0
var hovered_cell := Vector2i(-1, -1); var pulse := 0.0
var flash_timer := 0.0; var flash_color := Color.WHITE
var title_hovered_player := -1

# Camera zoom/pan
var cam_zoom := 1.0; var cam_zoom_target := 1.0
const CAM_ZOOM_MIN := 0.22; const CAM_ZOOM_MAX := 3.2
const CAM_ZOOM_SPEED := 0.16
var cam_offset := Vector2.ZERO; var cam_offset_target := Vector2.ZERO
var is_panning := false; var pan_start := Vector2.ZERO
var cam_pan_start := Vector2.ZERO
const CAM_PAN_SPEED := 0.015
const CAM_BASE_SIZE := 14.5
const UI_DESIGN_SIZE := Vector2(1280.0, 720.0)
const UI_MARGIN := 18.0
const UI_TOP_HEIGHT := 54.0
const UI_RAIL_HEIGHT := 188.0
const UI_SIDE_TOP := 82.0
const UI_SIDE_BOTTOM := 228.0

# Nodes
var camera: Camera3D; var grid_root: Node3D; var plant_root: Node3D
var decor_root: Node3D; var piece_preview_root: Node3D
var hover_mesh: MeshInstance3D; var hover_material: StandardMaterial3D; var ui_ctrl: Control
var sky_root: Node3D; var drifting_clouds := []; var sky_motes := []
var falling_leaves := []; var animated_grass_patches := []
var tile_select_root: Node3D; var selected_tile := Vector2i(-1, -1)
var aura_root: Node3D; var settle_fx_root: Node3D; var weather_fx_root: Node3D
var action_history: Array[String] = []
var action_history_tones: Array[String] = []
var history_scroll := 0
var center_notices := []
var top_terrain_counts := [0, 0, 0, 0, 0]
var top_terrain_count_tick := -1
var placement_highlights := []
var placement_highlight_root: Node3D
var ranking_order: Array[int] = []
var ranking_y: Dictionary = {}
var ranking_values: Dictionary = {}
var card_preview_viewport: SubViewport; var card_preview_root: Node3D; var card_preview_camera: Camera3D
var card_preview_signature := ""
var ui_glass_root: Control; var ui_glass_panels := []
var ui_preview_mode := "card"; var ui_preview_index := 0

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
	camera.near = 0.1; camera.far = 1000
	add_child(camera)

	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 0.70; sun.light_color = Color("#ffe8c4")
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.shadow_enabled = true; add_child(sun)

	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 150, 0)
	fill.light_energy = 0.17; fill.light_color = Color("#87c5c7")
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)

	var rim = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -120, 0)
	rim.light_energy = 0.07; rim.light_color = Color("#f5b766")
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(rim)

	var env = WorldEnvironment.new()
	var e = Environment.new()
	var sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#89cbed")
	sky_material.sky_horizon_color = Color("#ccecff")
	sky_material.sky_curve = 0.38
	sky_material.ground_horizon_color = Color("#b9e4f8")
	sky_material.ground_bottom_color = Color("#f6fbff")
	sky_material.ground_curve = 1.65
	var sky = Sky.new(); sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_QUALITY; sky.radiance_size = Sky.RADIANCE_SIZE_128
	e.background_mode = Environment.BG_SKY; e.sky = sky
	e.background_color = Color("#f8fcff")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#a7d6c4")
	e.ambient_light_energy = 0.52
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true; e.glow_intensity = 0.10; e.glow_bloom = 0.015
	env.environment = e; add_child(env)
	_setup_sky_world()

	grid_root = Node3D.new(); add_child(grid_root)
	edge_root = Node3D.new(); add_child(edge_root)
	plant_root = Node3D.new(); add_child(plant_root)
	decor_root = Node3D.new(); add_child(decor_root)
	piece_preview_root = Node3D.new(); add_child(piece_preview_root)
	tile_select_root = Node3D.new(); tile_select_root.name = "TileSelection"; add_child(tile_select_root)
	aura_root = Node3D.new(); aura_root.name = "BuildingAuras"; add_child(aura_root)
	settle_fx_root = Node3D.new(); settle_fx_root.name = "SettlementEffects"; add_child(settle_fx_root)
	weather_fx_root = Node3D.new(); weather_fx_root.name = "WeatherEffects"; add_child(weather_fx_root)
	placement_highlight_root = Node3D.new(); placement_highlight_root.name = "PlacementHighlights"; add_child(placement_highlight_root)

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
	var canvas = CanvasLayer.new(); canvas.layer = 10
	add_child(canvas)
	var back_buffer = BackBufferCopy.new(); back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	canvas.add_child(back_buffer)
	ui_glass_root = Control.new(); ui_glass_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_glass_root.mouse_filter = Control.MOUSE_FILTER_IGNORE; canvas.add_child(ui_glass_root)
	for panel_index in 4:
		var panel = ColorRect.new(); panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glass_material = ShaderMaterial.new(); glass_material.shader = UI_FROSTED_GLASS_SHADER
		glass_material.set_shader_parameter("tint_color", Color(0.96, 0.96, 0.93, 0.42 if panel_index == 0 else (0.44 if panel_index == 3 else 0.40)))
		glass_material.set_shader_parameter("blur_lod", 3.2 if panel_index < 3 else 3.4)
		glass_material.set_shader_parameter("blur_radius", 10.0 if panel_index == 0 else 12.0)
		panel.material = glass_material; ui_glass_root.add_child(panel); ui_glass_panels.append(panel)
	ui_ctrl = Control.new(); ui_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE; canvas.add_child(ui_ctrl)
	ui_ctrl.connect("draw", _draw_ui)
	_setup_card_preview_viewport()

func _setup_card_preview_viewport():
	card_preview_viewport = SubViewport.new()
	card_preview_viewport.size = Vector2i(640, 400)
	card_preview_viewport.transparent_bg = true
	card_preview_viewport.own_world_3d = true
	card_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(card_preview_viewport)
	card_preview_root = Node3D.new(); card_preview_viewport.add_child(card_preview_root)
	card_preview_camera = Camera3D.new()
	card_preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	card_preview_camera.size = 3.4; card_preview_camera.position = Vector3(3.2, 3.8, 4.2)
	card_preview_viewport.add_child(card_preview_camera)
	card_preview_camera.look_at_from_position(card_preview_camera.position, Vector3(0, 0.18, 0))
	var key_light = DirectionalLight3D.new(); key_light.rotation_degrees = Vector3(-50, -30, 0); key_light.light_energy = 1.05
	card_preview_viewport.add_child(key_light)
	var fill_light = DirectionalLight3D.new(); fill_light.rotation_degrees = Vector3(30, 150, 0); fill_light.light_energy = 0.45
	card_preview_viewport.add_child(fill_light)
	# 环境光 + 天空
	var env = Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c8e0d4")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env = WorldEnvironment.new(); world_env.environment = env
	card_preview_viewport.add_child(world_env)

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
	var pearl_mat = _sky_prop_material(Color(0.99, 1.00, 1.00, 0.72))
	var shade_mat = _sky_prop_material(Color(0.72, 0.86, 0.95, 0.34))
	var cloud_positions = [
		Vector3(-15, 3.0, -9), Vector3(-13, 4.2, 8), Vector3(-4, 5.8, -15),
		Vector3(10, 3.8, 12), Vector3(15, 5.2, -4), Vector3(17, 2.6, 7),
	]
	for cloud_index in cloud_positions.size():
		var cloud = Node3D.new(); cloud.position = cloud_positions[cloud_index]
		cloud.set_meta("speed", randf_range(0.055, 0.10)); cloud.set_meta("base_z", cloud.position.z)
		cloud.set_meta("base_y", cloud.position.y); cloud.set_meta("bob", randf_range(0.07, 0.14))
		cloud.set_meta("phase", randf() * TAU); sky_root.add_child(cloud); drifting_clouds.append(cloud)
		cloud.scale = Vector3.ONE * randf_range(0.72, 1.08)
		for puff_index in 4:
			var puff = MeshInstance3D.new(); var puff_mesh = SphereMesh.new()
			puff_mesh.radius = 0.38 + float(puff_index % 2) * 0.08
			puff_mesh.height = puff_mesh.radius * 1.25; puff_mesh.radial_segments = 8; puff_mesh.rings = 4
			puff.mesh = puff_mesh; puff.material_override = pearl_mat if puff_index < 3 else shade_mat
			puff.position = Vector3((puff_index - 1.5) * 0.35, 0.08 + (puff_index % 2) * 0.13, (puff_index % 3 - 1) * 0.12)
			puff.scale = Vector3(1.25, 0.68, 0.92); cloud.add_child(puff)
		var cloud_base = MeshInstance3D.new(); var base_mesh = BoxMesh.new()
		base_mesh.size = Vector3(1.48, 0.13, 0.52); cloud_base.mesh = base_mesh
		cloud_base.material_override = shade_mat; cloud_base.position.y = -0.10; cloud.add_child(cloud_base)

func _spawn_mist_banks():
	var mist_material = _sky_prop_material(Color(0.94, 0.98, 1.00, 0.16))
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
	var mote_material = _soft_material(Color(0.82, 0.94, 1.00, 0.48), 0.65)
	for i in 20:
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
	grid_origin = Vector2i.ZERO
	falling_leaves.clear(); animated_grass_patches.clear()
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
	var logical = pos - grid_origin
	return Vector3(logical.x * TILE_SPACING - off, 0, logical.y * TILE_SPACING - off)

func _logical_cell(pos: Vector2i) -> Vector2i:
	return pos - grid_origin

func _grid_width() -> int:
	return grid.size()

func _grid_height() -> int:
	return grid[0].size() if not grid.is_empty() else 0

func _new_column(height: int) -> Array:
	var column := []
	for y in height: column.append(-1)
	return column

func _new_int_column(height: int, value: int = 0) -> Array:
	var column := []
	for y in height: column.append(value)
	return column

func _new_flower_column(height: int) -> Array:
	var column := []
	for y in height: column.append([0, 0, 0, 0])
	return column

func _new_node_column(height: int) -> Array:
	var column := []
	for y in height: column.append(null)
	return column

func _expand_board_ring():
	var old_width = _grid_width(); var old_height = _grid_height()
	for x in old_width:
		grid[x].push_front(-1); grid[x].append(-1)
		roads[x].push_front(0); roads[x].append(0)
		plants[x].push_front(0); plants[x].append(0)
		plant_age[x].push_front(0); plant_age[x].append(0)
		flowers[x].push_front([0, 0, 0, 0]); flowers[x].append([0, 0, 0, 0])
		tile_nodes[x].push_front(null); tile_nodes[x].append(null)
		plant_nodes[x].push_front(null); plant_nodes[x].append(null)
		decor_nodes[x].push_front(null); decor_nodes[x].append(null)
	var new_height = old_height + 2
	grid.push_front(_new_int_column(new_height, -1)); grid.append(_new_int_column(new_height, -1))
	roads.push_front(_new_int_column(new_height)); roads.append(_new_int_column(new_height))
	plants.push_front(_new_int_column(new_height)); plants.append(_new_int_column(new_height))
	plant_age.push_front(_new_int_column(new_height)); plant_age.append(_new_int_column(new_height))
	flowers.push_front(_new_flower_column(new_height)); flowers.append(_new_flower_column(new_height))
	tile_nodes.push_front(_new_node_column(new_height)); tile_nodes.append(_new_node_column(new_height))
	plant_nodes.push_front(_new_node_column(new_height)); plant_nodes.append(_new_node_column(new_height))
	decor_nodes.push_front(_new_node_column(new_height)); decor_nodes.append(_new_node_column(new_height))
	grid_origin += Vector2i.ONE
	for child in edge_root.get_children(): child.free()
	closed_road_ids.clear(); closed_road_cells.clear()
	for x in _grid_width():
		for y in _grid_height():
			var pos = Vector2i(x, y)
			_update_edge_bridges(pos)
			_update_road_bridges(pos)
	_refresh_road_effects()

func _ensure_growth_margin(cells: Array):
	_rebuild_mountain_envelope()

func _non_developable_cells() -> Array:
	var result := []
	for x in _grid_width():
		for y in _grid_height():
			if grid[x][y] >= 0 and not _is_developable(grid[x][y]): result.append(Vector2i(x, y))
	return result

func _rebuild_mountain_envelope():
	var developed = _non_developable_cells()
	if developed.is_empty(): return
	var needs_space := true
	while needs_space:
		needs_space = false
		for cell in developed:
			if cell.x < BOARD_GROW_MARGIN or cell.y < BOARD_GROW_MARGIN or cell.x >= _grid_width() - BOARD_GROW_MARGIN or cell.y >= _grid_height() - BOARD_GROW_MARGIN:
				_expand_board_ring(); needs_space = true; developed = _non_developable_cells(); break
	for center in developed:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var pos = center + Vector2i(dx, dy)
				if _in_bounds(pos) and grid[pos.x][pos.y] == -1:
					_force_tile(pos, T_MOUNTAIN, true, 0)

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
	for x in _grid_width():
		for y in _grid_height():
			if grid[x][y] != -1: return true
	return false

func _can_place_piece_data(anchor: Vector2i, piece: Dictionary, rotation: int) -> bool:
	var piece_cells = _piece_cells(piece, rotation)
	var touches_board = not _has_any()
	for local_cell in piece_cells:
		var pos = anchor + local_cell
		if not _in_bounds(pos): return false
		if grid[pos.x][pos.y] != -1: return false
		for dir in DIRS:
			var neighbor = pos + dir
			if _in_bounds(neighbor):
				if grid[neighbor.x][neighbor.y] != -1: touches_board = true
	return touches_board

func _market_has_move() -> bool:
	for piece in piece_market:
		for rotation in 4:
			for x in _grid_width():
				for y in _grid_height():
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
		_refresh_neighbor_trims(anchor + local_cell)
	_refresh_road_effects()
	piece_preview_root.visible = false
	return true

func _force_tile(pos: Vector2i, terr: int, animate: bool, road_mask: int = 0):
	grid[pos.x][pos.y] = terr; roads[pos.x][pos.y] = road_mask
	_spawn_tile(pos, terr, animate, road_mask)
	_update_edge_bridges(pos)
	_update_road_bridges(pos)
	_refresh_neighbor_trims(pos)

func _set_tile_type(pos: Vector2i, terr: int, animate: bool = true, road_mask: int = -1):
	if not _in_bounds(pos): return
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
	_refresh_neighbor_trims(pos)

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
			if _in_bounds(p):
				if grid[p.x][p.y] == terr: return true
	return false

func _refresh_building_auras():
	if not is_instance_valid(aura_root): return
	for child in aura_root.get_children(): child.free()
	var boosted := {}
	for x in _grid_width():
		for y in _grid_height():
			if grid[x][y] != T_BUILDING: continue
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0: continue
					var target = Vector2i(x + dx, y + dy)
					if _in_bounds(target) and _is_plant_terrain(grid[target.x][target.y]): boosted[target] = true
	for pos in boosted:
		_spawn_aura_particles(pos)
		for side in DIRS.size():
			var neighbor: Vector2i = pos + DIRS[side]
			if boosted.has(neighbor): continue
			var border = MeshInstance3D.new(); var mesh = BoxMesh.new()
			var horizontal = side == 0 or side == 2
			mesh.size = Vector3(TILE_SPACING if horizontal else 0.045, 0.32, 0.045 if horizontal else TILE_SPACING)
			border.mesh = mesh
			var material = StandardMaterial3D.new()
			material.albedo_color = Color(0.96, 0.76, 0.25, 0.24)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.emission_enabled = true; material.emission = Color("#e9bd45")
			material.emission_energy_multiplier = 0.45
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			border.material_override = material
			border.position = _world(pos) + Vector3(DIRS[side].x * TILE_SPACING * 0.5, 0.40, DIRS[side].y * TILE_SPACING * 0.5)
			aura_root.add_child(border)
			var tween = create_tween().set_loops()
			tween.tween_property(material, "emission_energy_multiplier", 0.85, 1.2).set_trans(Tween.TRANS_SINE)
			tween.tween_property(material, "emission_energy_multiplier", 0.25, 1.2).set_trans(Tween.TRANS_SINE)

func _spawn_aura_particles(pos: Vector2i):
	for particle_index in 3:
		var mote = MeshInstance3D.new(); var mesh = SphereMesh.new()
		mesh.radius = 0.014; mesh.height = 0.028; mesh.radial_segments = 6; mesh.rings = 3
		mote.mesh = mesh
		var material = _soft_material(Color(1.0, 0.82, 0.32, 0.68), 0.9)
		mote.material_override = material
		mote.position = _world(pos) + Vector3(randf_range(-0.36, 0.36), 0.30 + particle_index * 0.08, randf_range(-0.36, 0.36))
		aura_root.add_child(mote)
		var start_y = mote.position.y; var tween = create_tween().set_loops()
		tween.tween_property(mote, "position:y", start_y + 0.38, 1.5 + particle_index * 0.25).set_trans(Tween.TRANS_SINE)
		tween.tween_property(mote, "position:y", start_y, 1.1).set_trans(Tween.TRANS_SINE)

func _trim_flowers_to_capacity(pos: Vector2i):
	var cap = _tile_capacity(pos)
	var total = _flower_total(pos)
	if total <= cap: return
	if cap <= 0:
		flowers[pos.x][pos.y] = [0, 0, 0, 0]
		_refresh_plant_visual(pos)
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
	if not _in_bounds(pos): return
	_rebuild_bridges_for(pos)
	for direction in DIRS: _rebuild_bridges_for(pos + direction)

func _rebuild_bridges_for(pos: Vector2i):
	if not _in_bounds(pos): return
	for child in edge_root.get_children():
		if child.has_meta("bridge_owner") and child.get_meta("bridge_owner") == str(pos): child.free()
	var terr: int = grid[pos.x][pos.y]
	if terr < 0 or _is_developable(terr): return
	for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
		var neighbor: Vector2i = pos + direction
		if _in_bounds(neighbor) and grid[neighbor.x][neighbor.y] == terr:
			_spawn_bridge(pos, neighbor, terr)

func _spawn_bridge(owner_pos: Vector2i, neighbor_pos: Vector2i, terr: int):
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new(); var horizontal = owner_pos.y == neighbor_pos.y
	bm.size = Vector3(0.28 if horizontal else 1.03, 0.035, 1.03 if horizontal else 0.28)
	mi.mesh = bm
	mi.material_override = edge_materials[terr]
	mi.position = (_world(owner_pos) + _world(neighbor_pos)) * 0.5 + Vector3(0, 0.1425, 0)
	mi.set_meta("bridge_owner", str(owner_pos))
	edge_root.add_child(mi)

func _road_pair_key(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var swap = a; a = b; b = swap
	return "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]

func _update_road_bridges(pos: Vector2i):
	if not _in_bounds(pos): return
	for owner in [pos, pos + Vector2i.LEFT, pos + Vector2i.UP]: _rebuild_road_bridges_for(owner)

func _rebuild_road_bridges_for(owner: Vector2i):
	if not _in_bounds(owner): return
	for child in edge_root.get_children():
		if child.has_meta("road_bridge_owner") and child.get_meta("road_bridge_owner") == str(owner): child.free()
	if grid[owner.x][owner.y] < 0 or grid[owner.x][owner.y] == T_BUILDING: return
	for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
		var neighbor: Vector2i = owner + direction
		if not _in_bounds(neighbor) or grid[neighbor.x][neighbor.y] < 0 or grid[neighbor.x][neighbor.y] == T_BUILDING: continue
		if _roads_connect(owner, neighbor): _spawn_road_bridge_pair(owner, neighbor)

func _spawn_road_bridge_pair(owner: Vector2i, neighbor: Vector2i):
	var horizontal := owner.y == neighbor.y
	var center := (_world(owner) + _world(neighbor)) * 0.5
	var layers = [
		[Vector3(0.24, 0.026, 0.24) if horizontal else Vector3(0.24, 0.026, 0.24), 0.165, Color("#5a4430"), 0.95, "under"],
		[Vector3(0.24, 0.022, 0.20) if horizontal else Vector3(0.20, 0.022, 0.24), 0.178, Color("#d8bd80"), 0.82, "surface"],
	]
	for layer_data in layers:
		var bridge = MeshInstance3D.new(); var mesh = BoxMesh.new(); mesh.size = layer_data[0]
		bridge.mesh = mesh; bridge.material_override = _road_material(layer_data[2], layer_data[3])
		bridge.position = center + Vector3(0, layer_data[1], 0)
		bridge.set_meta("road_key", _road_pair_key(owner, neighbor)); bridge.set_meta("road_bridge_owner", str(owner))
		bridge.set_meta("road_bridge_layer", layer_data[4]); edge_root.add_child(bridge)

func _refresh_road_effects():
	last_road_event = ""
	for child in edge_root.get_children():
		if child.has_meta("road_fx"): child.free()
	closed_road_cells.clear()
	var current_closed := {}

	var visited := {}
	for x in _grid_width():
		for y in _grid_height():
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
				if not closed_road_ids.has(component_id):
					_grant_closed_road_seed_rewards(component)
					last_road_event = "道路闭合！沿线玩家获得1级播种卡"
	closed_road_ids = current_closed

func _grant_seed_card(player_id: int, level: int = 1, reason: String = ""):
	if player_id < 0 or player_id >= player_count: return
	var card := _make_seed_card(level)
	hands[player_id].append(card)
	seeds[player_id] += 1
	if player_id == current_player:
		current_hand = hands[current_player]
	if reason != "":
		var readable_reason: String = {"道路闭合": "道路封闭", "建筑开发": "建造建筑", "开发完成": "开发地块"}.get(reason, reason)
		_record_action("奖励 · 因%s获得%d级播种卡" % [readable_reason, level], "reward", player_id)
		_show_center_notice("%s因%s获得一张播种卡" % [PLAYER_NAMES[player_id], readable_reason], "reward")

func _grant_closed_road_seed_rewards(component: Array):
	var rewarded := {}
	for cell in component:
		if not _in_bounds(cell): continue
		for player_id in player_count:
			if rewarded.has(player_id): continue
			if flowers[cell.x][cell.y][player_id] > 0:
				rewarded[player_id] = true
				_grant_seed_card(player_id, 1, "道路闭合")

func _road_component(start: Vector2i, visited: Dictionary) -> Array:
	var component := []
	var pending := [start]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		if visited.has(cell): continue
		visited[cell] = true; component.append(cell)
		for dir in DIRS:
			var neighbor = cell + dir
			if _in_bounds(neighbor) and not visited.has(neighbor) and _roads_connect(cell, neighbor):
				pending.append(neighbor)
	return component

func _road_component_is_closed(component: Array) -> bool:
	for cell in component:
		var mask: int = roads[cell.x][cell.y]
		for dir_index in DIRS.size():
			if (mask & (1 << dir_index)) == 0: continue
			var neighbor: Vector2i = cell + DIRS[dir_index]
			if not _in_bounds(neighbor): return false
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
	var mesh = CylinderMesh.new(); mesh.top_radius = 0.23; mesh.bottom_radius = 0.23
	mesh.height = 0.008; mesh.radial_segments = 20
	ring.mesh = mesh
	var material = _road_material(Color("#f7e6a5"), 0.35)
	material.albedo_color.a = 0.18; material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true; material.emission = Color("#ffd66b"); material.emission_energy_multiplier = 0.4
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = material; ring.position = _world(pos) + Vector3(0, 0.305, 0)
	ring.set_meta("road_fx", true); edge_root.add_child(ring)
	var tw = create_tween().set_loops()
	tw.tween_property(material, "emission_energy_multiplier", 0.8, 1.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(material, "emission_energy_multiplier", 0.25, 1.5).set_trans(Tween.TRANS_SINE)

# ================================================================
#  STARTING BOARD
# ================================================================
func _generate_start_tiles():
	var center_cells := []
	for x in _grid_width():
		for y in _grid_height():
			var pos = Vector2i(x, y)
			if x >= 2 and x <= 5 and y >= 2 and y <= 5:
				_force_tile(pos, _draw_terrain(), false, _random_road_mask())
				center_cells.append(pos)
			else:
				_force_tile(pos, T_MOUNTAIN, false, 0)
	_generate_development_roads(center_cells)
	_refresh_road_effects()
	_refresh_building_auras()

func _random_road_mask() -> int:
	# Roads are created only by road cards, which always write both ends.
	# This prevents isolated road stubs on newly generated terrain.
	return 0

# ================================================================
#  TILE MESH — rich 3D per terrain
# ================================================================
func _spawn_tile(pos: Vector2i, terr: int, animate: bool, road_mask: int = 0):
	var root = Node3D.new(); root.position = _world(pos)
	grid_root.add_child(root); tile_nodes[pos.x][pos.y] = root
	if terr != T_GAP:
		_spawn_island_base(root, terr)
		_spawn_merge_fills(root, terr, pos)

	# --- Top surface with terrain-specific shape ---
	match terr:
		0: _tile_grass_surface(root, road_mask)
		1: _tile_water_surface(root, road_mask)
		2: _tile_forest_surface(root, road_mask)
		3: _tile_desert_surface(root, road_mask)
		4:
			var building_data: Dictionary = special_buildings.get(_logical_cell(pos), {})
			if building_data.get("kind", "") == "hongshan_tech": _tile_hongshan_tech_surface(root, building_data)
			else: _tile_pavilion_surface(root, road_mask)
		5: _tile_mountain_surface(root)
		6: _tile_gap_surface(root)

	if terr != T_GAP:
		_spawn_edge_trim(root, terr, pos)

	# --- Decorations ---
	_spawn_decor(terr, root, road_mask)
	if road_mask != 0 and not _is_developable(terr) and terr != T_BUILDING: _spawn_road(root, road_mask)

	if animate:
		root.scale = Vector3(0.01, 0.01, 0.01)
		var tw = create_tween()
		tw.tween_property(root, "scale", Vector3(1, 1, 1), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

func _spawn_island_base(root: Node3D, terr: int):
	# The continuous cap covers both seams and four-cell junctions.
	# 水域不加cap，避免遮挡水面和涟漪装饰
	if terr != T_WATER:
		_building_box(root, Vector3(1.03, 0.06, 1.03), Vector3(0, 0.12, 0), edge_materials[terr])
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

func _spawn_edge_trim(root: Node3D, terr: int, pos: Vector2i):
	var trim_material = StandardMaterial3D.new()
	trim_material.albedo_color = TERRAIN_TOP[terr].lightened(0.08)
	trim_material.roughness = 0.76
	for side in 4:
		var neighbor = pos + DIRS[side]
		if _in_bounds(neighbor) and grid[neighbor.x][neighbor.y] == terr: continue
		var trim = MeshInstance3D.new(); var mesh = BoxMesh.new()
		var horizontal = side == 0 or side == 2
		mesh.size = Vector3(1.09 if horizontal else 0.03, 0.14, 0.03 if horizontal else 1.09)
		trim.mesh = mesh; trim.material_override = trim_material
		trim.position = Vector3(DIRS[side].x * 0.53, 0.10, DIRS[side].y * 0.53)
		trim.set_meta("edge_trim", true)
		root.add_child(trim)

func _rebuild_edge_trim(pos: Vector2i):
	if not _in_bounds(pos) or grid[pos.x][pos.y] < 0 or grid[pos.x][pos.y] == T_GAP: return
	var root = tile_nodes[pos.x][pos.y]
	if not is_instance_valid(root): return
	for child in root.get_children():
		if child.has_meta("edge_trim"): child.free()
	_spawn_edge_trim(root, grid[pos.x][pos.y], pos)

func _get_merge_directions(pos: Vector2i, terr: int) -> Array:
	var dirs := []
	for dir in DIRS:
		var n = pos + dir
		if _in_bounds(n) and grid[n.x][n.y] == terr: dirs.append(dir)
	return dirs

func _spawn_merge_fills(root: Node3D, terr: int, pos: Vector2i):
	var merge_dirs = _get_merge_directions(pos, terr)
	if merge_dirs.is_empty(): return

	# 地形表面填充（从表面边缘到缝隙中点 0.625）
	var surface_color = TERRAIN_TOP[terr]
	var surface_y = 0.13 if terr != T_WATER else 0.10
	var surface_h = 0.06 if terr != T_WATER else 0.04
	var surface_edge = 0.475 if terr != T_WATER else 0.46
	var surface_fill_w = 0.625 - surface_edge  # 0.15 or 0.165

	var surface_mat = StandardMaterial3D.new()
	surface_mat.albedo_color = surface_color; surface_mat.roughness = 0.92
	if terr == T_WATER:
		surface_mat.albedo_color = Color(0.25, 0.58, 0.78, 0.65)
		surface_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		surface_mat.emission_enabled = true; surface_mat.emission = Color(0.15, 0.35, 0.6)
		surface_mat.emission_energy_multiplier = 0.2

	for dir in merge_dirs:
		var is_h = dir.x != 0
		# 地形表面填充
		var sf = MeshInstance3D.new(); var sfm = BoxMesh.new()
		sfm.size = Vector3(surface_fill_w if is_h else 0.95, surface_h, surface_fill_w if not is_h else 0.95)
		sf.mesh = sfm; sf.material_override = surface_mat
		sf.position = Vector3(dir.x * (surface_edge + surface_fill_w * 0.5), surface_y, dir.y * (surface_edge + surface_fill_w * 0.5))
		sf.set_meta("merge_fill", true); root.add_child(sf)

		# 边框区域填充（从地块边缘到缝隙中点，覆盖原边框位置）
		var trim_mat = StandardMaterial3D.new()
		trim_mat.albedo_color = TERRAIN_TOP[terr].lightened(0.08); trim_mat.roughness = 0.76
		var trim_fill_w = 0.625 - 0.53  # 0.095
		var trim_fill = MeshInstance3D.new(); var tfm2 = BoxMesh.new()
		if is_h:
			tfm2.size = Vector3(trim_fill_w, 0.14, 1.09)
		else:
			tfm2.size = Vector3(1.09, 0.14, trim_fill_w)
		trim_fill.mesh = tfm2; trim_fill.material_override = trim_mat
		trim_fill.position = Vector3(dir.x * (0.53 + trim_fill_w * 0.5), 0.10, dir.y * (0.53 + trim_fill_w * 0.5))
		trim_fill.set_meta("merge_fill", true); root.add_child(trim_fill)

		# Top层填充（非可开发地块）
		if not _is_developable(terr):
			var top_fill_w = 0.625 - 0.53  # 0.095
			var tf = MeshInstance3D.new(); var tfm = BoxMesh.new()
			tfm.size = Vector3(top_fill_w if is_h else 1.06, 0.13, top_fill_w if not is_h else 1.06)
			tf.mesh = tfm
			var top_mat = StandardMaterial3D.new(); top_mat.albedo_color = TERRAIN_MID[terr]; top_mat.roughness = 0.94
			tf.material_override = top_mat
			tf.position = Vector3(dir.x * (0.53 + top_fill_w * 0.5), 0.025, dir.y * (0.53 + top_fill_w * 0.5))
			tf.set_meta("merge_fill", true); root.add_child(tf)

		# Cap填充（非水域、非可开发地块）
		if terr != T_WATER and not _is_developable(terr):
			var cap_fill_w = 0.625 - 0.515  # 0.11
			var cf = MeshInstance3D.new(); var cfm = BoxMesh.new()
			cfm.size = Vector3(cap_fill_w if is_h else 1.03, 0.06, cap_fill_w if not is_h else 1.03)
			cf.mesh = cfm; cf.material_override = edge_materials[terr]
			cf.position = Vector3(dir.x * (0.515 + cap_fill_w * 0.5), 0.12, dir.y * (0.515 + cap_fill_w * 0.5))
			cf.set_meta("merge_fill", true); root.add_child(cf)

func _rebuild_merge_fills(pos: Vector2i):
	if not _in_bounds(pos) or grid[pos.x][pos.y] < 0 or grid[pos.x][pos.y] == T_GAP: return
	var root = tile_nodes[pos.x][pos.y]
	if not is_instance_valid(root): return
	for child in root.get_children():
		if child.has_meta("merge_fill"): child.free()
	_spawn_merge_fills(root, grid[pos.x][pos.y], pos)

func _refresh_neighbor_trims(pos: Vector2i):
	_rebuild_edge_trim(pos)
	_rebuild_merge_fills(pos)
	for direction in DIRS:
		_rebuild_edge_trim(pos + direction)
		_rebuild_merge_fills(pos + direction)

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
	var under_material = _road_material(Color("#5a4430"), 0.95)
	var road_material = _road_material(Color("#d8bd80"), 0.82)
	road_material.emission_enabled = true; road_material.emission = Color("#a89060")
	road_material.emission_energy_multiplier = 0.08
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
		under.position = offset + Vector3(0, 0.165, 0); root.add_child(under)
		var road = MeshInstance3D.new(); var road_mesh = BoxMesh.new()
		road_mesh.size = Vector3(length if is_horizontal else 0.20, 0.022, 0.20 if is_horizontal else length)
		road.mesh = road_mesh; road.material_override = road_material
		road.position = offset + Vector3(0, 0.178, 0); root.add_child(road)

	var hub_under = MeshInstance3D.new(); var hub_under_mesh = CylinderMesh.new()
	hub_under_mesh.top_radius = 0.16; hub_under_mesh.bottom_radius = 0.16; hub_under_mesh.height = 0.026
	hub_under.mesh = hub_under_mesh; hub_under.material_override = under_material
	hub_under.position.y = 0.165; root.add_child(hub_under)
	var hub = MeshInstance3D.new(); var hub_mesh = CylinderMesh.new()
	hub_mesh.top_radius = 0.115; hub_mesh.bottom_radius = 0.115; hub_mesh.height = 0.03
	hub.mesh = hub_mesh; hub.material_override = road_material
	hub.position.y = 0.178; root.add_child(hub)

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
		patch.set_meta("green_color", patch_material.albedo_color); patch.set_meta("phase", randf() * TAU)
		animated_grass_patches.append(patch)

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

	var mmat2 = StandardMaterial3D.new()
	mmat2.albedo_color = TERRAIN_TOP[2]
	if road_mask == 0:
		var moss = MeshInstance3D.new(); var moss_mesh = CylinderMesh.new()
		moss_mesh.top_radius = 0.31; moss_mesh.bottom_radius = 0.34; moss_mesh.height = 0.025; moss_mesh.radial_segments = 14
		moss.mesh = moss_mesh; moss.material_override = mmat2; moss.position.y = 0.19
		root.add_child(moss)
	else:
		for patch_index in 3:
			var moss_patch = MeshInstance3D.new(); var patch_mesh = CylinderMesh.new()
			patch_mesh.top_radius = randf_range(0.08, 0.13); patch_mesh.bottom_radius = patch_mesh.top_radius * 1.08
			patch_mesh.height = 0.012; patch_mesh.radial_segments = 9; moss_patch.mesh = patch_mesh
			moss_patch.material_override = mmat2
			var patch_pos = _feature_position(road_mask, 0.37)
			moss_patch.position = Vector3(patch_pos.x, 0.163, patch_pos.y)
			moss_patch.scale.z = randf_range(0.65, 1.15); root.add_child(moss_patch)

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
	for i in 5:
		var rock = MeshInstance3D.new(); var rm = CylinderMesh.new()
		rm.top_radius = randf_range(0.015, 0.055); rm.bottom_radius = randf_range(0.15, 0.25)
		rm.height = randf_range(0.30, 0.58); rm.radial_segments = randi_range(5, 7)
		rock.mesh = rm; rock.material_override = mat
		rock.position = Vector3(randf_range(-0.27, 0.27), 0.19 + rm.height * 0.5, randf_range(-0.27, 0.27))
		rock.scale = Vector3(randf_range(0.85, 1.25), 1.0, randf_range(0.85, 1.25))
		rock.rotation_degrees.y = randf_range(0, 360); root.add_child(rock)
		if i < 2:
			var snow = MeshInstance3D.new(); var snow_mesh = CylinderMesh.new()
			snow_mesh.top_radius = 0.006; snow_mesh.bottom_radius = rm.top_radius + 0.055; snow_mesh.height = 0.07; snow_mesh.radial_segments = rm.radial_segments
			snow.mesh = snow_mesh; snow.material_override = _soft_material(Color("#d8e0d8"))
			snow.position = rock.position + Vector3(0, rm.height * 0.48, 0); root.add_child(snow)

func _tile_gap_surface(root: Node3D):
	var gap_material = StandardMaterial3D.new()
	gap_material.albedo_color = Color(0.95, 0.98, 1.0, 0.22)
	gap_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gap_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var layers = [
		[Vector3(1.06, 0.025, 1.06), 0.145],
		[Vector3(0.88, 0.025, 0.88), 0.105],
		[Vector3(0.56, 0.030, 0.56), 0.060],
	]
	for layer_data in layers:
		var layer = MeshInstance3D.new(); var layer_mesh = BoxMesh.new()
		layer_mesh.size = layer_data[0]; layer.mesh = layer_mesh
		layer.material_override = gap_material; layer.position.y = layer_data[1]
		root.add_child(layer)
	var ring_material = StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.95, 0.98, 1.0, 0.38)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in 4:
		var edge = MeshInstance3D.new(); var mesh = BoxMesh.new()
		var horizontal = side == 0 or side == 2
		mesh.size = Vector3(0.88 if horizontal else 0.025, 0.018, 0.025 if horizontal else 0.88)
		edge.mesh = mesh; edge.material_override = ring_material
		edge.position = Vector3(DIRS[side].x * 0.44, 0.16, DIRS[side].y * 0.44)
		root.add_child(edge)

func _clear_tile_selection():
	selected_tile = Vector2i(-1, -1)
	if ui_preview_mode == "tile":
		ui_preview_mode = "card"; ui_preview_index = clampi(selected_card, 0, maxi(current_hand.size() - 1, 0))
	if not is_instance_valid(tile_select_root): return
	for child in tile_select_root.get_children(): child.free()

func _try_select_tile(pos: Vector2i):
	if not _in_bounds(pos) or grid[pos.x][pos.y] < 0 or pos == selected_tile:
		_clear_tile_selection(); return
	_clear_tile_selection()
	selected_tile = pos
	ui_preview_mode = "tile"; ui_preview_index = 0
	var highlight = MeshInstance3D.new(); var mesh = BoxMesh.new()
	mesh.size = Vector3(1.07, 0.018, 1.07); highlight.mesh = mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.26)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.no_depth_test = true
	highlight.material_override = material
	highlight.position = _world(pos) + Vector3(0, 0.31, 0)
	tile_select_root.add_child(highlight)
	var tween = create_tween().set_loops()
	tween.tween_property(material, "albedo_color:a", 0.40, 1.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(material, "albedo_color:a", 0.18, 1.2).set_trans(Tween.TRANS_SINE)
	ui_ctrl.queue_redraw()

func _tile_info_text(pos: Vector2i) -> String:
	var terr: int = grid[pos.x][pos.y]
	if _is_plant_terrain(terr):
		var growth_rate: float = TERRAIN_GROWTH[terr]
		if _has_extreme_weather(): growth_rate *= 0.5
		if rainbow_turns > 0: growth_rate *= 2.0
		var spread_rate := 1.0
		if rainbow_turns > 0: spread_rate = 2.0
		var lines = [
			TERRAIN_NAMES[terr],
			"生长率 %.2f   容积 %d/%d" % [growth_rate, _flower_total(pos), _tile_capacity(pos)],
			"扩散概率 x%.1f" % spread_rate
		]
		var water_count := 0; var building_count := 0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0: continue
				var neighbor = pos + Vector2i(dx, dy)
				if not _in_bounds(neighbor): continue
				if grid[neighbor.x][neighbor.y] == T_WATER: water_count += 1
				elif grid[neighbor.x][neighbor.y] == T_BUILDING: building_count += 1
		if water_count > 0: lines.append("水域增益 x%d" % water_count)
		if building_count > 0: lines.append("建筑增益 x%d" % building_count)
		if terr == T_DESERT: lines.append("荒漠容量低：最多10朵")
		lines.append("道路：%s" % ("已连通" if roads[pos.x][pos.y] != 0 else "无"))
		return "\n".join(lines)
	if terr == T_WATER: return "水域\n相邻植物升级概率翻倍\n影响范围 3x3"
	if terr == T_BUILDING: return "建筑\n相邻植物容积翻倍\n影响范围 3x3"
	if terr == T_MOUNTAIN: return "山体\n可使用开发卡"
	return "缺口\n可使用建筑开发卡"

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

# ---- Level-2 landmark: Hongshan Technology Building across two tiles ----
func _tile_hongshan_tech_surface(root: Node3D, data: Dictionary):
	var direction_index: int = int(data.get("direction", 1)); var part: int = int(data.get("part", 0))
	var direction: Vector2i = DIRS[direction_index]
	var toward_joint = Vector3(direction.x, 0, direction.y) * (1.0 if part == 0 else -1.0)
	var along_x = direction.x != 0
	var lateral = Vector3(-direction.y, 0, direction.x)
	var white = _soft_material(Color("#f5f6f3")); var shadow = _soft_material(Color("#b8c0c0"))
	var glass = _soft_material(Color("#76b8c8"), 0.10); glass.metallic = 0.32; glass.roughness = 0.14
	var dark_glass = _soft_material(Color("#397b91"), 0.16); dark_glass.metallic = 0.38; dark_glass.roughness = 0.12
	var green = _soft_material(Color("#477b53"))

	# One continuous civic plinth and glazed link visually bind both occupied tiles.
	_building_box(root, Vector3(1.02, 0.055, 1.02), Vector3(0, 0.15, 0), white)
	_building_box(root, Vector3(1.16 if along_x else 0.78, 0.16, 0.78 if along_x else 1.16), toward_joint * 0.14 + Vector3(0, 0.25, 0), shadow)
	_building_box(root, Vector3(1.18 if along_x else 0.25, 0.18, 0.25 if along_x else 1.18), toward_joint * 0.47 + Vector3(0, 0.36, 0), glass)

	# Stepped white twin towers frame a recessed curtain-wall core.
	var tower_offset = toward_joint * 0.08 + lateral * (-0.07 if part == 0 else 0.07)
	var storeys = 7 + part
	for floor_index in storeys:
		var setback = float(floor_index) * 0.018
		var width = 0.70 - setback; var depth = 0.54 - setback * 0.55
		var floor_size = Vector3(width if along_x else depth, 0.115, depth if along_x else width)
		var floor_center = tower_offset + Vector3(0, 0.44 + floor_index * 0.118, 0)
		_building_box(root, floor_size, floor_center, glass if floor_index % 2 == 0 else dark_glass)
		_building_box(root, Vector3(floor_size.x + 0.035, 0.018, floor_size.z + 0.035), floor_center + Vector3(0, 0.057, 0), white)
	# Strong white corner piers and a central spine give the silhouette structure.
	var tower_height = storeys * 0.118
	for side in [-1, 1]:
		for column in [-1, 0, 1]:
			var pier_shift: Vector3 = lateral * side * 0.27 + Vector3(direction.x, 0, direction.y) * column * 0.27
			_building_box(root, Vector3(0.025, tower_height, 0.025), tower_offset + pier_shift + Vector3(0, 0.44 + tower_height * 0.5 - 0.06, 0), white)
	# A shallow floating crown finishes each tower without a bulky box-shaped roof.
	var crown_size = Vector3(0.58 if along_x else 0.44, 0.055, 0.44 if along_x else 0.58)
	_building_box(root, crown_size, tower_offset + Vector3(0, 0.45 + tower_height, 0), white)
	_building_box(root, crown_size * Vector3(0.72, 0.65, 0.72), tower_offset + Vector3(0, 0.50 + tower_height, 0), glass)

	# Entrance canopy and restrained landscaping keep the ground plane readable.
	_building_box(root, Vector3(0.42 if along_x else 0.68, 0.035, 0.68 if along_x else 0.42), -toward_joint * 0.30 + Vector3(0, 0.34, 0), white)
	for planter_side in [-1, 1]:
		var planter_pos = lateral * planter_side * 0.38 - toward_joint * 0.30
		_building_box(root, Vector3(0.17, 0.06, 0.17), planter_pos + Vector3(0, 0.20, 0), shadow)
		var shrub = MeshInstance3D.new(); var shrub_mesh = SphereMesh.new(); shrub_mesh.radius = 0.09; shrub_mesh.height = 0.12; shrub_mesh.radial_segments = 7; shrub_mesh.rings = 4
		shrub.mesh = shrub_mesh; shrub.material_override = green; shrub.position = planter_pos + Vector3(0, 0.29, 0); shrub.scale = Vector3(1.2, 0.72, 1.0); root.add_child(shrub)

func _building_box(root: Node3D, size: Vector3, position: Vector3, material: Material):
	var mesh_instance = MeshInstance3D.new(); var mesh = BoxMesh.new(); mesh.size = size
	mesh_instance.mesh = mesh; mesh_instance.material_override = material; mesh_instance.position = position; root.add_child(mesh_instance)

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
	# Low shrubs replace the old decorative flower dots.
	var shrub_material = StandardMaterial3D.new(); shrub_material.albedo_color = Color("#397a3d"); shrub_material.roughness = 1.0
	for shrub_index in randi_range(2, 4):
		var shrub_pos = _feature_position(road_mask, 0.34)
		for leaf_index in 4:
			var leaf = MeshInstance3D.new(); var leaf_mesh = SphereMesh.new()
			leaf_mesh.radius = randf_range(0.045, 0.075); leaf_mesh.height = leaf_mesh.radius * 1.45; leaf_mesh.radial_segments = 7; leaf_mesh.rings = 4
			leaf.mesh = leaf_mesh; leaf.material_override = shrub_material
			var angle = TAU * float(leaf_index) / 4.0
			leaf.position = Vector3(shrub_pos.x + cos(angle) * 0.055, 0.205 + (leaf_index % 2) * 0.025, shrub_pos.y + sin(angle) * 0.055)
			leaf.scale = Vector3(1.15, 0.78, 1.0); p.add_child(leaf)
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
	# Lily pad — sits on water surface (y≈0.09)
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
		for leaf_index in 2:
			var leaf = MeshInstance3D.new(); var leaf_mesh = SphereMesh.new(); leaf_mesh.radius = 0.018; leaf_mesh.height = 0.009; leaf_mesh.radial_segments = 5; leaf_mesh.rings = 2
			leaf.mesh = leaf_mesh; leaf.material_override = _soft_material(Color("#6f9b43"))
			leaf.position = Vector3(tx + randf_range(-0.11, 0.11), 0.48 + randf_range(0.0, 0.20), tz + randf_range(-0.11, 0.11))
			leaf.set_meta("top_y", leaf.position.y); leaf.set_meta("phase", randf() * TAU); leaf.set_meta("speed", randf_range(0.10, 0.18))
			p.add_child(leaf); falling_leaves.append(leaf)

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
	if not _in_bounds(pos): return false
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
	if _flower_total(pos) <= 0:
		plants[pos.x][pos.y] = 0
		if plant_nodes[pos.x][pos.y] == null: return
	var pid = _dominant_flower_player(pos)
	if pid >= 0: plants[pos.x][pos.y] = pid + 1
	if plant_nodes[pos.x][pos.y] == null: _spawn_plant(pos, pid)
	var root: Node3D = plant_nodes[pos.x][pos.y]
	for owner in player_count:
		var existing := []
		for child in root.get_children():
			if child.has_meta("flower_owner") and int(child.get_meta("flower_owner")) == owner: existing.append(child)
		var target: int = flowers[pos.x][pos.y][owner]
		while existing.size() < target:
			var flower = _create_flower_instance(pos, owner, root)
			root.add_child(flower); existing.append(flower)
		while existing.size() > target:
			var remove_index = randi() % existing.size(); var flower: Node3D = existing.pop_at(remove_index)
			var tween = create_tween().set_parallel(true)
			tween.tween_property(flower, "scale", Vector3.ZERO, 0.28).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
			tween.tween_property(flower, "position:y", flower.position.y - 0.08, 0.28)
			tween.chain().tween_callback(flower.queue_free)

func _spawn_plant(pos: Vector2i, pid: int):
	var root = Node3D.new()
	root.position = _world(pos); root.position.y = 0.18
	plant_root.add_child(root)
	plant_nodes[pos.x][pos.y] = root

func _create_flower_instance(pos: Vector2i, owner: int, flower_root: Node3D) -> Node3D:
	var flower = Node3D.new(); flower.set_meta("flower_owner", owner)
	var road_mask: int = roads[pos.x][pos.y]; var candidate = Vector2.ZERO
	for attempt in 16:
		candidate = Vector2(randf_range(-0.39, 0.39), randf_range(-0.39, 0.39))
		if not _position_clear_of_road(candidate, road_mask): continue
		var separated := true
		for other in flower_root.get_children():
			if Vector2(other.position.x, other.position.z).distance_to(candidate) < 0.035:
				separated = false; break
		if separated: break
	flower.position = Vector3(candidate.x, randf_range(0.015, 0.055), candidate.y)
	flower.rotation.y = randf() * TAU
	var target_scale = Vector3.ONE * randf_range(0.75, 1.25)
	var stem = MeshInstance3D.new(); var stem_mesh = CylinderMesh.new()
	stem_mesh.top_radius = 0.006; stem_mesh.bottom_radius = 0.009; stem_mesh.height = randf_range(0.055, 0.10); stem_mesh.radial_segments = 5
	stem.mesh = stem_mesh; stem.material_override = _soft_material(Color("#3d713e")); stem.position.y = stem_mesh.height * 0.5; flower.add_child(stem)
	var bloom_y = stem_mesh.height
	var shade = randf_range(-0.18, 0.22)
	var flower_color = PLAYER_COLORS[owner].lightened(shade) if shade >= 0.0 else PLAYER_COLORS[owner].darkened(-shade)
	var petal_material = _soft_material(flower_color, randf_range(0.10, 0.22))
	match owner:
		0:
			for i in 4: _add_flower_petal(flower, petal_material, bloom_y, i * TAU / 4.0, Vector3(0.026, 0.012, 0.038))
		1:
			var bell = MeshInstance3D.new(); var bell_mesh = CylinderMesh.new(); bell_mesh.top_radius = 0.010; bell_mesh.bottom_radius = 0.030; bell_mesh.height = 0.045; bell_mesh.radial_segments = 6
			bell.mesh = bell_mesh; bell.material_override = petal_material; bell.position.y = bloom_y - 0.008; flower.add_child(bell)
		2:
			for i in 7: _add_flower_petal(flower, petal_material, bloom_y, i * TAU / 7.0, Vector3(0.020, 0.016, 0.026))
		3:
			for i in 6: _add_flower_petal(flower, petal_material, bloom_y, i * TAU / 6.0, Vector3(0.015, 0.025, 0.045))
	flower.scale = Vector3.ZERO
	create_tween().tween_property(flower, "scale", target_scale, 0.38).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	return flower

func _displace_flowers_for_road(pos: Vector2i):
	var flower_root: Node3D = plant_nodes[pos.x][pos.y]
	if not is_instance_valid(flower_root): return
	var road_mask: int = roads[pos.x][pos.y]
	for child in flower_root.get_children():
		if not child.has_meta("flower_owner"): continue
		var flower: Node3D = child
		var current: Vector2 = Vector2(flower.position.x, flower.position.z)
		if _position_clear_of_road(current, road_mask): continue
		var candidate: Vector2 = current
		for attempt in 24:
			candidate = Vector2(randf_range(-0.39, 0.39), randf_range(-0.39, 0.39))
			if _position_clear_of_road(candidate, road_mask): break
		create_tween().tween_property(flower, "position", Vector3(candidate.x, flower.position.y, candidate.y), 0.24).set_trans(Tween.TRANS_SINE)

func _add_flower_petal(root: Node3D, material: Material, y: float, angle: float, size: Vector3):
	var petal = MeshInstance3D.new(); var mesh = SphereMesh.new(); mesh.radius = 0.03; mesh.height = 0.045; mesh.radial_segments = 5; mesh.rings = 3
	petal.mesh = mesh; petal.material_override = material; petal.scale = size / Vector3(0.06, 0.045, 0.06)
	petal.position = Vector3(cos(angle) * 0.022, y, sin(angle) * 0.022); petal.rotation.y = -angle; root.add_child(petal)

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
	return _draw_card_from_deck(deck)

func _draw_card_from_deck(deck: int) -> Dictionary:
	if deck == 0:
		if randf() < 0.18:
			var building_level = randi_range(1, 2)
			return {"kind": "building_develop", "name": "%d级建筑开发" % building_level, "level": building_level, "deck": "开发"}
		var level = randi_range(1, 4)
		var shape = randi_range(0, 2) if level == 4 else 0
		return {"kind": "develop", "name": "%d级山体开发" % level, "level": level, "deck": "开发", "shape": shape}
	if deck == 1:
		var level = randi_range(1, 3)
		return {"kind": "road", "name": "%d级道路" % level, "level": level, "deck": "道路"}
	var weather_names = ["台风", "沙尘暴", "雨季", "旱季", "彩虹"]
	var weather = weather_names[randi() % weather_names.size()]
	return {"kind": "weather", "name": weather, "level": 1, "deck": "天气", "weather": weather}

func _card_sort_value(card: Dictionary) -> int:
	var kind: String = card["kind"]
	if kind == "seed": return int(card["level"])
	if kind == "develop": return 100 + int(card["level"])
	if kind == "building_develop": return 120 + int(card["level"])
	if kind == "road": return 200 + int(card["level"])
	var weather_order = ["台风", "沙尘暴", "雨季", "旱季", "彩虹"]
	return 300 + maxi(0, weather_order.find(card.get("weather", "")))

func _card_sort_less(a: Dictionary, b: Dictionary) -> bool:
	return _card_sort_value(a) < _card_sort_value(b)

func _sort_current_hand():
	current_hand.sort_custom(_card_sort_less)
	hands[current_player] = current_hand

func _take_card_from_deck(deck_index: int) -> bool:
	if state != S.DRAW_CARDS or draws_remaining <= 0: return false
	current_hand.append(_draw_card_from_deck(deck_index))
	draws_remaining -= 1
	_record_action("从%s卡堆抽牌，剩余%d次" % [["开发", "道路", "天气"][deck_index], draws_remaining])
	_sort_current_hand()
	if draws_remaining <= 0:
		state = S.PLAY_CARDS
		selected_card = 0
	ui_ctrl.queue_redraw()
	return true

func _start_player_turn():
	current_hand = hands[current_player]
	selected_card = 0
	ui_preview_mode = "card"; ui_preview_index = 0
	draws_remaining = CARDS_DRAWN_PER_TURN
	state = S.DRAW_CARDS
	hover_mesh.visible = false
	piece_preview_root.visible = false
	_calc_all_scores()
	ui_ctrl.queue_redraw()

func _start_game():
	action_history.clear(); action_history_tones.clear(); center_notices.clear(); history_scroll = 0
	top_terrain_count_tick = -1
	ranking_order.clear(); ranking_y.clear(); ranking_values.clear()
	_init_grid()
	current_player = randi() % player_count; turns_played = 0
	total_turns = TOTAL_ROUNDS_PER_PLAYER * player_count
	seeds = []; scores = []; group_counts = []; largest_groups = []; diversity_counts = []; road_scores = []
	hands = []; current_hand = []; selected_card = 0
	piece_market = []; selected_market = 0; piece_rotation = 0; last_growth_count = 0
	closed_road_ids = {}; closed_road_cells = {}; last_road_event = ""; last_settlement = ""
	active_weather = {}; rainbow_turns = 0; special_buildings.clear()
	for i in player_count:
		seeds.append(STARTING_SEED_CARDS); scores.append(0); group_counts.append(0)
		largest_groups.append(0); diversity_counts.append(0); road_scores.append(0)
		var hand := []
		for card_index in STARTING_SEED_CARDS:
			hand.append(_make_seed_card(card_index + 1))
		hands.append(hand)
	_generate_start_tiles()
	_refresh_building_auras()
	_start_player_turn()

func _end_turn():
	for card in current_hand:
		card.erase("rolled_terrains"); card.erase("rolled_roads")
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

func _hand_card_rect(index: int, ux: float, iy: float) -> Rect2:
	var column = index % 2; var row = index / 2
	return Rect2(ux + 10 + column * 126, iy + 18 + row * 60, 118, 56)

func _card_description(card: Dictionary) -> String:
	match card["kind"]:
		"seed": return "+%d 朵花" % (int(card["level"]) * 10)
		"develop": return "开发 %d 格山体" % int(card["level"])
		"building_develop": return "洪山科技大厦" if int(card["level"]) == 2 else "缺口建造黄鹤楼"
		"road": return "连接 %d 段道路" % int(card["level"])
		"weather": return "改变本轮环境"
	return ""

func _card_accent(card: Dictionary) -> Color:
	match card["kind"]:
		"seed": return Color("#4f9c62")
		"develop", "building_develop": return Color("#c47a42")
		"road": return Color("#ae8b55")
		"weather": return Color("#568eb0")
	return Color.WHITE

func _card_base_color(card: Dictionary) -> Color:
	match card["kind"]:
		"seed": return Color("#f7f5ef")
		"develop", "building_develop": return Color("#a9afb2")
		"road": return Color("#e8c34f")
		"weather": return Color("#65a9d8")
	return Color.WHITE

func _bottom_card_rect(index: int, count: int, vp: Vector2) -> Rect2:
	var card_size = Vector2(98, 141)
	var hand_left = UI_MARGIN + 315.0
	var hand_right = vp.x - UI_MARGIN - 74.0
	var available = maxf(card_size.x, hand_right - hand_left)
	var step = minf(68.0, maxf(4.0, (available - card_size.x) / maxf(float(count - 1), 1.0)))
	var width = card_size.x + step * maxf(float(count - 1), 0.0)
	var start_x = hand_left + maxf(0.0, (available - width) * 0.5)
	var t = (float(index) / maxf(float(count - 1), 1.0) - 0.5) * 2.0
	var y = vp.y - UI_MARGIN - card_size.y - 21.0 + absf(t) * 14.0
	if index == hovered_card_index or index == selected_card: y -= 28.0
	return Rect2(Vector2(start_x + index * step, y), card_size)

func _hand_card_angle(index: int) -> float:
	var count = current_hand.size()
	if count <= 1 or (dragging_card and index == drag_card_index): return 0.0
	var t = (float(index) / float(count - 1) - 0.5) * 2.0
	return deg_to_rad(t * 10.0)

func _hand_card_scale(index: int) -> float:
	if index == selected_card: return 1.12
	if index == hovered_card_index: return 1.06
	return 1.0

func _hand_card_has_point(pointer: Vector2, index: int, vp: Vector2) -> bool:
	var rect = _bottom_card_rect(index, current_hand.size(), vp)
	var center = rect.get_center()
	var local = (pointer - center).rotated(-_hand_card_angle(index)) / _hand_card_scale(index)
	return Rect2(-rect.size * 0.5, rect.size).has_point(local)

func _deck_rect(index: int, vp: Vector2) -> Rect2:
	return Rect2(UI_MARGIN + 14.0 + index * 96.0, vp.y - UI_MARGIN - 145.0, 82.0, 116.0)

func _card_at_pointer(pointer: Vector2, vp: Vector2) -> int:
	if selected_card >= 0 and selected_card < current_hand.size() and _hand_card_has_point(pointer, selected_card, vp): return selected_card
	if hovered_card_index >= 0 and hovered_card_index < current_hand.size() and _hand_card_has_point(pointer, hovered_card_index, vp): return hovered_card_index
	for index in range(current_hand.size() - 1, -1, -1):
		if _hand_card_has_point(pointer, index, vp): return index
	return -1

func _begin_card_drag(index: int):
	if state != S.PLAY_CARDS or index < 0 or index >= current_hand.size(): return
	_clear_tile_selection()
	selected_card = index; dragging_card = true; drag_card_index = index
	card_drag_origin = drag_pointer
	ui_preview_mode = "card"; ui_preview_index = index
	road_drag_cells.clear(); develop_preview_cells.clear(); pending_develop.clear()
	var card: Dictionary = current_hand[index]
	if card["kind"] == "road": road_drag_level = int(card["level"])
	elif card["kind"] == "develop":
		if not card.has("rolled_terrains"):
			var terrains := []
			for i in int(card["level"]): terrains.append(_draw_terrain())
			var offsets = _development_shape_offsets(int(card["level"]), int(card.get("shape", 0)))
			card["rolled_terrains"] = terrains; card["rolled_roads"] = _make_local_road_masks(offsets)
			current_hand[index] = card
		pending_develop = {"terrains": card["rolled_terrains"], "roads": card["rolled_roads"]}
	ui_ctrl.queue_redraw()

func _release_hand_drag(pointer: Vector2, cell: Vector2i):
	dragging_card = false
	var vp = get_viewport().get_visible_rect().size / _ui_scale(get_viewport().get_visible_rect().size)
	var release_point = _ui_point(pointer)
	var drag_distance = pointer.distance_to(card_drag_origin)
	# A click only selects the card. Activation requires a deliberate drag beyond the rail.
	if drag_distance < 32.0 or release_point.y >= _ui_rail_rect(vp).position.y:
		_cancel_armed_card(); return
	card_armed = true
	ui_preview_mode = "card"; ui_preview_index = drag_card_index
	var card: Dictionary = current_hand[drag_card_index]
	if not _card_has_valid_target(card):
		_warn_player(_invalid_card_action_message(card))
		_cancel_armed_card(); return
	if card["kind"] == "weather": _finish_card_drag(cell)
	else: _update_card_drag_preview(cell)
	_update_placement_highlights()
	ui_ctrl.queue_redraw()

func _cancel_armed_card():
	dragging_card = false; card_armed = false; road_drawing = false; drag_card_index = -1
	road_drag_cells.clear(); pending_develop.clear(); develop_preview_cells.clear()
	for child in piece_preview_root.get_children(): child.free()
	piece_preview_root.visible = false; _clear_placement_highlights(); ui_ctrl.queue_redraw()

func _update_placement_highlights():
	_clear_placement_highlights()
	var card = _selected_card()
	if card.is_empty() or card["kind"] == "weather": return
	# 只在已有非山体地块的邻域内检查，避免外围山体亮满
	var developed := {}
	for x in _grid_width():
		for y in _grid_height():
			if grid[x][y] >= 0 and grid[x][y] != T_MOUNTAIN:
				developed[Vector2i(x, y)] = true
	var check_zone := {}
	for pos in developed:
		check_zone[pos] = true
		for dir in DIRS:
			var n = pos + dir
			if _in_bounds(n): check_zone[n] = true
	for pos in check_zone:
		if _can_play_selected_card(pos):
			_spawn_tile_breath_glow(pos)

func _clear_placement_highlights():
	for node in placement_highlights:
		if is_instance_valid(node): node.queue_free()
	placement_highlights.clear()

func _spawn_tile_breath_glow(pos: Vector2i):
	var glow = MeshInstance3D.new()
	var gm = BoxMesh.new(); gm.size = Vector3(1.06, 0.025, 1.06)
	glow.mesh = gm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.15)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true; mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 0.3
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	glow.material_override = mat
	glow.position = _world(pos) + Vector3(0, 0.16, 0)
	placement_highlight_root.add_child(glow)
	placement_highlights.append(glow)
	var tw = create_tween().set_loops()
	tw.tween_property(mat, "albedo_color:a", 0.30, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mat, "albedo_color:a", 0.10, 0.8).set_trans(Tween.TRANS_SINE)
	var tw2 = create_tween().set_loops()
	tw2.tween_property(mat, "emission_energy_multiplier", 0.6, 0.8).set_trans(Tween.TRANS_SINE)
	tw2.tween_property(mat, "emission_energy_multiplier", 0.15, 0.8).set_trans(Tween.TRANS_SINE)

func _card_has_valid_target(card: Dictionary) -> bool:
	if card["kind"] == "weather": return true
	if card["kind"] == "road":
		for x in _grid_width():
			for y in _grid_height():
				var pos = Vector2i(x, y)
				if grid[x][y] < 0 or _is_developable(grid[x][y]): continue
				for direction in DIRS:
					var neighbor = pos + direction
					if _in_bounds(neighbor) and grid[neighbor.x][neighbor.y] >= 0 and not _is_developable(grid[neighbor.x][neighbor.y]): return true
		return false
	if card["kind"] == "seed":
		for x in _grid_width():
			for y in _grid_height():
				var pos = Vector2i(x, y)
				if _is_plant_terrain(grid[x][y]) and _flower_total(pos) < _tile_capacity(pos): return true
		return false
	var saved_rotation := piece_rotation
	for rotation in 4:
		piece_rotation = rotation
		for x in _grid_width():
			for y in _grid_height():
				var pos = Vector2i(x, y)
				if card["kind"] == "develop" and _can_develop_cells(_develop_card_cells(pos, int(card["level"]), rotation)):
					piece_rotation = saved_rotation; return true
				if card["kind"] == "building_develop":
					var cells = [pos] if int(card["level"]) == 1 else [pos, pos + DIRS[rotation]]
					var valid := true
					for target in cells:
						if not _in_bounds(target) or grid[target.x][target.y] != T_GAP: valid = false; break
					if valid: piece_rotation = saved_rotation; return true
	piece_rotation = saved_rotation
	return false

func _extend_road_drag(cell: Vector2i):
	if not _in_bounds(cell) or _is_developable(grid[cell.x][cell.y]) or grid[cell.x][cell.y] < 0: return
	if road_drag_cells.is_empty():
		road_drag_cells.append(cell); return
	var last: Vector2i = road_drag_cells.back()
	if cell == last: return
	if road_drag_cells.size() >= 2 and cell == road_drag_cells[road_drag_cells.size() - 2]:
		road_drag_cells.pop_back(); return
	if abs(cell.x - last.x) + abs(cell.y - last.y) != 1: return
	if road_drag_cells.has(cell) or road_drag_cells.size() >= road_drag_level + 1: return
	road_drag_cells.append(cell)

func _apply_road_path(cells: Array) -> bool:
	if cells.size() != road_drag_level + 1: return false
	for i in cells.size() - 1: _connect_road(cells[i], cells[i + 1])
	for cell in cells: _update_road_bridges(cell)
	_refresh_road_effects(); last_settlement = "修建了长度%d道路" % road_drag_level
	return true

func _drag_card_index_is_valid() -> bool:
	return drag_card_index >= 0 and drag_card_index < current_hand.size()

func _consume_dragged_card(played_card: Dictionary) -> bool:
	var consume_index = -1
	if _drag_card_index_is_valid() and current_hand[drag_card_index] == played_card:
		consume_index = drag_card_index
	else:
		consume_index = current_hand.find(played_card)
	if consume_index < 0 or consume_index >= current_hand.size():
		_warn_player("卡牌状态已经变化，本次操作已取消")
		return false
	current_hand.remove_at(consume_index)
	_sort_current_hand()
	selected_card = clampi(consume_index, 0, maxi(current_hand.size() - 1, 0))
	ui_preview_mode = "card"; ui_preview_index = selected_card
	hands[current_player] = current_hand
	return true

func _finish_card_drag(cell: Vector2i):
	if not card_armed and not road_drawing: return
	if not _drag_card_index_is_valid():
		_cancel_armed_card()
		_warn_player("卡牌状态已经变化，本次操作已取消")
		return
	var card: Dictionary = current_hand[drag_card_index]
	var before_flowers: int = _flower_total(cell) if _in_bounds(cell) else 0
	var ok := false
	if card["kind"] == "road": ok = _apply_road_path(road_drag_cells)
	elif card["kind"] == "weather": ok = _apply_weather_card(card)
	elif _in_bounds(cell):
		if card["kind"] == "develop": ok = _apply_pending_develop(cell, card)
		elif card["kind"] == "building_develop": ok = _apply_building_develop_card(cell, int(card["level"]))
		elif card["kind"] == "seed":
			ok = _add_flowers(cell, current_player, int(card["level"]) * 10)
			if ok: seeds[current_player] = maxi(0, seeds[current_player] - 1)
	if ok:
		if card["kind"] == "seed": last_settlement = "播种增加%d朵" % (_flower_total(cell) - before_flowers)
		_record_action(last_settlement)
		_consume_dragged_card(card); _calc_all_scores(); _cancel_armed_card()
	else:
		dragging_card = false; road_drawing = false; road_drag_cells.clear()
		_warn_player(_invalid_card_action_message(card))
		_update_card_drag_preview(cell); ui_ctrl.queue_redraw()

func _invalid_card_action_message(card: Dictionary) -> String:
	match str(card.get("kind", "")):
		"seed": return "请选择花朵未满的植物地块"
		"develop": return "开发区块必须完整覆盖山体并邻接已开发地块"
		"building_develop": return "没有符合建筑占地形状的完整缺口"
		"road": return "道路必须在允许地块上连续绘制到规定长度"
		"weather": return "当前天气状态不允许使用这张天气卡"
	return "当前位置无法使用这张卡"

func _record_action(message: String, tone: String = "info", actor_id: int = -1):
	var resolved_actor = current_player if actor_id < 0 else clampi(actor_id, 0, maxi(player_count - 1, 0))
	action_history.push_front("%s · %s" % [PLAYER_NAMES[resolved_actor], message])
	action_history_tones.push_front(tone)
	history_scroll = 0

func _show_center_notice(message: String, tone: String):
	center_notices.append({"text": message, "tone": tone, "age": 0.0})
	if center_notices.size() > 4: center_notices.pop_front()
	ui_ctrl.queue_redraw()

func _warn_player(message: String):
	_record_action("WARNING · %s" % message, "warning")
	_show_center_notice(message, "warning")

func _apply_pending_develop(anchor: Vector2i, card: Dictionary) -> bool:
	var cells = _develop_card_cells(anchor, int(card["level"]), piece_rotation)
	if not _can_develop_cells(cells): return false
	var generated: Array = pending_develop.get("terrains", [])
	var generated_roads: Array = pending_develop.get("roads", [])
	for i in cells.size(): _set_tile_type(cells[i], generated[i], true, _rotate_road_mask(generated_roads[i], piece_rotation))
	_update_gaps(); _ensure_growth_margin(cells); _update_gaps(); _refresh_road_effects()
	_grant_seed_card(current_player, 1, "开发完成")
	last_settlement = "开发了 %d 格新地块，获得1级播种卡" % cells.size()
	return true

func _make_local_road_masks(offsets: Array) -> Array:
	var masks := []
	for i in offsets.size(): masks.append(0)
	if offsets.size() < 2 or randf() > 0.38: return masks
	var connected := [0]
	while connected.size() < offsets.size():
		var options := []
		for from_index in connected:
			for to_index in offsets.size():
				if connected.has(to_index): continue
				var dir_index = _direction_index(offsets[to_index] - offsets[from_index])
				if dir_index >= 0: options.append([from_index, to_index, dir_index])
		if options.is_empty(): break
		var edge = options.pick_random(); masks[edge[0]] |= 1 << edge[2]; masks[edge[1]] |= 1 << ((edge[2] + 2) % 4); connected.append(edge[1])
	return masks

func _generate_development_roads(cells: Array):
	var eligible := []
	for cell in cells:
		if _in_bounds(cell) and not _is_developable(grid[cell.x][cell.y]): eligible.append(cell)
	if eligible.size() < 2 or randf() > 0.38: return
	var max_len = randi_range(2, mini(4, eligible.size()))
	var path := [eligible.pick_random()]
	while path.size() < max_len:
		var options := []
		for cell in eligible:
			if path.has(cell): continue
			for placed in path:
				if abs(cell.x - placed.x) + abs(cell.y - placed.y) == 1: options.append([placed, cell]); break
		if options.is_empty(): break
		var edge = options.pick_random(); _connect_road(edge[0], edge[1]); path.append(edge[1])
	for cell in cells: _update_road_bridges(cell)
	_refresh_road_effects()

func _can_play_selected_card(pos: Vector2i) -> bool:
	if not _in_bounds(pos): return false
	var card = _selected_card()
	if card.is_empty(): return false
	match card["kind"]:
		"seed":
			return seeds[current_player] > 0 and _is_plant_terrain(grid[pos.x][pos.y]) and _flower_total(pos) < _tile_capacity(pos)
		"develop":
			return _can_develop_cells(_develop_card_cells(pos, int(card["level"]), piece_rotation))
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
			var weather: String = card.get("weather", "")
			if weather == "彩虹": return rainbow_turns <= 0 or not active_weather.is_empty()
			return not active_weather.has(weather)
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
			# Development cards are committed through the drag preview flow.
			ok = false
		"building_develop":
			ok = _apply_building_develop_card(pos, int(card["level"]))
		"road":
			# Road cards require a continuous dragged path.
			ok = false
		"weather":
			ok = _apply_weather_card(card)
	if ok:
		current_hand.remove_at(selected_card)
		selected_card = clampi(selected_card, 0, maxi(current_hand.size() - 1, 0))
		ui_preview_mode = "card"; ui_preview_index = selected_card
		flash_timer = 0.18; flash_color = PLAYER_COLORS[current_player]
		_calc_all_scores(); ui_ctrl.queue_redraw()
	return ok

func _apply_develop_card(pos: Vector2i, level: int) -> bool:
	var cells = _develop_card_cells(pos, level, piece_rotation)
	if not _can_develop_cells(cells): return false
	for cell in cells:
		_set_tile_type(cell, _draw_terrain(), true, _random_road_mask())
	_generate_development_roads(cells)
	_update_gaps()
	_ensure_growth_margin(cells)
	_update_gaps()
	_refresh_road_effects()
	_refresh_building_auras()
	_grant_seed_card(current_player, 1, "开发完成")
	last_settlement = "开发了 %d 格新地块，获得1级播种卡" % cells.size()
	return true

func _can_develop_cells(cells: Array) -> bool:
	if cells.is_empty(): return false
	var touches_developed := false
	for cell in cells:
		# A mountain development card may never overwrite gaps or developed terrain.
		if not _in_bounds(cell) or grid[cell.x][cell.y] != T_MOUNTAIN: return false
		for dir in DIRS:
			var neighbor = cell + dir
			if _in_bounds(neighbor) and not cells.has(neighbor) and not _is_developable(grid[neighbor.x][neighbor.y]):
				touches_developed = true
	return touches_developed

func _apply_building_develop_card(pos: Vector2i, level: int) -> bool:
	var cells = [pos] if level == 1 else [pos, pos + DIRS[piece_rotation]]
	for cell in cells:
		if not _in_bounds(cell) or grid[cell.x][cell.y] != T_GAP: return false
	if level == 1:
		special_buildings.erase(_logical_cell(pos))
		_set_tile_type(pos, T_BUILDING, true, 0)
	else:
		for i in cells.size():
			special_buildings[_logical_cell(cells[i])] = {"kind": "hongshan_tech", "part": i, "direction": piece_rotation}
			_set_tile_type(cells[i], T_BUILDING, true, 0)
	_refill_mountain_border()
	_refresh_building_auras()
	_refresh_road_effects()
	_grant_seed_card(current_player, 1, "建筑开发")
	last_settlement = ("建成洪山科技大厦" if level == 2 else "缺口变为黄鹤楼") + "，获得1级播种卡"
	return true

func _develop_card_cells(pos: Vector2i, level: int, rotation: int = 0) -> Array:
	var active_card = _selected_card()
	var shape_index = int(active_card.get("shape", 0)) if not active_card.is_empty() else 0
	var result := []
	for cell in _development_shape_offsets(level, shape_index): result.append(pos + _rotate_cell(cell, rotation))
	return result

func _development_shape_offsets(level: int, shape_index: int = 0) -> Array:
	match level:
		1: return [Vector2i.ZERO]
		2: return [Vector2i.ZERO, Vector2i.RIGHT]
		3: return [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN]
		4:
			var shapes = [
				[Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1)],
				[Vector2i.ZERO, Vector2i.RIGHT, Vector2i(1, 1), Vector2i(2, 1)],
				[Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN],
			]
			return shapes[clampi(shape_index, 0, shapes.size() - 1)]
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
	_displace_flowers_for_road(a)
	_displace_flowers_for_road(b)

func _apply_weather_card(card: Dictionary) -> bool:
	var weather: String = card["weather"]
	if weather == "彩虹":
		if rainbow_turns > 0 and active_weather.is_empty(): return false
		_apply_weather_visual(weather)
		active_weather.clear()
		rainbow_turns = 1
		last_settlement = "彩虹清除了极端天气"
	else:
		if active_weather.has(weather): return false
		if weather == "旱季":
			active_weather.erase("雨季")
			active_weather.erase("台风")
		elif weather == "雨季" or weather == "台风":
			active_weather.erase("旱季")
		_apply_weather_visual(weather)
		active_weather[weather] = 3
		last_settlement = "%s将持续3回合" % weather
	return true

func _apply_weather_visual(weather: String):
	for child in weather_fx_root.get_children(): child.free()
	weather_fx_root.position = Vector3.ZERO
	var center = _world(Vector2i(_grid_width() / 2, _grid_height() / 2))
	weather_fx_root.set_meta("weather_center", center)
	if weather == "台风" or weather == "雨季":
		_spawn_weather_rain(center, 60 if weather == "台风" else 40, weather == "台风")
	elif weather == "沙尘暴":
		_spawn_weather_drift(center, Color(0.88, 0.70, 0.34, 0.78), 100)
		_spawn_weather_bands(center, Color(0.76, 0.57, 0.25, 0.18))
	elif weather == "旱季":
		_spawn_weather_bands(center, Color(1.0, 0.78, 0.30, 0.12))
		var sun = MeshInstance3D.new(); var mesh = SphereMesh.new()
		mesh.radius = 0.75; mesh.height = 1.5; mesh.radial_segments = 12; mesh.rings = 6; sun.mesh = mesh
		var material = _soft_material(Color(1.0, 0.84, 0.26, 0.12), 1.3); sun.material_override = material
		sun.position = center + Vector3(-2.8, 4.5, -2.8); weather_fx_root.add_child(sun)
		var tween = create_tween().set_loops()
		tween.tween_property(sun, "scale", Vector3.ONE * 1.14, 1.8).set_trans(Tween.TRANS_SINE)
		tween.tween_property(sun, "scale", Vector3.ONE, 1.8).set_trans(Tween.TRANS_SINE)
	else:
		# 彩虹：只生成上半弧，放在地块缝隙中心。
		var rainbow_colors = [Color("#e85b56"), Color("#e99b45"), Color("#ead45d"), Color("#68b978"), Color("#5fb8c7"), Color("#5b78c9"), Color("#a46ab9")]
		var gap_center = _world(Vector2i(_grid_width() / 2, _grid_height() / 2)) + Vector3(TILE_SPACING * 0.5, 0, TILE_SPACING * 0.5)
		for index in rainbow_colors.size():
			var ring := MeshInstance3D.new()
			ring.mesh = _make_rainbow_arc_mesh(1.15 + index * 0.09, 0.055, 40)
			var material = _soft_material(Color(rainbow_colors[index], 0.45), 0.35)
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			ring.material_override = material
			ring.position = gap_center + Vector3(0, 0.55, 0)
			ring.set_meta("rainbow", true)
			ring.set_meta("rainbow_base_pos", ring.position)
			weather_fx_root.add_child(ring)

func _make_rainbow_arc_mesh(radius: float, thickness: float, segments: int) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in range(segments + 1):
		var t := PI * float(i) / float(segments)
		var outer := radius + thickness
		var inner := radius
		vertices.append(Vector3(cos(t) * outer, sin(t) * outer, 0.0))
		vertices.append(Vector3(cos(t) * inner, sin(t) * inner, 0.0))
		normals.append(Vector3(0, 0, 1))
		normals.append(Vector3(0, 0, 1))
	for i in segments:
		var a := i * 2
		indices.append(a); indices.append(a + 2); indices.append(a + 1)
		indices.append(a + 1); indices.append(a + 2); indices.append(a + 3)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _spawn_weather_rain(center: Vector3, count: int, storm: bool):
	if storm:
		for cloud_index in 4:
			var cloud = MeshInstance3D.new(); var cloud_mesh = SphereMesh.new()
			cloud_mesh.radius = 1.2; cloud_mesh.height = 0.65; cloud_mesh.radial_segments = 10; cloud_mesh.rings = 5
			cloud.mesh = cloud_mesh; cloud.material_override = _soft_material(Color(0.22, 0.27, 0.30, 0.28))
			cloud.position = center + Vector3(-3.0 + cloud_index * 2.0, 3.4 + cloud_index % 2 * 0.25, -1.5 + cloud_index % 3)
			weather_fx_root.add_child(cloud)
			create_tween().set_loops().tween_property(cloud, "position:x", cloud.position.x + 1.2, 3.4).set_trans(Tween.TRANS_SINE)
	var rain_material = _soft_material(Color(0.50, 0.65, 0.90, 0.55))
	for drop_index in count:
		var drop = MeshInstance3D.new(); var mesh = CylinderMesh.new()
		mesh.top_radius = 0.008; mesh.bottom_radius = 0.008; mesh.height = 0.15; mesh.radial_segments = 4
		drop.mesh = mesh; drop.material_override = rain_material
		drop.position = center + Vector3(randf_range(-5.0, 5.0), randf_range(0.5, 3.4), randf_range(-5.0, 5.0))
		weather_fx_root.add_child(drop)
		var top_y = drop.position.y; var tween = create_tween().set_loops()
		tween.tween_property(drop, "position:y", 0.0, randf_range(0.35, 0.65))
		tween.tween_property(drop, "position:y", top_y, 0.01)

func _spawn_weather_drift(center: Vector3, color: Color, count: int):
	var material = _soft_material(color, 0.08)
	for grain_index in count:
		var grain = MeshInstance3D.new(); var mesh = SphereMesh.new()
		mesh.radius = 0.035; mesh.height = 0.05; mesh.radial_segments = 5; mesh.rings = 3
		grain.mesh = mesh; grain.material_override = material
		grain.position = center + Vector3(randf_range(-5.0, 5.0), randf_range(0.2, 2.2), randf_range(-5.0, 5.0))
		weather_fx_root.add_child(grain)
		var start_x = grain.position.x; var tween = create_tween().set_loops()
		tween.tween_property(grain, "position:x", start_x + 7.0, randf_range(1.8, 3.2))
		tween.tween_property(grain, "position:x", start_x, 0.01)

func _spawn_weather_bands(center: Vector3, color: Color):
	for index in 7:
		var band = MeshInstance3D.new(); var mesh = BoxMesh.new()
		mesh.size = Vector3(5.0, 0.06, 0.65); band.mesh = mesh
		band.material_override = _soft_material(color)
		band.position = center + Vector3(-4.0, 0.6 + index * 0.16, -4.0 + index * 1.3)
		weather_fx_root.add_child(band)
		var tween = band.create_tween().set_loops()
		tween.tween_property(band, "position:x", center.x + 4.0, 4.0 + index * 0.2)
		tween.tween_property(band, "position:x", center.x - 4.0, 0.01)

func _settle_turn():
	var old_score: int = scores[current_player]
	var grid_snapshot = grid.duplicate(true)
	var flower_snapshot = flowers.duplicate(true)
	_apply_weather_tile_changes()
	_apply_neighbor_terrain_changes()
	_grow_flowers()
	_spread_flowers()
	_emit_settlement_labels(grid_snapshot, flower_snapshot)
	_tick_weather()
	_refresh_all_plants()
	_refresh_building_auras()
	_refresh_road_effects()
	_calc_all_scores()
	_record_action("结算 %d朵 (%+d)" % [scores[current_player], scores[current_player] - old_score])

func _emit_settlement_labels(grid_snapshot: Array, flower_snapshot: Array):
	var delay := 0.0
	for x in _grid_width():
		for y in _grid_height():
			var pos = Vector2i(x, y)
			var changed := false
			for player_id in player_count:
				var gain: int = flowers[x][y][player_id] - flower_snapshot[x][y][player_id]
				if gain > 0:
					_float_settlement_label(pos, "+%d" % gain, PLAYER_COLORS[player_id], delay)
					changed = true
			var old_terrain: int = grid_snapshot[x][y]
			if old_terrain >= 0 and old_terrain != grid[x][y]:
				_float_settlement_label(pos, "%s>%s" % [TERRAIN_NAMES[old_terrain].substr(0, 1), TERRAIN_NAMES[grid[x][y]].substr(0, 1)], Color("#e8c840"), delay)
				changed = true
			if changed: delay += 0.08

func _float_settlement_label(pos: Vector2i, label_text: String, color: Color, delay: float = 0.0):
	var label = Label3D.new(); label.text = label_text; label.font_size = 28; label.pixel_size = 0.005
	label.modulate = color; label.outline_size = 8; label.outline_modulate = Color(0.04, 0.06, 0.05, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; label.no_depth_test = true
	label.render_priority = 90
	label.position = _world(pos) + Vector3(randf_range(-0.30, 0.30), 0.54 + randf_range(0, 0.12), 0)
	label.modulate.a = 0.0  # 先隐藏
	settle_fx_root.add_child(label)
	var tween = create_tween()
	tween.tween_interval(delay)
	tween.tween_property(label, "modulate:a", 1.0, 0.01)
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 0.80, 3.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(label, "modulate:a", 0.0, 3.0).set_delay(1.5)
	tween.chain().tween_callback(label.queue_free)

func _tick_weather():
	var expired := []
	for weather in active_weather.keys():
		active_weather[weather] = int(active_weather[weather]) - 1
		if active_weather[weather] <= 0: expired.append(weather)
	for weather in expired: active_weather.erase(weather)
	if rainbow_turns > 0: rainbow_turns -= 1
	if active_weather.is_empty() and rainbow_turns <= 0:
		for child in weather_fx_root.get_children(): child.free()

func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < _grid_width() and pos.y >= 0 and pos.y < _grid_height()

func _apply_weather_tile_changes():
	if active_weather.has("台风"):
		var waters := []
		for x in _grid_width():
			for y in _grid_height():
				if grid[x][y] == T_WATER: waters.append(Vector2i(x, y))
		for pos in waters:
			_weather_convert_neighbor(pos, T_WATER)
	if active_weather.has("沙尘暴"):
		var deserts := []
		for x in _grid_width():
			for y in _grid_height():
				if grid[x][y] == T_DESERT: deserts.append(Vector2i(x, y))
		for pos in deserts:
			_weather_convert_neighbor(pos, T_DESERT)
	if active_weather.has("旱季"):
		var dried_waters := []
		for x in _grid_width():
			for y in _grid_height():
				if grid[x][y] == T_WATER and randf() < 0.30:
					dried_waters.append(Vector2i(x, y))
		for pos in dried_waters:
			_set_tile_type(pos, T_GRASS, true)
			for dir in DIRS:
				var neighbor = pos + dir
				if _in_bounds(neighbor):
					_update_edge_bridges(neighbor)
					_update_road_bridges(neighbor)
					_refresh_neighbor_trims(neighbor)

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
	for x in _grid_width():
		for y in _grid_height():
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
	for x in _grid_width():
		for y in _grid_height():
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
	for x in _grid_width():
		for y in _grid_height():
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
						add_for_tile[pid] += floori(float(amount * amount) / float(neighbor_capacity) * prob * 0.3)
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
	for x in _grid_width():
		for y in _grid_height():
			_refresh_plant_visual(Vector2i(x, y))

func _update_gaps():
	var developed = _non_developable_cells()
	if developed.is_empty(): return
	var min_x = developed[0].x; var max_x = min_x; var min_y = developed[0].y; var max_y = min_y
	for cell in developed:
		min_x = mini(min_x, cell.x); max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y); max_y = maxi(max_y, cell.y)
	min_x = maxi(0, min_x - 1); min_y = maxi(0, min_y - 1)
	max_x = mini(_grid_width() - 1, max_x + 1); max_y = mini(_grid_height() - 1, max_y + 1)
	var exterior := {}; var pending := []
	for x in range(min_x, max_x + 1):
		for y in [min_y, max_y]:
			var p = Vector2i(x, y)
			if grid[x][y] == -1 or grid[x][y] == T_MOUNTAIN: pending.append(p)
	for y in range(min_y + 1, max_y):
		for x in [min_x, max_x]:
			var p = Vector2i(x, y)
			if grid[x][y] == -1 or grid[x][y] == T_MOUNTAIN: pending.append(p)
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		if exterior.has(cell): continue
		exterior[cell] = true
		for dir in DIRS:
			var neighbor = cell + dir
			if neighbor.x < min_x or neighbor.x > max_x or neighbor.y < min_y or neighbor.y > max_y: continue
			if not exterior.has(neighbor) and (grid[neighbor.x][neighbor.y] == -1 or grid[neighbor.x][neighbor.y] == T_MOUNTAIN): pending.append(neighbor)
	for x in range(min_x + 1, max_x):
		for y in range(min_y + 1, max_y):
			var pos = Vector2i(x, y)
			if not exterior.has(pos) and (grid[x][y] == -1 or grid[x][y] == T_MOUNTAIN):
				if grid[x][y] == -1: _force_tile(pos, T_GAP, true, 0)
				else: _set_tile_type(pos, T_GAP, true, 0)

func _refill_mountain_border():
	for x in _grid_width():
		for y in _grid_height():
			if x == 0 or y == 0 or x == _grid_width() - 1 or y == _grid_height() - 1:
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
		for x in _grid_width():
			for y in _grid_height():
				var amount: int = flowers[x][y][pid]
				if amount > 0:
					flower_score += amount
					if _is_plant_terrain(grid[x][y]): occupied_tiles += 1
		var vis := []
		for x in _grid_width():
			vis.append([])
			for y in _grid_height(): vis[x].append(false)
		var groups := 0; var largest := 0
		for x in _grid_width():
			for y in _grid_height():
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
	for x in _grid_width():
		for y in _grid_height():
			if flowers[x][y][pid - 1] <= 0: continue
			var pos = Vector2i(x, y)
			if closed_road_cells.has(pos): connections += 2
			for dir in [Vector2i.RIGHT, Vector2i.DOWN]:
				var neighbor = pos + dir
				if _in_bounds(neighbor) and flowers[neighbor.x][neighbor.y][pid - 1] > 0:
					if _roads_connect(pos, neighbor): connections += 1
	return connections

func _flood_p(x: int, y: int, v: Array, pid: int) -> int:
	if x < 0 or x >= _grid_width() or y < 0 or y >= _grid_height(): return 0
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
	var gx = roundi((hit.x + off) / TILE_SPACING) + grid_origin.x
	var gy = roundi((hit.z + off) / TILE_SPACING) + grid_origin.y
	if gx >= 0 and gx < _grid_width() and gy >= 0 and gy < _grid_height(): return Vector2i(gx, gy)
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

func _update_card_drag_preview(cell: Vector2i):
	for child in piece_preview_root.get_children(): child.free()
	piece_preview_root.visible = false
	if (not dragging_card and not card_armed and not road_drawing) or not _drag_card_index_is_valid(): return
	var card: Dictionary = current_hand[drag_card_index]
	var preview_cells := []
	var preview_terrains := []
	var valid := false
	if card["kind"] == "develop" and _in_bounds(cell):
		preview_cells = _develop_card_cells(cell, int(card["level"]), piece_rotation)
		preview_terrains = pending_develop.get("terrains", [])
		valid = _can_develop_cells(preview_cells)
	elif card["kind"] == "building_develop" and _in_bounds(cell):
		preview_cells = [cell] if int(card["level"]) == 1 else [cell, cell + DIRS[piece_rotation]]
		for building_cell in preview_cells: preview_terrains.append(T_BUILDING)
		valid = true
		for building_cell in preview_cells:
			if not _in_bounds(building_cell) or grid[building_cell.x][building_cell.y] != T_GAP: valid = false
	elif card["kind"] == "road":
		preview_cells = road_drag_cells
		for road_cell in preview_cells: preview_terrains.append(grid[road_cell.x][road_cell.y])
		valid = preview_cells.size() == road_drag_level + 1
	else: return
	piece_preview_root.visible = true
	for i in preview_cells.size():
		var root = Node3D.new(); root.position = _world(preview_cells[i]) + Vector3(0, 0.08, 0)
		piece_preview_root.add_child(root)
		var terrain: int = preview_terrains[i] if i < preview_terrains.size() else T_GRASS
		_spawn_preview_tile_model(root, terrain, card, i)
		var overlay = MeshInstance3D.new(); var box = BoxMesh.new(); box.size = Vector3(1.04, 0.025, 1.04)
		overlay.mesh = box
		var material = _soft_material(Color(0.24, 0.90, 0.52, 0.24) if valid else Color(0.92, 0.22, 0.20, 0.28))
		material.no_depth_test = true; overlay.material_override = material; overlay.position.y = 0.20
		root.add_child(overlay)
		if card["kind"] == "develop":
			var preview_roads: Array = pending_develop.get("roads", [])
			if i < preview_roads.size():
				var road_mask = _rotate_road_mask(preview_roads[i], piece_rotation)
				if road_mask != 0: _spawn_road(root, road_mask)
		if card["kind"] == "road":
			var mask := 0
			if i > 0:
				var previous: Vector2i = preview_cells[i - 1]
				var back_dir = _direction_index(previous - preview_cells[i]); mask |= 1 << back_dir
			if i + 1 < preview_cells.size(): mask |= 1 << _direction_index(preview_cells[i + 1] - preview_cells[i])
			if mask != 0: _spawn_road(root, mask)

func _spawn_preview_tile_model(root: Node3D, terrain: int, card: Dictionary, index: int):
	_spawn_island_base(root, terrain)
	match terrain:
		T_GRASS: _tile_grass_surface(root, 0)
		T_WATER: _tile_water_surface(root, 0)
		T_FOREST: _tile_forest_surface(root, 0)
		T_DESERT: _tile_desert_surface(root, 0)
		T_MOUNTAIN: _tile_mountain_surface(root)
		T_BUILDING:
			if card.get("kind", "") == "building_develop" and int(card.get("level", 1)) == 2:
				_tile_hongshan_tech_surface(root, {"part": index, "direction": piece_rotation})
			else: _tile_pavilion_surface(root, 0)
		_: pass
	_make_preview_translucent(root)

func _make_preview_translucent(node: Node):
	for child in node.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			var source: StandardMaterial3D = child.material_override
			var material: StandardMaterial3D = source.duplicate()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = minf(material.albedo_color.a, 0.46)
			material.no_depth_test = true; child.material_override = material
		_make_preview_translucent(child)

# ================================================================
#  LOOP
# ================================================================
func _process(delta):
	pulse += delta
	if flash_timer > 0: flash_timer = max(0, flash_timer - delta * 2.5)
	for notice_index in range(center_notices.size() - 1, -1, -1):
		var notice: Dictionary = center_notices[notice_index]
		notice["age"] = float(notice.get("age", 0.0)) + delta
		if float(notice["age"]) >= 2.4: center_notices.remove_at(notice_index)
		else: center_notices[notice_index] = notice
	_animate_sky_world(delta)
	_animate_tile_ambience(delta)
	# 天气动效跟随摄像机（彩虹除外）
	if weather_fx_root.has_meta("weather_center"):
		var wc: Vector3 = weather_fx_root.get_meta("weather_center")
		var offset = Vector3(cam_offset.x - wc.x, 0, cam_offset.y - wc.z)
		weather_fx_root.position = offset
		# 彩虹节点反向移动，保持在原位
		for child in weather_fx_root.get_children():
			if child.has_meta("rainbow"):
				child.position = child.get_meta("rainbow_base_pos") - offset
	if state != S.TITLE and scores.size() == player_count:
		if ranking_order.size() != player_count:
			ranking_order.clear()
			for pid in player_count: ranking_order.append(pid)
		# Adjacent swaps preserve the previous order for ties.
		for iteration in player_count:
			for rank in range(player_count - 1):
				if scores[ranking_order[rank]] < scores[ranking_order[rank + 1]]:
					var swap: int = ranking_order[rank]
					ranking_order[rank] = ranking_order[rank + 1]; ranking_order[rank + 1] = swap
		for rank in player_count:
			var pid: int = ranking_order[rank]
			ranking_y[pid] = lerpf(float(ranking_y.get(pid, rank * 30.0)), rank * 30.0, minf(delta * 7.0, 1.0))
			ranking_values[pid] = lerpf(float(ranking_values.get(pid, 0.0)), float(scores[pid]), minf(delta * 7.0, 1.0))

	var viewport_size = get_viewport().get_visible_rect().size
	var play_aspect = maxf(viewport_size.x / maxf(viewport_size.y, 1.0), 0.35)
	var camera_fit = maxf(1.0, 1.05 / play_aspect)

	# The world fills the viewport; interface panels float above it.
	cam_zoom = lerp(cam_zoom, cam_zoom_target, delta * 10.0)
	camera.size = CAM_BASE_SIZE * camera_fit / cam_zoom

	# Smooth pan interpolation
	cam_offset = cam_offset.lerp(cam_offset_target, delta * 10.0)
	var base_pos = Vector3(7.2, 14.2, 10.8)
	camera.position = base_pos + Vector3(cam_offset.x, 0, cam_offset.y)

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

func _animate_tile_ambience(delta: float):
	for index in range(falling_leaves.size() - 1, -1, -1):
		var leaf = falling_leaves[index]
		if not is_instance_valid(leaf): falling_leaves.remove_at(index); continue
		var speed: float = leaf.get_meta("speed"); var top_y: float = leaf.get_meta("top_y"); var phase: float = leaf.get_meta("phase")
		var cycle = fmod(pulse * speed + phase, 1.0)
		leaf.position.y = lerpf(top_y, 0.19, cycle)
		leaf.position.x += sin(pulse * 1.7 + phase) * delta * 0.018
		leaf.rotation_degrees += Vector3(35.0, 58.0, 24.0) * delta
	for index in range(animated_grass_patches.size() - 1, -1, -1):
		var patch = animated_grass_patches[index]
		if not is_instance_valid(patch): animated_grass_patches.remove_at(index); continue
		var material: StandardMaterial3D = patch.material_override
		var base: Color = patch.get_meta("green_color"); var phase: float = patch.get_meta("phase")
		var yellow_amount = smoothstep(0.25, 0.82, sin(pulse * 0.42 + phase) * 0.5 + 0.5) * 0.46
		material.albedo_color = base.lerp(Color("#c4b84f"), yellow_amount)

func _ui_scale(viewport_size: Vector2) -> float:
	return clampf(minf(viewport_size.x / UI_DESIGN_SIZE.x, viewport_size.y / UI_DESIGN_SIZE.y), 0.35, 1.5)

func _ui_point(screen_point: Vector2) -> Vector2:
	return screen_point / _ui_scale(get_viewport().get_visible_rect().size)

func _ui_left_width(vp: Vector2) -> float:
	return clampf(vp.x * 0.18, 190.0, 226.0)

func _ui_right_width(vp: Vector2) -> float:
	return clampf(vp.x * 0.20, 220.0, 254.0)

func _ui_top_rect(vp: Vector2) -> Rect2:
	return Rect2(UI_MARGIN, UI_MARGIN, vp.x - UI_MARGIN * 2.0, UI_TOP_HEIGHT)

func _top_weather_rect(vp: Vector2) -> Rect2:
	var bar = _ui_top_rect(vp)
	return Rect2(bar.end.x - 205.0, bar.position.y + 7.0, 187.0, bar.size.y - 14.0)

func _ui_left_rect(vp: Vector2) -> Rect2:
	return Rect2(UI_MARGIN, UI_SIDE_TOP, _ui_left_width(vp), maxf(120.0, vp.y - UI_SIDE_TOP - UI_SIDE_BOTTOM))

func _ui_right_rect(vp: Vector2) -> Rect2:
	var width = _ui_right_width(vp)
	return Rect2(vp.x - UI_MARGIN - width, UI_SIDE_TOP, width, maxf(120.0, vp.y - UI_SIDE_TOP - UI_SIDE_BOTTOM))

func _ui_rail_rect(vp: Vector2) -> Rect2:
	return Rect2(UI_MARGIN, vp.y - UI_MARGIN - UI_RAIL_HEIGHT, vp.x - UI_MARGIN * 2.0, UI_RAIL_HEIGHT)

func _end_turn_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x - UI_MARGIN - 67.0, vp.y - UI_MARGIN - 67.0, 46.0, 46.0)

func _pointer_over_ui(pointer: Vector2, vp: Vector2) -> bool:
	return _ui_top_rect(vp).has_point(pointer) or _ui_left_rect(vp).has_point(pointer) or _ui_right_rect(vp).has_point(pointer) or _ui_rail_rect(vp).has_point(pointer)

func _history_capacity(vp: Vector2) -> int:
	var inner = _ui_right_rect(vp).grow(-20.0)
	var progress_top = inner.position.y + 48.0
	var ranking_top = progress_top + 43.0 + 31.0
	var history_top = ranking_top + player_count * 21.0 + 35.0
	return maxi(1, floori((inner.end.y - history_top - 2.0) / 25.0))

func _layout_glass_panels(vp: Vector2, interface_scale: float):
	if ui_glass_panels.size() != 4: return
	var rects = [_ui_top_rect(vp), _ui_left_rect(vp), _ui_right_rect(vp), _ui_rail_rect(vp)]
	for index in 4:
		var panel: ColorRect = ui_glass_panels[index]
		panel.position = rects[index].position * interface_scale
		panel.size = rects[index].size * interface_scale
		panel.visible = state != S.TITLE and state != S.GAME_OVER

func _input(event):
	if state == S.TITLE:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_1: player_count = 1; state = S.PLAY_CARDS; _start_game()
			elif event.keycode == KEY_2: player_count = 2; state = S.PLAY_CARDS; _start_game()
			elif event.keycode == KEY_3: player_count = 3; state = S.PLAY_CARDS; _start_game()
			elif event.keycode == KEY_4: player_count = 4; state = S.PLAY_CARDS; _start_game()
		if event is InputEventMouseMotion:
			var vp = get_viewport().get_visible_rect().size / _ui_scale(get_viewport().get_visible_rect().size)
			var pointer = _ui_point(event.position)
			title_hovered_player = -1
			for index in 4:
				if _title_player_button_rect(index, vp).has_point(pointer): title_hovered_player = index; break
			ui_ctrl.queue_redraw()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var vp = get_viewport().get_visible_rect().size / _ui_scale(get_viewport().get_visible_rect().size)
			var ui_pointer = _ui_point(event.position)
			for index in 4:
				if _title_player_button_rect(index, vp).has_point(ui_pointer):
					player_count = index + 1; state = S.PLAY_CARDS; _start_game(); return
		return

	# The history panel owns the wheel while hovered; elsewhere it controls zoom.
	if event is InputEventMouseButton:
		var ui_view = get_viewport().get_visible_rect().size / _ui_scale(get_viewport().get_visible_rect().size)
		var ui_pointer = _ui_point(event.position)
		if _ui_right_rect(ui_view).has_point(ui_pointer):
			var capacity = _history_capacity(ui_view)
			var max_scroll = maxi(0, action_history.size() - capacity)
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				history_scroll = maxi(0, history_scroll - 1); ui_ctrl.queue_redraw(); return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				history_scroll = mini(max_scroll, history_scroll + 1); ui_ctrl.queue_redraw(); return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom_target = clamp(cam_zoom_target * (1.0 + CAM_ZOOM_SPEED), CAM_ZOOM_MIN, CAM_ZOOM_MAX)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom_target = clamp(cam_zoom_target / (1.0 + CAM_ZOOM_SPEED), CAM_ZOOM_MIN, CAM_ZOOM_MAX)
			return

	# ---- Zoom: trackpad pinch (macOS MagnifyGesture) ----
	if event is InputEventMagnifyGesture:
		cam_zoom_target = clamp(cam_zoom_target * maxf(event.factor, 0.1), CAM_ZOOM_MIN, CAM_ZOOM_MAX)
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
			var right = camera.global_transform.basis.x; var forward = -camera.global_transform.basis.z
			var right_ground = Vector2(right.x, right.z).normalized()
			var forward_ground = Vector2(forward.x, forward.z).normalized()
			cam_offset_target = cam_pan_start - right_ground * delta_pos.x + forward_ground * delta_pos.y
			return
		var nc = _mouse_to_grid(event.position)
		var pointer = _ui_point(event.position)
		var ui_view = get_viewport().get_visible_rect().size / _ui_scale(get_viewport().get_visible_rect().size)
		hovered_card_index = _card_at_pointer(pointer, ui_view) if state == S.PLAY_CARDS and not dragging_card and not card_armed else -1
		hovered_deck_index = -1
		if not dragging_card and not card_armed:
			for deck_index in 3:
				if _deck_rect(deck_index, ui_view).has_point(pointer): hovered_deck_index = deck_index; break
		if dragging_card:
			drag_pointer = event.position
			_update_card_drag_preview(nc); ui_ctrl.queue_redraw(); return
		if road_drawing:
			_extend_road_drag(nc); _update_card_drag_preview(nc); ui_ctrl.queue_redraw(); return
		if card_armed:
			drag_pointer = event.position; _update_card_drag_preview(nc); ui_ctrl.queue_redraw(); return
		if _pointer_over_ui(pointer, ui_view):
			hover_mesh.visible = false; piece_preview_root.visible = false
			return
		if nc != hovered_cell:
			hovered_cell = nc
			if state == S.PLACE_TILE:
				hover_mesh.visible = false; _update_piece_preview()
			elif state == S.PLAY_CARDS and hovered_cell.x >= 0:
				hover_mesh.visible = true
				hover_mesh.position = _world(hovered_cell); hover_mesh.position.y = 0.52
				hover_material.albedo_color = Color(0.35, 1.0, 0.72, 0.30) if _can_play_selected_card(hovered_cell) else Color(1.0, 0.28, 0.24, 0.24)
			elif state == S.PLACE_SEED and hovered_cell.x >= 0:
				hover_mesh.visible = true
				hover_mesh.position = _world(hovered_cell); hover_mesh.position.y = 0.48
				var valid = _can_seed(hovered_cell)
				hover_material.albedo_color = Color(0.35, 1.0, 0.72, 0.38) if valid else Color(1.0, 0.28, 0.24, 0.28)
			else:
				hover_mesh.visible = false; piece_preview_root.visible = false

	# ---- Pan: trackpad two-finger scroll (PanGesture) ----
	if event is InputEventPanGesture:
		var right = camera.global_transform.basis.x; var forward = -camera.global_transform.basis.z
		var right_ground = Vector2(right.x, right.z).normalized()
		var forward_ground = Vector2(forward.x, forward.z).normalized()
		cam_offset_target += (-right_ground * event.delta.x + forward_ground * event.delta.y) * CAM_PAN_SPEED * 2.0 / cam_zoom
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if dragging_card: _release_hand_drag(event.position, _mouse_to_grid(event.position)); return
		if road_drawing: _finish_card_drag(_mouse_to_grid(event.position)); return

	if event is InputEventMouseButton and event.pressed:
		var ui_pointer = _ui_point(event.position)
		var ui_view = get_viewport().get_visible_rect().size / _ui_scale(get_viewport().get_visible_rect().size)
		if event.button_index == MOUSE_BUTTON_RIGHT and (card_armed or road_drawing or dragging_card):
			_cancel_armed_card(); return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _top_weather_rect(ui_view).has_point(ui_pointer):
				ui_preview_mode = "deck"; ui_preview_index = 2; ui_ctrl.queue_redraw(); return
			for deck_index in 3:
				if _deck_rect(deck_index, ui_view).has_point(ui_pointer):
					ui_preview_mode = "deck"; ui_preview_index = deck_index
					if state == S.DRAW_CARDS: _take_card_from_deck(deck_index)
					ui_ctrl.queue_redraw(); return
			if state == S.DRAW_CARDS:
				_warn_player("抽牌阶段请点击公共卡堆"); return
		if event.button_index == MOUSE_BUTTON_LEFT and state == S.PLAY_CARDS:
			if card_armed:
				if _pointer_over_ui(ui_pointer, ui_view): return
				if not _drag_card_index_is_valid(): _cancel_armed_card(); return
				var armed_card: Dictionary = current_hand[drag_card_index]
				if armed_card["kind"] == "road":
					road_drawing = true; road_drag_cells.clear(); _extend_road_drag(_mouse_to_grid(event.position)); return
				_finish_card_drag(_mouse_to_grid(event.position)); return
			var card_index = _card_at_pointer(ui_pointer, ui_view)
			if card_index >= 0: drag_pointer = event.position; _begin_card_drag(card_index); return
			if _end_turn_rect(ui_view).has_point(ui_pointer): _end_turn(); return
		if _pointer_over_ui(ui_pointer, ui_view): return
		var cell = _mouse_to_grid(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if state == S.PLAY_CARDS:
				_try_select_tile(cell)
			elif state == S.PLACE_TILE:
				if _place_piece(cell): _consume_market_tile(); state = S.PLACE_SEED; ui_ctrl.queue_redraw()
			elif state == S.PLACE_SEED:
				if _place_seed(cell): _end_turn()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if card_armed or road_drawing: _cancel_armed_card()
			elif state == S.PLAY_CARDS or state == S.PLACE_SEED: _end_turn()

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R: get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE and (card_armed or road_drawing or dragging_card): _cancel_armed_card()
		elif state == S.PLAY_CARDS and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			selected_card = clampi(event.keycode - KEY_1, 0, maxi(current_hand.size() - 1, 0))
			ui_preview_mode = "card"; ui_preview_index = selected_card; ui_ctrl.queue_redraw()
		elif state == S.PLAY_CARDS and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE):
			_end_turn()
		elif state == S.PLAY_CARDS and event.keycode == KEY_Q:
			piece_rotation = posmod(piece_rotation - 1, 4)
			if dragging_card or card_armed: _update_card_drag_preview(_mouse_to_grid(drag_pointer))
			_update_placement_highlights(); ui_ctrl.queue_redraw()
		elif state == S.PLAY_CARDS and event.keycode == KEY_E:
			piece_rotation = posmod(piece_rotation + 1, 4)
			if dragging_card or card_armed: _update_card_drag_preview(_mouse_to_grid(drag_pointer))
			_update_placement_highlights(); ui_ctrl.queue_redraw()
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
	var vp = screen_size / interface_scale
	_layout_glass_panels(vp, interface_scale)
	ui_ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * interface_scale)
	var ink = Color(0.08, 0.14, 0.13)
	var muted = Color(0.34, 0.42, 0.39)

	if state == S.TITLE: _draw_title(vp, font); return
	if state == S.GAME_OVER: _draw_gameover(vp, font); return

	for panel in [_ui_top_rect(vp), _ui_left_rect(vp), _ui_right_rect(vp), _ui_rail_rect(vp)]:
		ui_ctrl.draw_rect(panel, Color(1.0, 1.0, 1.0, 0.40), false, 1.0)
	_draw_top_info_bar(vp, font, ink, muted)
	_draw_context_preview_panel(vp, font, ink, muted)
	_draw_right_info_panel(vp, font, ink, muted)
	_draw_card_rail_labels(vp, font, muted)
	_draw_public_decks(vp, font, ink, muted)
	_draw_bottom_hand(vp, font, ink, muted, interface_scale)
	_draw_active_card_hint(vp, font)
	_draw_end_turn_button(vp, font)
	_draw_center_notices(vp, font)

func _draw_active_card_hint(vp: Vector2, font: Font):
	if not (dragging_card or card_armed or road_drawing) or not _drag_card_index_is_valid(): return
	var rail = _ui_rail_rect(vp); var card: Dictionary = current_hand[drag_card_index]
	var width = 410.0; var rect = Rect2(vp.x * 0.5 - width * 0.5, rail.position.y + 7.0, width, 24.0)
	var alpha = 0.42 + sin(pulse * 3.2) * 0.16
	ui_ctrl.draw_rect(rect, Color(0.16, 0.43, 0.34, alpha), true)
	ui_ctrl.draw_string(font, rect.position + Vector2(0, 17), "正在使用 %s   Esc或右键取消" % str(card["name"]), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 11, Color.WHITE)

func _draw_center_notices(vp: Vector2, font: Font):
	for notice_index in center_notices.size():
		var notice: Dictionary = center_notices[center_notices.size() - 1 - notice_index]
		var age = float(notice.get("age", 0.0))
		var fade = 1.0 - smoothstep(1.35, 2.4, age)
		var color = Color("#f1bd45") if str(notice.get("tone", "")) == "reward" else Color("#ef5148")
		color.a = fade
		var outline = Color(0.20, 0.10, 0.05, 0.72 * fade)
		var y = vp.y * 0.46 - age * 24.0 - notice_index * 34.0
		_draw_centered_outlined_text(str(notice.get("text", "")), Vector2(vp.x * 0.5, y), font, 21, color, outline, 5)

func _draw_context_preview_panel(vp: Vector2, font: Font, ink: Color, muted: Color):
	var panel = _ui_left_rect(vp); var inner = panel.grow(-18.0)
	var title = "卡牌预览"; var name = "暂无可预览内容"; var status = "点击牌库、卡牌或棋盘地块查看详情"
	var meta: Array = []
	var stage_height = minf(190.0, maxf(120.0, inner.size.y - 208.0))
	var stage = Rect2(inner.position + Vector2(0, 74), Vector2(inner.size.x, stage_height))
	var active_card_index = drag_card_index if (dragging_card or card_armed or road_drawing) and _drag_card_index_is_valid() else -1
	if active_card_index >= 0:
		var active_card: Dictionary = current_hand[active_card_index]
		title = "正在使用"; name = str(active_card["name"])
		_draw_card_context_stage(active_card, stage, font, ink, muted)
		meta = _card_preview_meta(active_card)
		status = "移动鼠标预览落点 · Esc或右键取消"
		var breath_alpha = 0.30 + sin(pulse * 3.2) * 0.16
		ui_ctrl.draw_rect(stage.grow(4.0), Color(0.28, 0.72, 0.55, breath_alpha), false, 2.5)
	elif ui_preview_mode == "deck":
		title = "牌库概率"; name = ["开发卡堆", "道路卡堆", "天气卡堆"][clampi(ui_preview_index, 0, 2)]
		_draw_deck_probability_preview(ui_preview_index, stage, font, ink, muted)
		meta = [["抽牌状态", "%d / %d" % [CARDS_DRAWN_PER_TURN - draws_remaining, CARDS_DRAWN_PER_TURN]], ["剩余次数", str(draws_remaining)]]
		status = "抽牌后按类别、等级自动整理"
	elif ui_preview_mode == "tile" and _in_bounds(selected_tile) and grid[selected_tile.x][selected_tile.y] >= 0:
		var terrain: int = grid[selected_tile.x][selected_tile.y]
		title = "地块属性"; name = TERRAIN_NAMES[terrain]
		_rebuild_selected_tile_preview(selected_tile)
		_draw_preview_texture(card_preview_viewport.get_texture(), stage)
		meta = _tile_preview_meta(selected_tile)
		status = _tile_preview_status(selected_tile)
	elif not current_hand.is_empty():
		ui_preview_index = clampi(ui_preview_index, 0, current_hand.size() - 1)
		var card: Dictionary = current_hand[ui_preview_index]
		title = _card_preview_title(card); name = str(card["name"])
		_draw_card_context_stage(card, stage, font, ink, muted)
		meta = _card_preview_meta(card)
		status = _card_preview_status(card)
	_draw_fitted_text(title, Rect2(inner.position, Vector2(inner.size.x, 18)), font, 11, muted)
	_draw_fitted_text(name, Rect2(inner.position + Vector2(0, 27), Vector2(inner.size.x, 28)), font, 18, ink)
	ui_ctrl.draw_line(Vector2(stage.position.x, stage.position.y - 8), Vector2(stage.end.x, stage.position.y - 8), Color(0.20, 0.30, 0.26, 0.18), 1.0)
	ui_ctrl.draw_line(Vector2(stage.position.x, stage.end.y + 4), Vector2(stage.end.x, stage.end.y + 4), Color(0.20, 0.30, 0.26, 0.18), 1.0)
	var meta_y = stage.end.y + 16.0
	for row in mini(meta.size(), 4):
		_draw_fitted_text(str(meta[row][0]), Rect2(inner.position.x, meta_y + row * 20.0, inner.size.x * 0.50, 18), font, 11, muted)
		_draw_fitted_text(str(meta[row][1]), Rect2(inner.position.x + inner.size.x * 0.50, meta_y + row * 20.0, inner.size.x * 0.50, 18), font, 11, ink)
	var status_y = minf(panel.end.y - 31.0, meta_y + mini(meta.size(), 4) * 20.0 + 8.0)
	ui_ctrl.draw_line(Vector2(inner.position.x, status_y - 8), Vector2(inner.end.x, status_y - 8), Color(0.20, 0.30, 0.26, 0.18), 1.0)
	_draw_fitted_text(status, Rect2(inner.position.x, status_y, inner.size.x, 20), font, 11, Color("#367052"))

func _draw_deck_probability_preview(deck_index: int, rect: Rect2, font: Font, ink: Color, muted: Color):
	var rows: Array
	match clampi(deck_index, 0, 2):
		0: rows = [["1级山体", 20.5, Color("#7f8783")], ["2级山体", 20.5, Color("#8f7b70")], ["3级山体", 20.5, Color("#a8795b")], ["4级山体", 20.5, Color("#bd7446")], ["建筑开发", 18.0, Color("#c7352e")]]
		1: rows = [["1级道路", 33.3, Color("#d7b64f")], ["2级道路", 33.3, Color("#ba9343")], ["3级道路", 33.4, Color("#8c6d35")]]
		_: rows = [["台风", 20.0, Color("#5b8eb2")], ["沙尘暴", 20.0, Color("#b8894c")], ["雨季", 20.0, Color("#65a9d8")], ["旱季", 20.0, Color("#d39a48")], ["彩虹", 20.0, Color("#7faa72")]]
	var row_h = minf(29.0, rect.size.y / maxf(float(rows.size()), 1.0))
	for index in rows.size():
		var row: Array = rows[index]; var y = rect.position.y + index * row_h + 5.0
		_draw_fitted_text(str(row[0]), Rect2(rect.position.x, y, 58, 18), font, 10, muted)
		var bar = Rect2(rect.position.x + 63, y + 5, maxf(18.0, rect.size.x - 97.0), 7)
		ui_ctrl.draw_rect(bar, Color(0.20, 0.30, 0.26, 0.12), true)
		ui_ctrl.draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(row[1]) / 100.0, bar.size.y)), row[2], true)
		_draw_fitted_text("%.1f%%" % float(row[1]), Rect2(rect.end.x - 31, y, 31, 18), font, 9, ink)

func _draw_card_context_stage(card: Dictionary, rect: Rect2, font: Font, ink: Color, muted: Color):
	ui_ctrl.draw_rect(rect, Color(0.24, 0.34, 0.29, 0.07), true)
	if card["kind"] == "develop" or card["kind"] == "building_develop":
		_rebuild_card_model_preview(card)
		_draw_preview_texture(card_preview_viewport.get_texture(), rect)
	else:
		_draw_card_model_icon(card, rect.get_center() + Vector2(0, -12), _card_accent(card).lightened(0.08), 1.28)
		_draw_fitted_text(_card_effect_text(card), Rect2(rect.position + Vector2(8, rect.size.y - 39), Vector2(rect.size.x - 16, 30)), font, 11, ink)

func _draw_preview_texture(texture: Texture2D, rect: Rect2):
	var texture_size = Vector2(texture.get_size())
	if texture_size.x <= 0.0 or texture_size.y <= 0.0: return
	var destination_aspect = rect.size.x / maxf(rect.size.y, 1.0)
	var texture_aspect = texture_size.x / texture_size.y
	var source = Rect2(Vector2.ZERO, texture_size)
	if texture_aspect > destination_aspect:
		source.size.x = texture_size.y * destination_aspect
		source.position.x = (texture_size.x - source.size.x) * 0.5
	else:
		source.size.y = texture_size.x / destination_aspect
		source.position.y = (texture_size.y - source.size.y) * 0.5
	ui_ctrl.draw_texture_rect_region(rect, texture, source)

func _card_preview_title(card: Dictionary) -> String:
	match card["kind"]:
		"develop": return "开发卡预览"
		"building_develop": return "建筑卡预览"
		"weather": return "天气效果预览"
		"road": return "道路卡预览"
	return "播种卡预览"

func _card_preview_meta(card: Dictionary) -> Array:
	match card["kind"]:
		"seed": return [["花朵数量", "%d朵" % (int(card["level"]) * 10)], ["目标", "植物地块"], ["容量检查", "需要"], ["玩家", PLAYER_NAMES[current_player]]]
		"develop":
			var roads_data: Array = card.get("rolled_roads", [])
			var segment_count := 0
			for mask in roads_data: segment_count += _count_mask_bits(int(mask))
			return [["形状", "%d格组合" % int(card["level"])], ["旋转", "%d°" % (piece_rotation * 90)], ["生成道路", "%d段" % (segment_count / 2)], ["落点要求", "相邻开发区"]]
		"building_develop": return [["占地", "1 × 2" if int(card["level"]) == 2 else "1 × 1"], ["建筑", "洪山科技大厦" if int(card["level"]) == 2 else "黄鹤楼"], ["旋转", "%d°" % (piece_rotation * 90)], ["目标", "完整缺口"]]
		"road": return [["路径长度", "%d格" % (int(card["level"]) + 1)], ["允许转弯", "是"], ["目标", "植物/增益地块"], ["建筑地块", "不可通过"]]
		"weather": return [["作用范围", "全棋盘"], ["持续时间", "%d回合" % (1 if card.get("weather", "") == "彩虹" else 3)], ["天气效果", _card_effect_text(card)], ["互斥天气", _weather_conflicts(str(card.get("weather", "")))]]
	return []

func _card_preview_status(card: Dictionary) -> String:
	match card["kind"]:
		"develop", "building_develop": return "拖出后显示真实地块并支持旋转放置"
		"road": return "拖出后在棋盘连续绘制道路"
		"weather": return "拖出界面即可使用，并立即改变环境"
	return "拖出界面后选择可播种的植物地块"

func _card_effect_text(card: Dictionary) -> String:
	if card["kind"] != "weather": return _card_description(card)
	match str(card.get("weather", "")):
		"台风": return "生长与扩散减半"
		"沙尘暴": return "生长与扩散减半"
		"雨季": return "植物升级概率翻倍"
		"旱季": return "植物降级，水域可能变草地"
		"彩虹": return "清除极端天气，生长翻倍"
	return "改变本轮环境"

func _weather_conflicts(weather: String) -> String:
	if weather == "旱季": return "雨季、台风"
	if weather == "雨季" or weather == "台风": return "旱季"
	if weather == "彩虹": return "清除全部"
	return "无"

func _count_mask_bits(mask: int) -> int:
	var count := 0
	for bit in 4:
		if (mask & (1 << bit)) != 0: count += 1
	return count

func _tile_preview_meta(pos: Vector2i) -> Array:
	var terrain: int = grid[pos.x][pos.y]; var road_text = _road_mask_text(roads[pos.x][pos.y])
	if _is_plant_terrain(terrain):
		var growth: float = TERRAIN_GROWTH[terrain]; var spread: float = TERRAIN_SPREAD[terrain]
		if _has_extreme_weather(): growth *= 0.5; spread *= 0.5
		if rainbow_turns > 0: growth *= 2.0; spread *= 2.0
		var flower_parts := []
		for player_id in player_count:
			if flowers[pos.x][pos.y][player_id] > 0: flower_parts.append("P%d:%d" % [player_id + 1, flowers[pos.x][pos.y][player_id]])
		return [["花朵/容量", "%d / %d" % [_flower_total(pos), _tile_capacity(pos)]], ["玩家花朵", "  ".join(flower_parts) if not flower_parts.is_empty() else "暂无"], ["生长/扩散", "%.2f / %.2f" % [growth, spread]], ["道路", road_text]]
	if terrain == T_WATER: return [["类型", "增益地块"], ["相邻增益", "升级概率翻倍"], ["旱季影响", "30%变为草地"], ["道路", road_text]]
	if terrain == T_BUILDING: return [["类型", "建筑地块"], ["相邻增益", "植物容积翻倍"], ["影响范围", "3 × 3"], ["道路", "不可修建"]]
	if terrain == T_MOUNTAIN: return [["类型", "非开发地块"], ["开发条件", "邻接已开发区"], ["覆盖", "不可覆盖缺口"], ["道路", "无"]]
	return [["类型", "封闭缺口"], ["形成条件", "被地块完全包围"], ["可用卡牌", "建筑开发卡"], ["道路", "无"]]

func _tile_preview_status(pos: Vector2i) -> String:
	var terrain: int = grid[pos.x][pos.y]
	if _is_plant_terrain(terrain): return "可播种 · 可修建道路"
	if terrain == T_WATER: return "增益地块 · 可修建道路"
	if terrain == T_GAP: return "可放置黄鹤楼或洪山科技大厦"
	if terrain == T_MOUNTAIN: return "可使用山体开发卡"
	return "建筑会提升相邻植物地块容量"

func _road_mask_text(mask: int) -> String:
	if mask == 0: return "无"
	var names := []
	for bit in 4:
		if (mask & (1 << bit)) != 0: names.append(["北", "东", "南", "西"][bit])
	return "".join(names) + "连通"

func _rebuild_selected_tile_preview(pos: Vector2i):
	var signature = "tile|%s|%d|%d" % [str(_logical_cell(pos)), grid[pos.x][pos.y], roads[pos.x][pos.y]]
	if signature == card_preview_signature: return
	card_preview_signature = signature
	for child in card_preview_root.get_children(): child.free()
	var terrain: int = grid[pos.x][pos.y]; var root = Node3D.new(); card_preview_root.add_child(root)
	if terrain != T_GAP: _spawn_island_base(root, terrain)
	match terrain:
		T_GRASS: _tile_grass_surface(root, roads[pos.x][pos.y])
		T_WATER: _tile_water_surface(root, roads[pos.x][pos.y])
		T_FOREST: _tile_forest_surface(root, roads[pos.x][pos.y])
		T_DESERT: _tile_desert_surface(root, roads[pos.x][pos.y])
		T_MOUNTAIN: _tile_mountain_surface(root)
		T_GAP: _tile_gap_surface(root)
		T_BUILDING:
			var building: Dictionary = special_buildings.get(_logical_cell(pos), {})
			if building.get("kind", "") == "hongshan_tech": _tile_hongshan_tech_surface(root, building)
			else: _tile_pavilion_surface(root, 0)
	_spawn_decor(terrain, root, roads[pos.x][pos.y])
	if roads[pos.x][pos.y] != 0 and terrain != T_BUILDING: _spawn_road(root, roads[pos.x][pos.y])
	card_preview_camera.size = 2.28 if terrain == T_BUILDING else 2.08
	var target = Vector3(0, 0.25, 0); card_preview_camera.look_at_from_position(target + Vector3(3.2, 3.4, 4.2), target)

func _rebuild_card_model_preview(card: Dictionary):
	var terrains: Array = pending_develop.get("terrains", card.get("rolled_terrains", []))
	var roads_data: Array = pending_develop.get("roads", card.get("rolled_roads", []))
	var signature = "%s|%s|%s|%d" % [str(card), str(terrains), str(roads_data), piece_rotation]
	if signature == card_preview_signature: return
	card_preview_signature = signature
	for child in card_preview_root.get_children(): child.free()
	var cells := []
	if card["kind"] == "develop":
		for offset in _development_shape_offsets(int(card["level"]), int(card.get("shape", 0))): cells.append(_rotate_cell(offset, piece_rotation))
	else:
		cells = [Vector2i.ZERO] if int(card["level"]) == 1 else [Vector2i.ZERO, DIRS[piece_rotation]]
		terrains = []
		for cell in cells: terrains.append(T_BUILDING)
	if cells.is_empty(): return
	var min_cell: Vector2i = cells[0]; var max_cell: Vector2i = cells[0]
	for cell in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y)); max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	var shape_center = Vector3(float(min_cell.x + max_cell.x) * TILE_SPACING * 0.5, 0, float(min_cell.y + max_cell.y) * TILE_SPACING * 0.5)
	for index in cells.size():
		var terrain: int = terrains[index] if index < terrains.size() else T_GRASS
		var tile_root = Node3D.new(); tile_root.position = Vector3(cells[index].x * TILE_SPACING, 0, cells[index].y * TILE_SPACING) - shape_center
		card_preview_root.add_child(tile_root)
		_spawn_exact_preview_tile(tile_root, terrain, card, index)
		if card["kind"] == "develop" and index < roads_data.size():
			var mask = _rotate_road_mask(int(roads_data[index]), piece_rotation)
			if mask != 0: _spawn_road(tile_root, mask)
	var span = maxi(max_cell.x - min_cell.x + 1, max_cell.y - min_cell.y + 1)
	card_preview_camera.size = 1.92 + maxf(0.0, float(span - 1)) * 0.82
	var target = Vector3(0, 0.25, 0)
	card_preview_camera.look_at_from_position(target + Vector3(3.2, 3.4, 4.2), target)

func _spawn_exact_preview_tile(root: Node3D, terrain: int, card: Dictionary, index: int):
	if terrain != T_GAP: _spawn_island_base(root, terrain)
	match terrain:
		T_GRASS: _tile_grass_surface(root, 0)
		T_WATER: _tile_water_surface(root, 0)
		T_FOREST: _tile_forest_surface(root, 0)
		T_DESERT: _tile_desert_surface(root, 0)
		T_MOUNTAIN: _tile_mountain_surface(root)
		T_GAP: _tile_gap_surface(root)
		T_BUILDING:
			if card.get("kind", "") == "building_develop" and int(card.get("level", 1)) == 2: _tile_hongshan_tech_surface(root, {"part": index, "direction": piece_rotation})
			else: _tile_pavilion_surface(root, 0)
	_spawn_decor(terrain, root, 0)

func _draw_top_info_bar(vp: Vector2, font: Font, ink: Color, muted: Color):
	var bar = _ui_top_rect(vp); var x = bar.position.x + 18.0; var center_y = bar.get_center().y
	_draw_fitted_text("花之江城", Rect2(x, center_y - 12.0, 78.0, 24.0), font, 17, ink)
	_draw_fitted_text("WUHAN IN BLOOM", Rect2(x + 82.0, center_y - 9.0, 112.0, 20.0), font, 11, muted)
	x += 225.0
	var terrain_types = [T_GRASS, T_WATER, T_FOREST, T_DESERT, T_BUILDING]
	var terrain_counts = _non_developable_terrain_counts()
	for i in terrain_types.size():
		_draw_top_terrain_model(Vector2(x + 13.0, center_y - 1.0), terrain_types[i])
		_draw_fitted_text("%s %d" % [TERRAIN_NAMES[terrain_types[i]], terrain_counts[i]], Rect2(x + 28.0, center_y - 9.0, 54.0, 20.0), font, 10, muted)
		x += 79.0
	var weather_text = "天气 晴朗"
	if not active_weather.is_empty() or rainbow_turns > 0:
		weather_text = "天气 "
		for weather in active_weather.keys(): weather_text += "%s %d回合  " % [weather, active_weather[weather]]
		if rainbow_turns > 0: weather_text += "彩虹 %d回合" % rainbow_turns
	var weather_rect = _top_weather_rect(vp)
	ui_ctrl.draw_rect(weather_rect, Color(0.36, 0.68, 0.84, 0.10), true)
	var weather_icon = Vector2(weather_rect.position.x + 20.0, center_y - 1.0)
	ui_ctrl.draw_circle(weather_icon + Vector2(-7, 2), 5.0, Color("#b9ddea"))
	ui_ctrl.draw_circle(weather_icon + Vector2(0, -2), 7.5, Color("#b9ddea"))
	ui_ctrl.draw_circle(weather_icon + Vector2(8, 2), 5.0, Color("#b9ddea"))
	ui_ctrl.draw_rect(Rect2(weather_icon + Vector2(-7, 1), Vector2(15, 6)), Color("#b9ddea"), true)
	_draw_fitted_text(weather_text.strip_edges(), Rect2(weather_rect.position.x + 42.0, center_y - 9.0, weather_rect.size.x - 48.0, 20.0), font, 11, Color("#37657a"))

func _non_developable_terrain_counts() -> Array:
	var count_tick = floori(pulse * 4.0)
	if count_tick == top_terrain_count_tick: return top_terrain_counts
	top_terrain_count_tick = count_tick
	top_terrain_counts = [0, 0, 0, 0, 0]
	for grid_x in _grid_width():
		for grid_y in _grid_height():
			var terrain: int = grid[grid_x][grid_y]
			if terrain >= T_GRASS and terrain <= T_BUILDING: top_terrain_counts[terrain] += 1
	return top_terrain_counts

func _draw_top_terrain_model(center: Vector2, terrain: int):
	_draw_iso_tile(center, TERRAIN_TOP[terrain].lightened(0.06), TERRAIN_MID[terrain], 11.0)
	match terrain:
		T_GRASS:
			ui_ctrl.draw_circle(center + Vector2(-3, -4), 2.8, Color("#397a3d")); ui_ctrl.draw_circle(center + Vector2(3, -3), 2.5, Color("#4f8f48"))
		T_WATER:
			ui_ctrl.draw_arc(center + Vector2(0, -1), 6.0, 0.15, PI - 0.15, 10, Color("#c5edf5"), 1.4)
		T_FOREST:
			ui_ctrl.draw_colored_polygon(PackedVector2Array([center + Vector2(-5, 1), center + Vector2(0, -11), center + Vector2(5, 1)]), Color("#286a43"))
		T_DESERT:
			ui_ctrl.draw_arc(center + Vector2(0, 1), 6.0, PI, TAU, 10, Color("#e5bb69"), 1.6)
		T_BUILDING:
			for tier in 3:
				var width = 12.0 - tier * 2.5; var y = center.y - tier * 4.0
				ui_ctrl.draw_rect(Rect2(center.x - width * 0.3, y - 2, width * 0.6, 3), Color("#b43b32"), true)
				ui_ctrl.draw_line(Vector2(center.x - width * 0.5, y), Vector2(center.x + width * 0.5, y), Color("#d99a26"), 1.5)

func _draw_right_info_panel(vp: Vector2, font: Font, ink: Color, muted: Color):
	var panel = _ui_right_rect(vp); var inner = panel.grow(-20.0); var pcol = PLAYER_COLORS[current_player]
	ui_ctrl.draw_rect(Rect2(inner.position, Vector2(8, 38)), pcol, true)
	_draw_fitted_text(PLAYER_NAMES[current_player], Rect2(inner.position + Vector2(17, 1), Vector2(105, 24)), font, 18, pcol.darkened(0.18))
	var phase = "抽牌 %d / %d" % [CARDS_DRAWN_PER_TURN - draws_remaining, CARDS_DRAWN_PER_TURN] if state == S.DRAW_CARDS else "出牌阶段"
	_draw_fitted_text(phase, Rect2(inner.position + Vector2(17, 24), Vector2(120, 18)), font, 11, muted)
	_draw_fitted_text("%02d" % (turns_played + 1), Rect2(inner.end.x - 42.0, inner.position.y + 3.0, 42.0, 28.0), font, 22, ink)
	var y = inner.position.y + 48.0
	ui_ctrl.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(0.20, 0.30, 0.26, 0.18), 1.0)
	_draw_fitted_text("守育进度", Rect2(inner.position.x, y + 9, 100, 18), font, 11, muted)
	_draw_fitted_text("%d / %d" % [turns_played + 1, total_turns], Rect2(inner.end.x - 64, y + 9, 64, 18), font, 11, muted)
	var progress = clampf(float(turns_played) / maxf(float(total_turns), 1.0), 0.0, 1.0)
	ui_ctrl.draw_rect(Rect2(inner.position.x, y + 30, inner.size.x, 7), Color(1.0, 1.0, 1.0, 0.44), true)
	ui_ctrl.draw_rect(Rect2(inner.position.x, y + 30, inner.size.x * progress, 7), pcol.darkened(0.16), true)
	y += 43.0
	ui_ctrl.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(0.20, 0.30, 0.26, 0.18), 1.0)
	_draw_fitted_text("花朵排名", Rect2(inner.position.x, y + 8, 100, 18), font, 11, muted)
	_draw_fitted_text("播种卡 %d" % seeds[current_player], Rect2(inner.end.x - 84, y + 8, 84, 18), font, 11, muted)
	var rank_top = y + 31.0; var maximum = maxf(float(scores.max()), 1.0)
	for player_id in player_count:
		var animated_rank_y: float = float(ranking_y.get(player_id, player_id * 30.0)) / 30.0 * 21.0
		var row_y: float = rank_top + animated_rank_y
		var amount: float = float(ranking_values.get(player_id, scores[player_id]))
		ui_ctrl.draw_circle(Vector2(inner.position.x + 4.0, row_y + 3.0), 3.5, PLAYER_COLORS[player_id])
		_draw_fitted_text(PLAYER_NAMES[player_id], Rect2(inner.position.x + 14, row_y - 5, 50, 18), font, 10, PLAYER_COLORS[player_id])
		var bar_x = inner.position.x + 69.0; var bar_w = maxf(20.0, inner.size.x - 99.0)
		ui_ctrl.draw_rect(Rect2(bar_x, row_y, bar_w, 5), Color(1.0, 1.0, 1.0, 0.42), true)
		ui_ctrl.draw_rect(Rect2(bar_x, row_y, bar_w * clampf(amount / maximum, 0.0, 1.0), 5), PLAYER_COLORS[player_id], true)
		_draw_fitted_text(str(roundi(amount)), Rect2(inner.end.x - 25, row_y - 6, 25, 18), font, 10, ink)
	y = rank_top + player_count * 21.0 + 5.0
	ui_ctrl.draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(0.20, 0.30, 0.26, 0.18), 1.0)
	_draw_fitted_text("操作历史", Rect2(inner.position.x, y + 8, 100, 18), font, 11, muted)
	_draw_fitted_text("全部%d条" % action_history.size(), Rect2(inner.end.x - 62, y + 8, 62, 18), font, 10, muted)
	var history_top = y + 30.0
	var capacity = maxi(0, floori((inner.end.y - history_top - 2.0) / 25.0))
	history_scroll = clampi(history_scroll, 0, maxi(0, action_history.size() - capacity))
	var visible_count = mini(maxi(0, action_history.size() - history_scroll), capacity)
	for slot in visible_count:
		var history_index = history_scroll + slot
		var tone = action_history_tones[history_index] if history_index < action_history_tones.size() else "info"
		var marker_color = Color("#d4463d") if tone == "warning" else (Color("#b47a16") if tone == "reward" else _player_text_color(action_history[history_index], muted))
		var text_color = _player_text_color(action_history[history_index], muted)
		ui_ctrl.draw_rect(Rect2(inner.position.x, history_top + slot * 25.0, 4, 19), marker_color, true)
		_draw_fitted_text(action_history[history_index], Rect2(inner.position.x + 12, history_top + slot * 25.0, inner.size.x - 17, 20), font, 10, text_color)
	if action_history.size() > capacity and capacity > 0:
		var track = Rect2(inner.end.x - 3.0, history_top, 2.0, capacity * 25.0 - 5.0)
		ui_ctrl.draw_rect(track, Color(0.20, 0.30, 0.26, 0.12), true)
		var thumb_h = maxf(12.0, track.size.y * float(capacity) / float(action_history.size()))
		var max_scroll = maxi(1, action_history.size() - capacity)
		var thumb_y = track.position.y + (track.size.y - thumb_h) * float(history_scroll) / float(max_scroll)
		ui_ctrl.draw_rect(Rect2(track.position.x, thumb_y, track.size.x, thumb_h), Color(0.20, 0.30, 0.26, 0.42), true)

func _draw_card_rail_labels(vp: Vector2, font: Font, muted: Color):
	var rail = _ui_rail_rect(vp)
	_draw_fitted_text("公共卡堆 · 抽牌 %d / %d" % [CARDS_DRAWN_PER_TURN - draws_remaining, CARDS_DRAWN_PER_TURN], Rect2(rail.position + Vector2(20, 10), Vector2(260, 18)), font, 11, muted)
	_draw_fitted_text("%s手牌 · %d张" % [PLAYER_NAMES[current_player], current_hand.size()], Rect2(rail.end.x - 170, rail.position.y + 10, 150, 18), font, 11, PLAYER_COLORS[current_player])
	ui_ctrl.draw_line(Vector2(rail.position.x + 300, rail.position.y + 28), Vector2(rail.position.x + 300, rail.end.y - 14), Color(0.20, 0.30, 0.26, 0.20), 1.0)

func _draw_end_turn_button(vp: Vector2, font: Font):
	var rect = _end_turn_rect(vp)
	ui_ctrl.draw_rect(Rect2(rect.position + Vector2(0, 5), rect.size), Color(0.03, 0.10, 0.08, 0.28), true)
	ui_ctrl.draw_rect(rect, Color("#18382f"), true)
	ui_ctrl.draw_string(font, rect.position + Vector2(0, 32), "✓", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 24, Color.WHITE)

func _draw_public_decks(vp: Vector2, font: Font, ink: Color, muted: Color):
	var cards = [
		{"kind": "develop", "name": "开发卡", "level": 3, "deck": "开发", "shape": 0},
		{"kind": "road", "name": "道路卡", "level": 2, "deck": "道路"},
		{"kind": "weather", "name": "天气卡", "level": 1, "deck": "天气", "weather": "雨季"},
	]
	for i in 3:
		var rect = _deck_rect(i, vp)
		if hovered_deck_index == i and state == S.DRAW_CARDS: rect.position.y -= 4.0
		for layer in range(2, 0, -1):
			ui_ctrl.draw_rect(Rect2(rect.position + Vector2(-layer * 3.0, -layer * 3.0), rect.size), Color(1.0, 1.0, 0.98, 0.90), true)
		_draw_card_component(cards[i], rect, font, ink, muted, ui_preview_mode == "deck" and ui_preview_index == i, 0.0, false)
		if state != S.DRAW_CARDS: ui_ctrl.draw_rect(rect.grow(-4.0), Color(0.20, 0.24, 0.22, 0.16), true)
		ui_ctrl.draw_string(font, Vector2(rect.position.x, rect.end.y + 18), ["开发", "道路", "天气"][i], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 10, ink if state == S.DRAW_CARDS else muted)

func _draw_bottom_hand(vp: Vector2, font: Font, ink: Color, muted: Color, interface_scale: float):
	var draw_order := []
	for i in current_hand.size():
		if card_armed and i == drag_card_index: continue
		if i != selected_card and i != hovered_card_index: draw_order.append(i)
	if hovered_card_index >= 0 and hovered_card_index < current_hand.size() and hovered_card_index != selected_card:
		draw_order.append(hovered_card_index)
	if selected_card >= 0 and selected_card < current_hand.size() and not (card_armed and selected_card == drag_card_index):
		draw_order.append(selected_card)
	for i in draw_order:
		var card: Dictionary = current_hand[i]
		var rect = _bottom_card_rect(i, current_hand.size(), vp)
		if dragging_card and i == drag_card_index:
			var pointer = _ui_point(drag_pointer)
			rect.position = pointer - rect.size * 0.5
		var scale = _hand_card_scale(i)
		var angle = _hand_card_angle(i)
		var center = rect.get_center()
		ui_ctrl.draw_set_transform(center * interface_scale, angle, Vector2.ONE * interface_scale * scale)
		_draw_hand_card_face(card, Rect2(-rect.size * 0.5, rect.size), font, ink, muted, i)
	ui_ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * interface_scale)

func _draw_hand_card_face(card: Dictionary, rect: Rect2, font: Font, ink: Color, muted: Color, index: int):
	var active = index == selected_card or index == hovered_card_index
	var depth = float(index) / maxf(float(current_hand.size() - 1), 1.0)
	_draw_card_component(card, rect, font, ink, muted, active, 0.0 if active else 0.04 + (1.0 - depth) * 0.08)

func _draw_card_component(card: Dictionary, rect: Rect2, font: Font, ink: Color, muted: Color, active: bool, depth_mask: float, show_details: bool = true):
	var base = _card_base_color(card)
	var accent = _card_accent(card)
	# 1. 投影
	var shadow_alpha = 0.28 if active else 0.18
	ui_ctrl.draw_rect(Rect2(rect.position + Vector2(5, 8), rect.size), Color(0, 0, 0, shadow_alpha), true)
	# 2. 四边边框
	var border_w = 4.0
	var border_color = accent.lerp(Color.WHITE, 0.20)
	ui_ctrl.draw_rect(rect, border_color, true)
	# 3. 内容区域（边框内部）
	var inner = Rect2(rect.position + Vector2(border_w, border_w), rect.size - Vector2(border_w * 2, border_w * 2))
	ui_ctrl.draw_rect(inner, Color(1.0, 1.0, 0.98, 0.96), true)
	# 4. 连续渐变：accent(顶) → 目标淡色(中) → 白(底)
	# 开发卡跳过灰色base，直接accent→皮肤色→白
	var fade_target := Color(1.0, 1.0, 0.97, 1.0)  # 默认白色
	var grad_start: Color = accent
	match card["kind"]:
		"develop", "building_develop":
			fade_target = Color("#f0d0b0")  # 皮肤色
			grad_start = accent.lerp(Color("#d4a070"), 0.3)  # 暖咖啡，不经过灰色
		"weather":
			fade_target = Color("#d0e4f4")  # 淡蓝色
	var rows = 24
	for row in rows:
		var t = float(row) / float(rows - 1)
		var band_color: Color
		if t < 0.45:
			band_color = grad_start.lerp(fade_target, t / 0.45)
		else:
			band_color = fade_target.lerp(Color(1.0, 1.0, 0.97, 1.0), (t - 0.45) / 0.55)
		var band_y = inner.position.y + inner.size.y * t
		var next_y = inner.position.y + inner.size.y * float(row + 1) / float(rows)
		ui_ctrl.draw_rect(Rect2(inner.position.x, band_y, inner.size.x, next_y - band_y + 1.0), band_color, true)
	# 5. 卡牌内容
	_draw_repeating_card_pattern(inner, card["kind"], base.darkened(0.08))
	_draw_card_model_icon(card, inner.get_center() + Vector2(0, -3), accent.lightened(0.08))
	if show_details:
		_draw_fitted_text(_card_description(card), Rect2(inner.position + Vector2(4, inner.size.y - 36), Vector2(inner.size.x - 8, 16)), font, 9, ink)
		_draw_fitted_text(card["deck"], Rect2(inner.position + Vector2(4, inner.size.y - 18), Vector2(inner.size.x - 8, 14)), font, 9, muted)
	_draw_fitted_text(card["name"], Rect2(inner.position + Vector2(5, 7), Vector2(inner.size.x - 10, 20)), font, 12, ink)
	# 6. 选中/深度遮罩
	if active:
		ui_ctrl.draw_rect(inner, Color(accent.r, accent.g, accent.b, 0.08), true)
	elif depth_mask > 0.0:
		ui_ctrl.draw_rect(inner, Color(0.03, 0.06, 0.05, depth_mask), true)
	# 7. 边框立体阴影：画在所有内容之上，边框向卡面内侧投射
	var sh = 6.0
	# 上边内阴影（向下投射）
	for s in int(sh):
		var a = 0.25 * (1.0 - float(s) / sh)
		ui_ctrl.draw_rect(Rect2(inner.position.x, inner.position.y + s, inner.size.x, 1.0), Color(0, 0, 0, a), true)
	# 左边内阴影（向右投射）
	for s in int(sh):
		var a = 0.20 * (1.0 - float(s) / sh)
		ui_ctrl.draw_rect(Rect2(inner.position.x + s, inner.position.y + sh, 1.0, inner.size.y - sh), Color(0, 0, 0, a), true)

func _draw_card_model_icon(card: Dictionary, center: Vector2, color: Color, preview_scale: float = 1.0):
	match card["kind"]:
		"seed": _draw_seed_card_flowers(center, int(card["level"]), preview_scale)
		"develop": _draw_develop_card_mountains(center, card)
		"building_develop": _draw_building_card_model(center, int(card["level"]))
		"weather": _draw_weather_card_forecast(center, str(card.get("weather", "")))
		_: _draw_card_symbol(card, center, color)

func _draw_seed_card_flowers(center: Vector2, level: int, preview_scale: float = 1.0):
	var count = clampi(level, 1, 5)
	for flower_index in count:
		var x = center.x + (flower_index - (count - 1) * 0.5) * 17.0 * preview_scale
		var y = center.y + absf(flower_index - (count - 1) * 0.5) * 3.0 * preview_scale
		var scale = (0.82 + float((flower_index + level) % 3) * 0.10) * preview_scale
		ui_ctrl.draw_line(Vector2(x, y + 23 * preview_scale), Vector2(x, y + 2 * preview_scale), Color("#397044"), 2.2 * preview_scale)
		_draw_card_flower_bloom(Vector2(x, y), current_player, scale, flower_index)

func _draw_card_flower_bloom(center: Vector2, owner: int, scale: float, variant: int):
	var flower_color = PLAYER_COLORS[owner]
	flower_color = flower_color.lightened(0.08) if variant % 2 == 0 else flower_color.darkened(0.08)
	match owner:
		0:
			for petal in 4:
				var angle = TAU * float(petal) / 4.0
				ui_ctrl.draw_circle(center + Vector2(cos(angle), sin(angle)) * 6.0 * scale, 4.5 * scale, flower_color)
		1:
			ui_ctrl.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-7, -5) * scale, center + Vector2(7, -5) * scale,
				center + Vector2(5, 7) * scale, center + Vector2(0, 11) * scale, center + Vector2(-5, 7) * scale
			]), flower_color)
		2:
			for petal in 7:
				var angle = TAU * float(petal) / 7.0
				ui_ctrl.draw_circle(center + Vector2(cos(angle), sin(angle)) * 6.5 * scale, 3.5 * scale, flower_color)
		3:
			for petal in 6:
				var angle = TAU * float(petal) / 6.0
				var direction = Vector2(cos(angle), sin(angle))
				ui_ctrl.draw_line(center + direction * 2.0 * scale, center + direction * 9.0 * scale, flower_color, 4.2 * scale)
	ui_ctrl.draw_circle(center, 3.0 * scale, Color("#f2c84b"))

func _draw_iso_tile(center: Vector2, top_color: Color, side_color: Color, size: float = 18.0):
	var top = PackedVector2Array([center + Vector2(0, -size * 0.52), center + Vector2(size, 0), center + Vector2(0, size * 0.52), center + Vector2(-size, 0)])
	ui_ctrl.draw_colored_polygon(top, top_color)
	ui_ctrl.draw_colored_polygon(PackedVector2Array([top[3], top[2], top[2] + Vector2(0, 6), top[3] + Vector2(0, 6)]), side_color.darkened(0.14))
	ui_ctrl.draw_colored_polygon(PackedVector2Array([top[2], top[1], top[1] + Vector2(0, 6), top[2] + Vector2(0, 6)]), side_color)

func _draw_develop_card_mountains(center: Vector2, card: Dictionary):
	var cells = _development_shape_offsets(int(card["level"]), int(card.get("shape", 0)))
	if cells.is_empty(): return
	var min_cell: Vector2i = cells[0]; var max_cell: Vector2i = cells[0]
	for cell in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y)); max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	var shape_center = Vector2(float(min_cell.x + max_cell.x), float(min_cell.y + max_cell.y)) * 0.5
	for cell in cells:
		var relative = Vector2(cell) - shape_center
		var tile_center = center + Vector2((relative.x - relative.y) * 17.0, (relative.x + relative.y) * 8.0 + 4.0)
		_draw_iso_tile(tile_center, TERRAIN_TOP[T_MOUNTAIN], TERRAIN_MID[T_MOUNTAIN], 15.0)
		ui_ctrl.draw_colored_polygon(PackedVector2Array([tile_center + Vector2(-9, 1), tile_center + Vector2(-1, -17), tile_center + Vector2(6, 1)]), TERRAIN_TOP[T_MOUNTAIN].lightened(0.10))
		ui_ctrl.draw_colored_polygon(PackedVector2Array([tile_center + Vector2(-1, -17), tile_center + Vector2(12, 2), tile_center + Vector2(6, 1)]), TERRAIN_TOP[T_MOUNTAIN].darkened(0.22))

func _draw_building_card_model(center: Vector2, level: int):
	if level <= 1:
		_draw_iso_tile(center + Vector2(0, 16), Color("#9d654d"), Color("#684638"), 25.0)
		for tier in 5:
			var width = 34.0 - tier * 4.8; var y = center.y + 9.0 - tier * 11.0
			ui_ctrl.draw_rect(Rect2(center.x - width * 0.33, y - 7, width * 0.66, 8), Color("#b43b32"), true)
			ui_ctrl.draw_colored_polygon(PackedVector2Array([Vector2(center.x - width * 0.58, y - 2), Vector2(center.x + width * 0.58, y - 2), Vector2(center.x + width * 0.40, y + 3), Vector2(center.x - width * 0.40, y + 3)]), Color("#d99a26"))
		ui_ctrl.draw_colored_polygon(PackedVector2Array([center + Vector2(-7, -43), center + Vector2(0, -54), center + Vector2(7, -43)]), Color("#d99a26"))
	else:
		_draw_iso_tile(center + Vector2(0, 17), Color("#f4f5f2"), Color("#b8c0c0"), 31.0)
		for side in [-1, 1]:
			var tower = Rect2(center + Vector2(side * 18 - 12, -37), Vector2(24, 49))
			ui_ctrl.draw_rect(tower, Color("#f5f6f3"), true)
			for floor_index in 6:
				ui_ctrl.draw_rect(Rect2(tower.position + Vector2(3, 4 + floor_index * 7), Vector2(18, 4)), Color("#5aa5bc").darkened(float(floor_index % 2) * 0.12), true)
		ui_ctrl.draw_rect(Rect2(center + Vector2(-18, -9), Vector2(36, 9)), Color("#76b8c8"), true)

func _draw_weather_card_forecast(center: Vector2, weather: String):
	match weather:
		"台风":
			for ring in 3: ui_ctrl.draw_arc(center, 10.0 + ring * 7.0, -2.5 + ring * 0.28, 2.1 + ring * 0.18, 20, Color.WHITE, 3.0)
			for drop in 4: ui_ctrl.draw_line(center + Vector2(-24 + drop * 15, 24), center + Vector2(-30 + drop * 15, 36), Color.WHITE, 3.0)
		"沙尘暴":
			for line_index in 4:
				var y = center.y - 19 + line_index * 13
				ui_ctrl.draw_arc(Vector2(center.x - 4 + line_index * 3, y), 23.0, -0.45, 0.65, 16, Color("#bd8845").lightened(line_index * 0.05), 4.0)
				ui_ctrl.draw_circle(Vector2(center.x + 27 - line_index * 4, y + 7), 2.5, Color("#d6aa65"))
		"雨季":
			_draw_weather_cloud(center + Vector2(0, -9), Color("#dceaf0"))
			for drop in 5: ui_ctrl.draw_line(center + Vector2(-25 + drop * 12, 12), center + Vector2(-29 + drop * 12, 27), Color("#4e9ed0"), 3.0)
		"旱季":
			ui_ctrl.draw_circle(center + Vector2(0, -14), 17, Color("#e6b34e"))
			for ray in 8:
				var direction = Vector2(cos(ray * TAU / 8.0), sin(ray * TAU / 8.0)); ui_ctrl.draw_line(center + Vector2(0, -14) + direction * 22, center + Vector2(0, -14) + direction * 29, Color("#d9963c"), 3.0)
			ui_ctrl.draw_polyline(PackedVector2Array([center + Vector2(-27, 26), center + Vector2(-10, 18), center + Vector2(-2, 30), center + Vector2(9, 19), center + Vector2(27, 27)]), Color("#875f42"), 3.0)
		"彩虹":
			var colors = [Color("#dd5149"), Color("#e5a645"), Color("#6fba65"), Color("#5799cf")]
			for band in colors.size(): ui_ctrl.draw_arc(center + Vector2(0, 20), 30.0 - band * 5.0, PI, TAU, 28, colors[band], 5.0)
		_:
			_draw_weather_cloud(center, Color("#dceaf0"))

func _draw_weather_cloud(center: Vector2, color: Color):
	ui_ctrl.draw_circle(center + Vector2(-16, 4), 12, color); ui_ctrl.draw_circle(center + Vector2(0, -4), 18, color); ui_ctrl.draw_circle(center + Vector2(18, 5), 12, color)
	ui_ctrl.draw_rect(Rect2(center + Vector2(-17, 3), Vector2(36, 13)), color, true)

func _draw_fitted_text(value: String, rect: Rect2, font: Font, size: int, color: Color):
	var fitted: String = value
	while size > 10 and font.get_string_size(fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > rect.size.x: size -= 1
	if font.get_string_size(fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > rect.size.x:
		while not fitted.is_empty() and font.get_string_size(fitted + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > rect.size.x:
			fitted = fitted.left(fitted.length() - 1)
		fitted += "..."
	ui_ctrl.draw_string(font, rect.position + Vector2(0, font.get_ascent(size)), fitted, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, size, color)

func _player_text_color(value: String, fallback: Color) -> Color:
	for player_id in player_count:
		if value.contains(PLAYER_NAMES[player_id]): return PLAYER_COLORS[player_id]
	return fallback

func _draw_card_symbol(card: Dictionary, center: Vector2, color: Color):
	match card["kind"]:
		"seed":
			ui_ctrl.draw_line(center + Vector2(0, 22), center + Vector2(0, -9), color.darkened(0.25), 4.0)
			ui_ctrl.draw_circle(center + Vector2(-9, -11), 10, color)
			ui_ctrl.draw_circle(center + Vector2(9, -16), 10, color.lightened(0.10))
		"develop", "building_develop":
			ui_ctrl.draw_line(center + Vector2(18, -26), center + Vector2(-13, 25), Color("#76563e"), 7.0)
			ui_ctrl.draw_line(center + Vector2(-26, 17), center + Vector2(4, 29), color.darkened(0.35), 11.0)
			var shape = _development_shape_offsets(int(card["level"]), int(card.get("shape", 0)))
			for cell in shape:
				ui_ctrl.draw_rect(Rect2(center + Vector2(21 + cell.x * 8, -24 + cell.y * 8), Vector2(7, 7)), color.darkened(0.32), true)
		"road":
			ui_ctrl.draw_line(center + Vector2(-27, -15), center + Vector2(27, 17), color.darkened(0.35), 13.0)
			ui_ctrl.draw_line(center + Vector2(-27, -15), center + Vector2(27, 17), color.lightened(0.30), 6.0)
		"weather":
			ui_ctrl.draw_circle(center + Vector2(-15, 4), 13, color.lightened(0.45))
			ui_ctrl.draw_circle(center + Vector2(1, -5), 18, color.lightened(0.45))
			ui_ctrl.draw_circle(center + Vector2(18, 5), 12, color.lightened(0.45))

func _draw_repeating_card_pattern(rect: Rect2, kind: String, color: Color):
	var pattern_color = color.lerp(Color.WHITE, 0.55)
	# 斜向排列：每行错开半格，覆盖整个卡面
	var spacing = 22.0
	var diag_x = 14.0  # 斜向x偏移
	var start_y = rect.position.y + 12.0
	var rows = maxi(1, floori((rect.size.y - 16) / spacing))
	var cols = maxi(1, floori(rect.size.x / diag_x)) + 2
	for row in rows:
		var offset_x = (row % 2) * (diag_x * 0.5)  # 奇数行错开半格
		for col in cols:
			var px = rect.position.x + offset_x + col * diag_x
			var py = start_y + row * spacing
			var p = Vector2(px, py)
			if not rect.grow(-4.0).has_point(p): continue
			match kind:
				"seed":
					ui_ctrl.draw_line(p + Vector2(0, 4), p + Vector2(0, -3), pattern_color, 0.9)
					ui_ctrl.draw_circle(p + Vector2(-2.5, -3.5), 2.0, pattern_color)
					ui_ctrl.draw_circle(p + Vector2(2.5, -4.5), 2.0, pattern_color)
				"develop", "building_develop":
					ui_ctrl.draw_line(p + Vector2(3, -4), p + Vector2(-2, 4), pattern_color, 1.2)
					ui_ctrl.draw_line(p + Vector2(-5, 2), p + Vector2(1, 5), pattern_color, 1.5)
				"road":
					ui_ctrl.draw_line(p + Vector2(-4, -2), p + Vector2(4, 2), pattern_color, 1.5)
					ui_ctrl.draw_line(p + Vector2(-3, -4), p + Vector2(-3, 3), pattern_color, 1.0)
					ui_ctrl.draw_line(p + Vector2(3, -1), p + Vector2(3, 5), pattern_color, 1.0)
				"weather":
					ui_ctrl.draw_circle(p + Vector2(-2.5, 0.5), 2.5, pattern_color)
					ui_ctrl.draw_circle(p + Vector2(1.5, -1.5), 3.5, pattern_color)
					ui_ctrl.draw_circle(p + Vector2(4, 0.5), 2.5, pattern_color)

func _draw_title(vp: Vector2, font: Font):
	_draw_title_mountain_field(vp)
	_draw_wuhan_river_lines(vp)
	ui_ctrl.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.05, 0.10, 0.09, 0.12), true)

	_draw_centered_outlined_text("花之江城", Vector2(vp.x * 0.5, vp.y * 0.22), font, 72, Color("#fff8e8"), Color("#254940"), 8)
	_draw_centered_outlined_text("W U H A N   I N   B L O O M", Vector2(vp.x * 0.5, vp.y * 0.22 + 57), font, 20, Color("#f3cf8d"), Color("#254940"), 4)

	for index in 4:
		_draw_title_player_tile(index, _title_player_button_rect(index, vp), font)

func _draw_centered_outlined_text(value: String, center: Vector2, font: Font, size: int, color: Color, outline: Color, outline_size: int):
	var text_size = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var baseline = center + Vector2(-text_size.x * 0.5, font.get_ascent(size) * 0.5)
	ui_ctrl.draw_string_outline(font, baseline, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size, outline)
	ui_ctrl.draw_string(font, baseline, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_title_mountain_field(vp: Vector2):
	ui_ctrl.draw_rect(Rect2(Vector2.ZERO, vp), Color("#9fc9bd"), true)
	var tile_w = 112.0; var tile_h = 54.0
	var rows = ceili(vp.y / (tile_h * 0.5)) + 3
	var columns = ceili(vp.x / tile_w) + 3
	for row in rows:
		for column in columns:
			var center = Vector2((column - 1) * tile_w + (row % 2) * tile_w * 0.5, row * tile_h * 0.5 - tile_h)
			var shade = float(posmod(row * 7 + column * 11, 5)) * 0.025
			var top_color = TERRAIN_TOP[T_MOUNTAIN].lightened(0.20 + shade)
			_draw_iso_tile(center, top_color, TERRAIN_MID[T_MOUNTAIN].lightened(0.08 + shade), tile_w * 0.5)
			var peak_height = 24.0 + float(posmod(row * 13 + column * 5, 4)) * 5.0
			var peak_x = center.x + float(posmod(row + column, 3) - 1) * 11.0
			ui_ctrl.draw_colored_polygon(PackedVector2Array([
				Vector2(peak_x - 28, center.y + 5), Vector2(peak_x, center.y - peak_height), Vector2(peak_x + 9, center.y + 5)
			]), top_color.lightened(0.08))
			ui_ctrl.draw_colored_polygon(PackedVector2Array([
				Vector2(peak_x, center.y - peak_height), Vector2(peak_x + 30, center.y + 5), Vector2(peak_x + 9, center.y + 5)
			]), top_color.darkened(0.22))
			ui_ctrl.draw_colored_polygon(PackedVector2Array([
				Vector2(peak_x - 6, center.y - peak_height + 7), Vector2(peak_x, center.y - peak_height), Vector2(peak_x + 6, center.y - peak_height + 9)
			]), Color("#dce5dd"))

func _draw_wuhan_river_lines(vp: Vector2):
	var yangtze = PackedVector2Array([
		Vector2(-40, vp.y * 0.47), Vector2(vp.x * 0.18, vp.y * 0.42), Vector2(vp.x * 0.39, vp.y * 0.50),
		Vector2(vp.x * 0.60, vp.y * 0.46), Vector2(vp.x * 0.82, vp.y * 0.54), Vector2(vp.x + 40, vp.y * 0.49)
	])
	var han = PackedVector2Array([
		Vector2(vp.x * 0.50, -30), Vector2(vp.x * 0.47, vp.y * 0.20), Vector2(vp.x * 0.53, vp.y * 0.34), Vector2(vp.x * 0.49, vp.y * 0.48)
	])
	ui_ctrl.draw_polyline(yangtze, Color(0.24, 0.62, 0.78, 0.54), 28.0, true)
	ui_ctrl.draw_polyline(yangtze, Color(0.56, 0.84, 0.91, 0.38), 12.0, true)
	ui_ctrl.draw_polyline(han, Color(0.24, 0.62, 0.78, 0.50), 20.0, true)
	ui_ctrl.draw_polyline(han, Color(0.56, 0.84, 0.91, 0.34), 8.0, true)

func _title_player_button_rect(index: int, vp: Vector2) -> Rect2:
	var gap = 16.0
	var tile_width = minf(132.0, maxf(68.0, (vp.x - 64.0 - gap * 3.0) / 4.0))
	var total_width = tile_width * 4.0 + gap * 3.0
	return Rect2(vp.x * 0.5 - total_width * 0.5 + index * (tile_width + gap), vp.y * 0.59, tile_width, 118.0)

func _draw_title_player_tile(index: int, rect: Rect2, font: Font):
	var terrain = [T_GRASS, T_WATER, T_FOREST, T_BUILDING][index]
	var hovered = index == title_hovered_player
	var center = Vector2(rect.get_center().x, rect.position.y + 42.0 - (8.0 if hovered else 0.0))
	var size = minf(48.0, rect.size.x * 0.38) * (1.08 if hovered else 1.0)
	ui_ctrl.draw_colored_polygon(PackedVector2Array([
		center + Vector2(-size, 8), center + Vector2(0, size * 0.56 + 8), center + Vector2(size, 8), center + Vector2(0, -size * 0.56 + 8)
	]), Color(0, 0, 0, 0.24))
	_draw_iso_tile(center, TERRAIN_TOP[terrain].lightened(0.08 if hovered else 0.0), TERRAIN_MID[terrain], size)
	match terrain:
		T_GRASS:
			for shrub in 3: ui_ctrl.draw_circle(center + Vector2(-18 + shrub * 18, -5 + abs(shrub - 1) * 5), 7, Color("#397a3d"))
		T_WATER:
			ui_ctrl.draw_arc(center, size * 0.42, 0.1, PI - 0.1, 18, Color("#a8e2ee"), 3.0)
			ui_ctrl.draw_arc(center + Vector2(0, 7), size * 0.28, 0.1, PI - 0.1, 14, Color("#d0f1f4"), 2.0)
		T_FOREST:
			for tree in 3:
				var tree_center = center + Vector2(-18 + tree * 18, -3 + abs(tree - 1) * 4)
				ui_ctrl.draw_rect(Rect2(tree_center + Vector2(-2, 1), Vector2(4, 15)), Color("#684326"), true)
				ui_ctrl.draw_colored_polygon(PackedVector2Array([tree_center + Vector2(-10, 4), tree_center + Vector2(0, -22), tree_center + Vector2(10, 4)]), Color("#286a43"))
		T_BUILDING:
			for tier in 4:
				var width = 45.0 - tier * 7.0; var y = center.y + 8.0 - tier * 10.0
				ui_ctrl.draw_rect(Rect2(center.x - width * 0.28, y - 6, width * 0.56, 7), Color("#b43b32"), true)
				ui_ctrl.draw_colored_polygon(PackedVector2Array([Vector2(center.x - width * 0.56, y), Vector2(center.x + width * 0.56, y), Vector2(center.x + width * 0.38, y + 4), Vector2(center.x - width * 0.38, y + 4)]), Color("#d99a26"))
	var label_color = PLAYER_COLORS[index].lightened(0.18) if hovered else Color("#fff8e8")
	_draw_centered_outlined_text("%d 人" % (index + 1), Vector2(rect.get_center().x, rect.position.y + 101), font, 19, label_color, Color("#254940"), 4)

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
		for x in _grid_width():
			for y in _grid_height():
				if plants[x][y] == i + 1: pc += 1
		ui_ctrl.draw_string(font, Vector2(cx - 20, py + 10), "%d 花" % scores[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.YELLOW if is_w else Color(0.8, 0.8, 0.8))
		ui_ctrl.draw_string(font, Vector2(cx + 90, py + 10), "占据%d格 · 最大%d格 · 路%d" % [diversity_counts[i], largest_groups[i], road_scores[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.5, 0.5, 0.5))
		if is_w: ui_ctrl.draw_string(font, Vector2(cx + 80, py + 32), "★ 胜利!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, PLAYER_COLORS[i].lightened(0.3))

	var blink = sin(pulse * 2.5) * 0.3 + 0.7
	ui_ctrl.draw_string(font, Vector2(cx - 75, vp.y * 0.88), "按 R 重新开始", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, blink))
