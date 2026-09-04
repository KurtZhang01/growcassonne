extends Node3D

# ---- Config ----
const GRID_SIZE := 9
const TILE_SPACING := 1.25
const TOTAL_TURNS := 30
const SPREAD_CHANCE := 0.45
const STARTING_SEEDS := 5
const SEEDS_PER_TURN := 1
const START_TILES := 7  # pre-placed tiles at game start

# ---- Terrain palette (Dorfromantik soft) ----
const TERRAIN_TOP := [
	Color(0.55, 0.86, 0.38),  # GRASS
	Color(0.32, 0.60, 0.92),  # WATER
	Color(0.18, 0.52, 0.22),  # FOREST
	Color(0.93, 0.82, 0.50),  # DESERT
]
const TERRAIN_MID := [
	Color(0.42, 0.68, 0.28),
	Color(0.22, 0.44, 0.75),
	Color(0.12, 0.36, 0.15),
	Color(0.78, 0.66, 0.38),
]
const TERRAIN_BOT := [
	Color(0.30, 0.48, 0.20),
	Color(0.15, 0.28, 0.52),
	Color(0.06, 0.20, 0.08),
	Color(0.55, 0.45, 0.25),
]
const TERRAIN_NAMES := ["草地", "水域", "森林", "荒漠"]

# ---- Player config ----
const PLAYER_COLORS := [
	Color(0.15, 0.95, 0.22),   # P1 green
	Color(0.30, 0.55, 1.00),   # P2 blue
	Color(1.00, 0.55, 0.15),   # P3 orange
	Color(0.78, 0.32, 0.95),   # P4 purple
]
const PLAYER_NAMES := ["玩家1", "玩家2", "玩家3", "玩家4"]

# ---- State ----
enum S { TITLE, PLACE_TILE, PLACE_SEED, GAME_OVER }

var grid := []; var plants := []; var plant_age := []
var tile_nodes := []; var plant_nodes := []; var decor_nodes := []
var current_tile := 0; var state := S.TITLE
var player_count := 2; var current_player := 0
var seeds := []; var total_turns := 0; var turns_played := 0
var scores := []; var group_counts := []
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
const CAM_BASE_SIZE := 18.0

# Nodes
var camera: Camera3D; var grid_root: Node3D; var plant_root: Node3D
var decor_root: Node3D; var hover_mesh: MeshInstance3D; var ui_ctrl: Control

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
	sun.light_energy = 1.3; sun.light_color = Color(1, 0.97, 0.90)
	sun.shadow_enabled = true; add_child(sun)

	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(30, 150, 0)
	fill.light_energy = 0.35; fill.light_color = Color(0.6, 0.7, 1.0)
	add_child(fill)

	var rim = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -120, 0)
	rim.light_energy = 0.2; rim.light_color = Color(1.0, 0.9, 0.7)
	add_child(rim)

	var env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.22, 0.24, 0.30)
	e.ambient_light_energy = 0.8
	e.glow_enabled = true; e.glow_intensity = 0.35; e.glow_bloom = 0.05
	env.environment = e; add_child(env)

	grid_root = Node3D.new(); add_child(grid_root)
	plant_root = Node3D.new(); add_child(plant_root)
	decor_root = Node3D.new(); add_child(decor_root)

	# Ground
	var ground = MeshInstance3D.new()
	var gp = PlaneMesh.new(); gp.size = Vector2(22, 22)
	ground.mesh = gp
	var gm = StandardMaterial3D.new(); gm.albedo_color = Color(0.04, 0.04, 0.07)
	ground.material_override = gm; ground.position = Vector3(5, -0.4, 5)
	add_child(ground)

	# Hover
	hover_mesh = MeshInstance3D.new()
	var hbox = BoxMesh.new(); hbox.size = Vector3(1.20, 0.03, 1.20)
	hover_mesh.mesh = hbox
	var hm = StandardMaterial3D.new()
	hm.albedo_color = Color(1, 1, 1, 0.15)
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.no_depth_test = true
	hover_mesh.material_override = hm; hover_mesh.visible = false
	add_child(hover_mesh)

	# UI
	ui_ctrl = Control.new()
	ui_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	var canvas = CanvasLayer.new(); canvas.layer = 10
	add_child(canvas); canvas.add_child(ui_ctrl)
	ui_ctrl.connect("draw", _draw_ui)

# ================================================================
#  GRID
# ================================================================
func _init_grid():
	for c in grid_root.get_children(): c.queue_free()
	for c in plant_root.get_children(): c.queue_free()
	for c in decor_root.get_children(): c.queue_free()
	grid = []; plants = []; plant_age = []
	tile_nodes = []; plant_nodes = []; decor_nodes = []
	for x in GRID_SIZE:
		grid.append([]); plants.append([]); plant_age.append([])
		tile_nodes.append([]); plant_nodes.append([]); decor_nodes.append([])
		for y in GRID_SIZE:
			grid[x].append(-1); plants[x].append(0); plant_age[x].append(0)
			tile_nodes[x].append(null); plant_nodes[x].append(null); decor_nodes[x].append(null)

func _world(pos: Vector2i) -> Vector3:
	var off = (GRID_SIZE - 1) * TILE_SPACING * 0.5
	return Vector3(pos.x * TILE_SPACING - off, 0, pos.y * TILE_SPACING - off)

func _pick_tile():
	current_tile = randi() % TERRAIN_TOP.size()
	state = S.PLACE_TILE

func _has_any() -> bool:
	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if grid[x][y] != -1: return true
	return false

func _can_place(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= GRID_SIZE or pos.y < 0 or pos.y >= GRID_SIZE: return false
	if grid[pos.x][pos.y] != -1: return false
	if not _has_any(): return true
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n = pos + d
		if n.x >= 0 and n.x < GRID_SIZE and n.y >= 0 and n.y < GRID_SIZE:
			if grid[n.x][n.y] != -1: return true
	return false

func _place_tile(pos: Vector2i, terr: int, animate: bool = true) -> bool:
	if not _can_place(pos): return false
	grid[pos.x][pos.y] = terr
	_spawn_tile(pos, terr, animate)
	return true

func _force_tile(pos: Vector2i, terr: int, animate: bool):
	grid[pos.x][pos.y] = terr
	_spawn_tile(pos, terr, animate)

# ================================================================
#  STARTING TILES — pre-generate a cross shape
# ================================================================
func _generate_start_tiles():
	var cx = GRID_SIZE / 2; var cy = GRID_SIZE / 2
	var center = Vector2i(cx, cy)
	_force_tile(center, randi() % 4, false)

	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	for d in dirs:
		var pos = center + d
		_force_tile(pos, randi() % 4, false)
	# Add some diagonals too
	for dx in [-1, 1]:
		for dy in [-1, 1]:
			if randf() < 0.6:
				_force_tile(center + Vector2i(dx, dy), randi() % 4, false)

# ================================================================
#  TILE MESH — rich 3D per terrain
# ================================================================
func _spawn_tile(pos: Vector2i, terr: int, animate: bool):
	var root = Node3D.new(); root.position = _world(pos)
	grid_root.add_child(root); tile_nodes[pos.x][pos.y] = root

	# --- Base slab (dark edge) ---
	var base = MeshInstance3D.new()
	var bm = BoxMesh.new(); bm.size = Vector3(1.06, 0.14, 1.06)
	base.mesh = bm
	var bmat = StandardMaterial3D.new(); bmat.albedo_color = TERRAIN_BOT[terr]
	base.material_override = bmat; base.position.y = -0.07
	root.add_child(base)

	# --- Mid layer ---
	var mid = MeshInstance3D.new()
	var mm = BoxMesh.new(); mm.size = Vector3(1.00, 0.10, 1.00)
	mid.mesh = mm
	var mmat = StandardMaterial3D.new(); mmat.albedo_color = TERRAIN_MID[terr]
	mid.material_override = mmat; mid.position.y = 0.05
	root.add_child(mid)

	# --- Top surface with terrain-specific shape ---
	match terr:
		0: _tile_grass_surface(root)
		1: _tile_water_surface(root)
		2: _tile_forest_surface(root)
		3: _tile_desert_surface(root)

	# --- Edge highlight ---
	var bevel = MeshInstance3D.new()
	var bvm = BoxMesh.new(); bvm.size = Vector3(1.08, 0.012, 1.08)
	bevel.mesh = bvm
	var bvmat = StandardMaterial3D.new()
	bvmat.albedo_color = TERRAIN_TOP[terr].lightened(0.3)
	bvmat.emission_enabled = true; bvmat.emission = TERRAIN_TOP[terr].lightened(0.1)
	bvmat.emission_energy_multiplier = 0.25
	bevel.material_override = bvmat; bevel.position.y = 0.16
	root.add_child(bevel)

	# --- Decorations ---
	_spawn_decor(terr, root)

	if animate:
		root.scale = Vector3(0.01, 0.01, 0.01)
		var tw = create_tween()
		tw.tween_property(root, "scale", Vector3(1, 1, 1), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

# ---- Grass: gentle rolling hills ----
func _tile_grass_surface(root: Node3D):
	# Main flat top
	var top = MeshInstance3D.new()
	var tm = BoxMesh.new(); tm.size = Vector3(0.95, 0.06, 0.95)
	top.mesh = tm
	var mat = StandardMaterial3D.new(); mat.albedo_color = TERRAIN_TOP[0]
	top.material_override = mat; top.position.y = 0.13
	root.add_child(top)

	# Small hill bumps
	for i in randi_range(2, 4):
		var bump = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = randf_range(0.08, 0.16); sm.height = sm.radius * 1.4
		bump.mesh = sm
		var bm2 = StandardMaterial3D.new()
		bm2.albedo_color = TERRAIN_TOP[0].lerp(Color(0.4, 0.75, 0.3), randf_range(0, 0.3))
		bump.material_override = bm2
		bump.position = Vector3(randf_range(-0.32, 0.32), 0.16, randf_range(-0.32, 0.32))
		bump.scale.y = randf_range(0.4, 0.7)
		root.add_child(bump)

# ---- Water: depressed pool with ripple rings ----
func _tile_water_surface(root: Node3D):
	# Water surface (slightly lower)
	var top = MeshInstance3D.new()
	var tm = BoxMesh.new(); tm.size = Vector3(0.92, 0.04, 0.92)
	top.mesh = tm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = TERRAIN_TOP[1]
	mat.metallic = 0.3; mat.roughness = 0.2
	top.material_override = mat; top.position.y = 0.10
	root.add_child(top)

	# Depth layer (darker center)
	var depth = MeshInstance3D.new()
	var dm = CylinderMesh.new(); dm.top_radius = 0.30; dm.bottom_radius = 0.30; dm.height = 0.02
	depth.mesh = dm
	var dmat = StandardMaterial3D.new()
	dmat.albedo_color = TERRAIN_BOT[1].lerp(TERRAIN_MID[1], 0.5)
	depth.material_override = dmat; depth.position.y = 0.09
	root.add_child(depth)

	# Ripple rings
	for i in randi_range(1, 3):
		var ripple = MeshInstance3D.new()
		var rm = TorusMesh.new()
		rm.inner_radius = 0.12 + i * 0.10; rm.outer_radius = rm.inner_radius + 0.02; rm.rings = 24
		ripple.mesh = rm
		var rmat = StandardMaterial3D.new()
		rmat.albedo_color = Color(0.5, 0.8, 1.0, 0.25 - i * 0.05)
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.emission_enabled = true; rmat.emission = Color(0.2, 0.5, 0.8)
		rmat.emission_energy_multiplier = 0.3
		ripple.material_override = rmat
		ripple.position = Vector3(randf_range(-0.15, 0.15), 0.13, randf_range(-0.15, 0.15))
		ripple.rotation_degrees.x = 90
		root.add_child(ripple)

	# Specular highlight
	var spec = MeshInstance3D.new()
	var sm = PlaneMesh.new(); sm.size = Vector2(0.25, 0.15)
	spec.mesh = sm
	var smat = StandardMaterial3D.new()
	smat.albedo_color = Color(0.8, 0.95, 1.0, 0.2)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.emission_enabled = true; smat.emission = Color(0.5, 0.8, 1.0)
	smat.emission_energy_multiplier = 0.4
	spec.material_override = smat
	spec.position = Vector3(randf_range(-0.15, 0.15), 0.14, randf_range(-0.15, 0.15))
	spec.rotation_degrees.x = -90
	root.add_child(spec)

# ---- Forest: raised terrain with visible tree trunks ----
func _tile_forest_surface(root: Node3D):
	# Raised earth mound
	var top = MeshInstance3D.new()
	var tm = CylinderMesh.new()
	tm.top_radius = 0.42; tm.bottom_radius = 0.48; tm.height = 0.10
	top.mesh = tm
	var mat = StandardMaterial3D.new(); mat.albedo_color = TERRAIN_MID[2]
	top.material_override = mat; top.position.y = 0.14
	root.add_child(top)

	# Moss layer on top
	var moss = MeshInstance3D.new()
	var mm2 = CylinderMesh.new()
	mm2.top_radius = 0.38; mm2.bottom_radius = 0.42; mm2.height = 0.04
	moss.mesh = mm2
	var mmat2 = StandardMaterial3D.new()
	mmat2.albedo_color = TERRAIN_TOP[2]
	moss.material_override = mmat2; moss.position.y = 0.20
	root.add_child(moss)

	# Stumps/logs
	for i in randi_range(1, 2):
		var stump = MeshInstance3D.new()
		var sm = CylinderMesh.new()
		sm.top_radius = randf_range(0.04, 0.07)
		sm.bottom_radius = sm.top_radius + 0.01
		sm.height = randf_range(0.08, 0.15)
		stump.mesh = sm
		var smat2 = StandardMaterial3D.new()
		smat2.albedo_color = Color(0.40, 0.28, 0.15).lerp(Color(0.55, 0.38, 0.22), randf())
		stump.material_override = smat2
		stump.position = Vector3(randf_range(-0.28, 0.28), 0.20, randf_range(-0.28, 0.28))
		root.add_child(stump)

# ---- Desert: flat with dune ridges ----
func _tile_desert_surface(root: Node3D):
	# Flat sand surface
	var top = MeshInstance3D.new()
	var tm = BoxMesh.new(); tm.size = Vector3(0.95, 0.05, 0.95)
	top.mesh = tm
	var mat = StandardMaterial3D.new(); mat.albedo_color = TERRAIN_TOP[3]
	top.material_override = mat; top.position.y = 0.13
	root.add_child(top)

	# Dune ridges (elongated boxes at angle)
	for i in randi_range(1, 3):
		var dune = MeshInstance3D.new()
		var dm = BoxMesh.new()
		var w = randf_range(0.12, 0.25)
		dm.size = Vector3(w, randf_range(0.03, 0.06), randf_range(0.35, 0.55))
		dune.mesh = dm
		var dmat2 = StandardMaterial3D.new()
		dmat2.albedo_color = TERRAIN_TOP[3].lerp(Color(0.85, 0.72, 0.40), randf_range(0, 0.4))
		dune.material_override = dmat2
		dune.position = Vector3(randf_range(-0.3, 0.3), 0.16, randf_range(-0.3, 0.3))
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
		shadow.position = Vector3(randf_range(-0.3, 0.3), 0.165, randf_range(-0.3, 0.3))
		shadow.rotation_degrees.x = -90; shadow.rotation_degrees.z = randf_range(0, 360)
		root.add_child(shadow)

# ================================================================
#  DECORATIONS
# ================================================================
func _spawn_decor(terr: int, parent: Node3D):
	var d = Node3D.new(); parent.add_child(d)
	match terr:
		0: _decor_grass(d)
		1: _decor_water(d)
		2: _decor_forest(d)
		3: _decor_desert(d)

func _decor_grass(p: Node3D):
	# Flowers
	for i in randi_range(2, 5):
		var flower = MeshInstance3D.new()
		# Stem
		var stem = MeshInstance3D.new()
		var stm = CylinderMesh.new(); stm.top_radius = 0.008; stm.bottom_radius = 0.01; stm.height = randf_range(0.06, 0.12)
		stem.mesh = stm
		var stmat = StandardMaterial3D.new(); stmat.albedo_color = Color(0.3, 0.65, 0.2)
		stem.material_override = stmat
		var sx = randf_range(-0.35, 0.35); var sz = randf_range(-0.35, 0.35)
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

func _decor_water(p: Node3D):
	# Lily pad
	var pad = MeshInstance3D.new()
	var pm2 = CylinderMesh.new(); pm2.top_radius = randf_range(0.08, 0.13); pm2.bottom_radius = pm2.top_radius; pm2.height = 0.012
	pad.mesh = pm2
	var pmat2 = StandardMaterial3D.new(); pmat2.albedo_color = Color(0.22, 0.65, 0.28)
	pad.material_override = pmat2
	pad.position = Vector3(randf_range(-0.25, 0.25), 0.12, randf_range(-0.25, 0.25))
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

func _decor_forest(p: Node3D):
	# Pine tree with trunk + 2-3 cone layers
	var trunk = MeshInstance3D.new()
	var tm = CylinderMesh.new(); tm.top_radius = 0.018; tm.bottom_radius = 0.028; tm.height = randf_range(0.18, 0.30)
	trunk.mesh = tm
	var tmat = StandardMaterial3D.new(); tmat.albedo_color = Color(0.42, 0.28, 0.14)
	trunk.material_override = tmat
	var tx = randf_range(-0.25, 0.25); var tz = randf_range(-0.25, 0.25)
	trunk.position = Vector3(tx, 0.20 + tm.height * 0.5, tz)
	p.add_child(trunk)
	for layer in randi_range(2, 3):
		var fol = MeshInstance3D.new()
		var fm = CylinderMesh.new()
		var lr = 0.16 - layer * 0.035
		fm.top_radius = 0.01; fm.bottom_radius = max(0.03, lr); fm.height = randf_range(0.10, 0.15)
		fol.mesh = fm
		var fmat = StandardMaterial3D.new()
		fmat.albedo_color = Color(0.14, 0.50, 0.18).lerp(Color(0.22, 0.68, 0.28), randf())
		fol.material_override = fmat
		fol.position = Vector3(tx, 0.20 + tm.height * 0.3 + layer * 0.09, tz)
		p.add_child(fol)

func _decor_desert(p: Node3D):
	# Rocks
	for i in randi_range(1, 3):
		var rock = MeshInstance3D.new()
		var rm = BoxMesh.new(); rm.size = Vector3(randf_range(0.06, 0.14), randf_range(0.04, 0.09), randf_range(0.06, 0.14))
		rock.mesh = rm
		var rmat = StandardMaterial3D.new()
		rmat.albedo_color = Color(0.62, 0.52, 0.35).lerp(Color(0.78, 0.68, 0.48), randf())
		rock.material_override = rmat
		rock.position = Vector3(randf_range(-0.3, 0.3), 0.18, randf_range(-0.3, 0.3))
		rock.rotation_degrees = Vector3(randf_range(-10, 10), randf_range(0, 360), randf_range(-10, 10))
		p.add_child(rock)
	# Cactus
	if randf() < 0.35:
		var cac = MeshInstance3D.new()
		var cm = CylinderMesh.new(); cm.top_radius = 0.02; cm.bottom_radius = 0.025; cm.height = randf_range(0.12, 0.20)
		cac.mesh = cm
		var cmat = StandardMaterial3D.new(); cmat.albedo_color = Color(0.28, 0.58, 0.22)
		cac.material_override = cmat
		cac.position = Vector3(randf_range(-0.2, 0.2), 0.18 + cm.height * 0.5, randf_range(-0.2, 0.2))
		p.add_child(cac)

# ================================================================
#  PLANT — per-player distinct 3D model
# ================================================================
func _place_seed(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= GRID_SIZE or pos.y < 0 or pos.y >= GRID_SIZE: return false
	if grid[pos.x][pos.y] == -1 or plants[pos.x][pos.y] != 0: return false
	if seeds[current_player] <= 0: return false
	plants[pos.x][pos.y] = current_player + 1
	plant_age[pos.x][pos.y] = 0; seeds[current_player] -= 1
	_spawn_plant(pos, current_player)
	flash_timer = 0.2; flash_color = PLAYER_COLORS[current_player]
	return true

func _spawn_plant(pos: Vector2i, pid: int):
	var root = Node3D.new()
	root.position = _world(pos); root.position.y = 0.18
	plant_root.add_child(root)
	plant_nodes[pos.x][pos.y] = root

	var col = PLAYER_COLORS[pid]
	# Player-specific plant shape
	match pid:
		0: _plant_mushroom(root, col)    # P1: mushroom
		1: _plant_flower(root, col)      # P2: flower bud
		2: _plant_crystal(root, col)     # P3: crystal
		3: _plant_star(root, col)        # P4: star

	root.scale = Vector3(0.01, 0.01, 0.01)
	var tw = create_tween()
	tw.tween_property(root, "scale", Vector3(1, 1, 1), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

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
func _start_game():
	_init_grid()
	current_player = 0; turns_played = 0
	total_turns = TOTAL_TURNS * player_count
	seeds = []; scores = []; group_counts = []
	for i in player_count:
		seeds.append(STARTING_SEEDS); scores.append(0); group_counts.append(0)
	_generate_start_tiles()
	_pick_tile(); ui_ctrl.queue_redraw()

func _end_turn():
	_do_grow()
	seeds[current_player] += SEEDS_PER_TURN
	turns_played += 1
	if turns_played >= total_turns:
		state = S.GAME_OVER; _calc_all_scores(); ui_ctrl.queue_redraw(); return
	current_player = (current_player + 1) % player_count
	_pick_tile(); ui_ctrl.queue_redraw()

func _do_grow():
	var new_p := []; var new_a := []
	for x in GRID_SIZE:
		new_p.append([]); new_a.append([])
		for y in GRID_SIZE:
			new_p[x].append(plants[x][y]); new_a[x].append(plant_age[x][y])

	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if plants[x][y] == current_player + 1:
				var t = grid[x][y]
				for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var nx = x + d.x; var ny = y + d.y
					if nx >= 0 and nx < GRID_SIZE and ny >= 0 and ny < GRID_SIZE:
						if grid[nx][ny] == t and plants[nx][ny] == 0:
							if randf() < SPREAD_CHANCE:
								new_p[nx][ny] = current_player + 1; new_a[nx][ny] = 0

	for x in GRID_SIZE:
		for y in GRID_SIZE:
			if new_p[x][y] != 0 and new_p[x][y] != plants[x][y]:
				plants[x][y] = new_p[x][y]; plant_age[x][y] = 0
				_spawn_plant(Vector2i(x, y), plants[x][y] - 1)
			elif plants[x][y] != 0:
				plant_age[x][y] = new_a[x][y] + 1
				if plant_nodes[x][y] != null:
					var s = min(1.0, plant_age[x][y] * 0.10)
					var tw = create_tween()
					tw.tween_property(plant_nodes[x][y], "scale", Vector3(s, s, s), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SPRING)

func _calc_all_scores():
	for pid in player_count:
		var count := 0
		for x in GRID_SIZE:
			for y in GRID_SIZE:
				if plants[x][y] == pid + 1: count += 1
		var vis := []
		for x in GRID_SIZE:
			vis.append([])
			for y in GRID_SIZE: vis[x].append(false)
		var groups := 0
		for x in GRID_SIZE:
			for y in GRID_SIZE:
				if plants[x][y] == pid + 1 and not vis[x][y]:
					groups += 1; _flood_p(x, y, vis, pid + 1)
		scores[pid] = count + groups * 5; group_counts[pid] = groups

func _flood_p(x: int, y: int, v: Array, pid: int):
	if x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE: return
	if v[x][y] or plants[x][y] != pid: return
	v[x][y] = true
	_flood_p(x+1,y,v,pid); _flood_p(x-1,y,v,pid)
	_flood_p(x,y+1,v,pid); _flood_p(x,y-1,v,pid)

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

# ================================================================
#  LOOP
# ================================================================
func _process(delta):
	pulse += delta
	if flash_timer > 0: flash_timer = max(0, flash_timer - delta * 2.5)

	# Smooth zoom interpolation
	cam_zoom = lerp(cam_zoom, cam_zoom_target, delta * 10.0)
	camera.size = CAM_BASE_SIZE / cam_zoom

	# Smooth pan interpolation
	cam_offset = cam_offset.lerp(cam_offset_target, delta * 10.0)
	var base_pos = Vector3(8, 16, 12)
	# Convert 2D offset to 3D (isometric axes)
	camera.position = base_pos + Vector3(cam_offset.x, 0, cam_offset.y)

	ui_ctrl.queue_redraw()

func _input(event):
	if state == S.TITLE:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_2: player_count = 2; state = S.PLACE_TILE; _start_game()
			elif event.keycode == KEY_3: player_count = 3; state = S.PLACE_TILE; _start_game()
			elif event.keycode == KEY_4: player_count = 4; state = S.PLACE_TILE; _start_game()
		if event is InputEventMouseButton and event.pressed:
			player_count = 2; state = S.PLACE_TILE; _start_game()
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
			if hovered_cell.x >= 0:
				hover_mesh.visible = true
				hover_mesh.position = _world(hovered_cell); hover_mesh.position.y = 0.01
			else: hover_mesh.visible = false

	# ---- Pan: trackpad two-finger scroll (PanGesture) ----
	if event is InputEventPanGesture:
		cam_offset_target += Vector2(-event.delta.x, -event.delta.y) * CAM_PAN_SPEED * 2.0 / cam_zoom
		return

	if event is InputEventMouseButton and event.pressed:
		var cell = _mouse_to_grid(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if state == S.PLACE_TILE:
				if _place_tile(cell, current_tile, true): state = S.PLACE_SEED; ui_ctrl.queue_redraw()
			elif state == S.PLACE_SEED:
				if _place_seed(cell): _end_turn()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if state == S.PLACE_SEED: _end_turn()

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R: get_tree().reload_current_scene()
		# Reset camera with C key
		elif event.keycode == KEY_C:
			cam_zoom_target = 1.0; cam_offset_target = Vector2.ZERO

# ================================================================
#  UI
# ================================================================
func _draw_ui():
	var font = ThemeDB.fallback_font
	var vp = get_viewport().get_visible_rect().size
	var ux = vp.x - 320.0; var uy = 30.0

	ui_ctrl.draw_rect(Rect2(ux - 15, uy - 10, 305, vp.y - 40), Color(0, 0, 0, 0.50), 0, true, 10.0)

	if state == S.TITLE: _draw_title(vp, font); return
	if state == S.GAME_OVER: _draw_gameover(vp, font); return

	var pcol = PLAYER_COLORS[current_player]
	ui_ctrl.draw_rect(Rect2(ux, uy, 270, 42), pcol.darkened(0.6), 0, true, 8.0)
	var st := "放置地形" if state == S.PLACE_TILE else "放置种子"
	ui_ctrl.draw_string(font, Vector2(ux + 16, uy + 18), PLAYER_NAMES[current_player], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, pcol.lightened(0.5))
	ui_ctrl.draw_string(font, Vector2(ux + 90, uy + 18), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)

	var sy = uy + 70
	ui_ctrl.draw_string(font, Vector2(ux + 12, sy), "回合", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.45, 0.45))
	ui_ctrl.draw_string(font, Vector2(ux + 12, sy + 22), "%d / %d" % [turns_played + 1, total_turns], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.9, 0.9))
	var bp = float(turns_played) / total_turns
	ui_ctrl.draw_rect(Rect2(ux + 12, sy + 32, 246, 7), Color(0.12, 0.12, 0.12), 0, true, 4.0)
	ui_ctrl.draw_rect(Rect2(ux + 12, sy + 32, 246 * bp, 7), pcol.darkened(0.2), 0, true, 4.0)

	ui_ctrl.draw_string(font, Vector2(ux + 12, sy + 60), "种子", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.45, 0.45))
	ui_ctrl.draw_string(font, Vector2(ux + 12, sy + 82), str(seeds[current_player]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.9, 0.9))
	ui_ctrl.draw_string(font, Vector2(ux + 120, sy + 60), "得分", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.45, 0.45))
	for i in player_count:
		ui_ctrl.draw_circle(Vector2(ux + 125, sy + 80 + i * 22 - 3), 5, PLAYER_COLORS[i])
		ui_ctrl.draw_string(font, Vector2(ux + 136, sy + 80 + i * 22), PLAYER_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, PLAYER_COLORS[i].lightened(0.3))

	var iy = sy + 180
	if state == S.PLACE_TILE:
		ui_ctrl.draw_string(font, Vector2(ux + 12, iy), "当前地形", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.45, 0.45))
		ui_ctrl.draw_rect(Rect2(ux + 12, iy + 8, 50, 50), TERRAIN_TOP[current_tile], 0, true, 8.0)
		ui_ctrl.draw_string(font, Vector2(ux + 72, iy + 40), TERRAIN_NAMES[current_tile], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.85, 0.85))
	elif state == S.PLACE_SEED:
		ui_ctrl.draw_string(font, Vector2(ux + 12, iy), "操作", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 0.45, 0.45))
		ui_ctrl.draw_string(font, Vector2(ux + 12, iy + 22), "左键 → 放种子", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.5, 1, 0.5))
		ui_ctrl.draw_string(font, Vector2(ux + 12, iy + 44), "右键 → 直接生长", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 0.6, 0.6))

	var ly = vp.y - 200.0
	ui_ctrl.draw_string(font, Vector2(ux + 12, ly), "地形", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.4, 0.4))
	for i in TERRAIN_TOP.size():
		ui_ctrl.draw_rect(Rect2(ux + 12, ly + 14 + i * 24, 14, 14), TERRAIN_TOP[i], 0, true, 4.0)
		ui_ctrl.draw_string(font, Vector2(ux + 32, ly + 26 + i * 24), TERRAIN_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.55, 0.55))
	ui_ctrl.draw_string(font, Vector2(ux + 120, ly), "玩家", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.4, 0.4))
	for i in player_count:
		ui_ctrl.draw_circle(Vector2(ux + 128, ly + 20 + i * 24), 6, PLAYER_COLORS[i])
		ui_ctrl.draw_string(font, Vector2(ux + 140, ly + 26 + i * 24), PLAYER_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PLAYER_COLORS[i].lightened(0.2))
	ui_ctrl.draw_string(font, Vector2(ux + 12, vp.y - 80), "滚轮/双指 = 缩放", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.3, 0.3))
	ui_ctrl.draw_string(font, Vector2(ux + 12, vp.y - 62), "中键拖拽/双指滑动 = 平移", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.3, 0.3))
	ui_ctrl.draw_string(font, Vector2(ux + 12, vp.y - 44), "C = 重置视角  R = 重新开始", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.3, 0.3))

func _draw_title(vp: Vector2, font: Font):
	ui_ctrl.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.75))
	for i in 12:
		var a = pulse * 0.2 + i * 0.524
		var c = PLAYER_COLORS[i % 4]; c.a = 0.12 + sin(pulse + i) * 0.05
		ui_ctrl.draw_circle(Vector2(vp.x * 0.5 + cos(a) * 320, vp.y * 0.32 + sin(a * 0.7) * 130), 32 + sin(pulse + i) * 12, c)

	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 140, vp.y * 0.22), "蔓  延", HORIZONTAL_ALIGNMENT_LEFT, -1, 90, Color.WHITE)
	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 170, vp.y * 0.22 + 68), "G R O W  C A S S O N N E", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.45, 0.78, 0.45))
	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 100, vp.y * 0.22 + 108), "卡卡颂 × GROW  多人对战", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.4, 0.4, 0.4))

	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 120, vp.y * 0.48), "选择玩家人数:", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.85, 0.85, 0.85))
	for i in 3:
		var np = i + 2
		var bx = vp.x * 0.5 - 110 + i * 130.0; var by = vp.y * 0.53
		ui_ctrl.draw_rect(Rect2(bx, by, 100, 50), PLAYER_COLORS[np - 2].darkened(0.5), 0, true, 10.0)
		ui_ctrl.draw_string(font, Vector2(bx + 25, by + 34), "%d 人" % np, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, PLAYER_COLORS[np - 2])

	var blink = sin(pulse * 2.2) * 0.3 + 0.7
	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 140, vp.y * 0.64), "按 2 / 3 / 4 或点击选择人数", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, blink))

	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 130, vp.y * 0.75), "每人轮流: 放地形 → 播种 → 生长", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.45, 0.45, 0.45))
	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 140, vp.y * 0.79), "你的植物会蔓延到同类地形，连片越大分越高", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.40, 0.40, 0.40))
	ui_ctrl.draw_string(font, Vector2(vp.x * 0.5 - 90, vp.y * 0.90), "GGJ 2025  ·  GROW Theme", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.22, 0.22, 0.22))

func _draw_gameover(vp: Vector2, font: Font):
	ui_ctrl.draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.85))
	var cx = vp.x * 0.5
	ui_ctrl.draw_string(font, Vector2(cx - 130, vp.y * 0.12), "游戏结束", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color.WHITE)

	var max_s = 0; var winner = 0
	for i in player_count:
		if scores[i] > max_s: max_s = scores[i]; winner = i

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
		ui_ctrl.draw_string(font, Vector2(cx - 20, py + 10), "%d 分" % scores[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.YELLOW if is_w else Color(0.8, 0.8, 0.8))
		ui_ctrl.draw_string(font, Vector2(cx + 80, py + 10), "(%d格 %d组)" % [pc, group_counts[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.5, 0.5, 0.5))
		if is_w: ui_ctrl.draw_string(font, Vector2(cx + 80, py + 32), "★ 胜利!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, PLAYER_COLORS[i].lightened(0.3))

	var blink = sin(pulse * 2.5) * 0.3 + 0.7
	ui_ctrl.draw_string(font, Vector2(cx - 75, vp.y * 0.88), "按 R 重新开始", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, blink))
