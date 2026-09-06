extends Control

signal start_requested(count: int)

const INK := Color("#284a41")
const MUTED := Color("#5e797d")
const TERRAIN_IDS := [0, 1, 2, 4]
const CHOICE_NAMES := ["独自栽培", "双人对弈", "三人同游", "四人争芳"]

var game: Node3D
var world: Node3D
var choices: Array[Button] = []
var previews: Array[SubViewport] = []
var heading: Label
var english: Label
var tagline: Label
var footer: Label
var music_button: Button
var veil: TextureRect
var elapsed := 0.0
var leaving := false
var pointer_offset := Vector2.ZERO
var scenery_tweens: Array[Tween] = []

class TerrainChoice extends Button:

	var preview: Texture2D
	var number := 1
	var caption := ""
	var accent := Color.WHITE
	var hover_amount := 0.0
	var age := 0.0

	func _process(delta: float):
		age += delta
		var target := 1.0 if (is_hovered() or has_focus()) and not disabled else 0.0
		hover_amount = lerpf(hover_amount, target, 1.0 - exp(-delta * 12.0))
		queue_redraw()

	func _draw():
		var image_size := minf(size.x + 12.0, size.y - 55.0)
		var lift := hover_amount * 12.0 + sin(age * 1.3 + number) * 2.0
		var center := Vector2(size.x * 0.5, size.y - 71.0)
		draw_set_transform(center, 0.0, Vector2(1.0, 0.20))
		draw_circle(Vector2.ZERO, image_size * 0.29, Color(0.12, 0.22, 0.22, 0.09 - hover_amount * 0.025))
		draw_set_transform(Vector2.ZERO)
		var zoom := 1.0 + hover_amount * 0.055
		var extent := Vector2.ONE * image_size * zoom
		var image_center := Vector2(size.x * 0.5, (size.y - 55.0) * 0.5 - lift)
		if preview: draw_texture_rect(preview, Rect2(image_center - extent * 0.5, extent), false)
		var font := get_theme_font("font")
		var label := "%d 人" % number
		var color := INK.lerp(accent, hover_amount * 0.8)
		var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 23).x
		draw_string(font, Vector2((size.x - label_width) * 0.5, size.y - 32.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, color)
		var caption_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, Vector2((size.x - caption_width) * 0.5, size.y - 11.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
		if hover_amount > 0.01:
			draw_line(Vector2(size.x * 0.5 - 14.0, size.y - 2.0), Vector2(size.x * 0.5 + 14.0, size.y - 2.0), Color(accent, hover_amount), 2.0, true)

func setup(host: Node3D):
	game = host
	name = "TitleScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var existing_tweens := get_tree().get_processed_tweens()
	_build_world()
	_build_interface()
	for tween in get_tree().get_processed_tweens():
		if not tween in existing_tweens: scenery_tweens.append(tween)
	resized.connect(_layout)
	_layout()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)

func _build_world():
	world = Node3D.new()
	world.name = "TitleLandscape"
	game.add_child(world)
	var noise := FastNoiseLite.new()
	noise.seed = 2026
	noise.frequency = 0.17
	noise.fractal_octaves = 2
	# Mesh resources are shared by the repeated scenery; gameplay keeps its own board.
	var prototypes: Dictionary = {}
	var nursery := Node3D.new()
	nursery.visible = false
	world.add_child(nursery)
	for terrain in [0, 1, 2, 4, 5]:
		var variants: Array[Node3D] = []
		for variant in 3:
			var tile := Node3D.new()
			nursery.add_child(tile)
			_build_tile(tile, terrain)
			var cap := BoxMesh.new()
			cap.size = Vector3(1.252, 0.045, 1.252)
			var surface := MeshInstance3D.new()
			surface.mesh = cap
			surface.position.y = 0.115 if terrain != 1 else 0.09
			if terrain == 1:
				var water := ShaderMaterial.new()
				water.shader = game.WATER_TILE_SHADER
				surface.material_override = water
			else:
				surface.material_override = game.edge_materials[terrain]
			tile.add_child(surface)
			variants.append(tile)
		prototypes[terrain] = variants
	for x in range(-9, 10):
		for z in range(-9, 10):
			var river := absf(float(z) - sin(float(x) * 0.36) * 2.1 + 0.7)
			var terrain := 5
			if river < 1.05: terrain = 1
			elif river < 2.2: terrain = 0
			elif noise.get_noise_2d(x, z) > 0.05: terrain = 2 if noise.get_noise_2d(x + 40, z) > 0.0 else 0
			if Vector2i(x, z) in [Vector2i(-4, 3), Vector2i(5, -2)]: terrain = 4
			var variants: Array = prototypes[terrain]
			var tile: Node3D = variants[posmod(x * 7 + z * 11, variants.size())].duplicate()
			world.add_child(tile)
			tile.position = Vector3(x * 1.25, 0.0, z * 1.25)
	var batches: Dictionary = {}
	for tile in world.get_children():
		if tile != nursery: _collect_scenery(tile, Transform3D.IDENTITY, batches)
	for batch in batches.values():
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = batch["mesh"]
		instances.instance_count = batch["transforms"].size()
		for index in instances.instance_count:
			instances.set_instance_transform(index, batch["transforms"][index])
		var renderer := MultiMeshInstance3D.new()
		renderer.multimesh = instances
		renderer.material_override = batch["material"]
		world.add_child(renderer)
	game.camera.keep_aspect = Camera3D.KEEP_HEIGHT

func _collect_scenery(node: Node3D, parent_transform: Transform3D, batches: Dictionary):
	var transform := parent_transform * node.transform
	for child in node.get_children():
		if child is Node3D: _collect_scenery(child, transform, batches)
	if node is MeshInstance3D and node.mesh:
		var material_id: int = node.material_override.get_instance_id() if node.material_override else 0
		var key := "%d:%d" % [node.mesh.get_instance_id(), material_id]
		if not batches.has(key):
			batches[key] = {"mesh": node.mesh, "material": node.material_override, "transforms": []}
		batches[key]["transforms"].append(transform)
		node.queue_free()

func _build_tile(root: Node3D, terrain: int):
	game._spawn_island_base(root, terrain)
	match terrain:
		0: game._tile_grass_surface(root, 0)
		1: game._tile_water_surface(root, 0)
		2: game._tile_forest_surface(root, 0)
		4: game._tile_pavilion_surface(root, 0)
		5: game._tile_mountain_surface(root)
	game._spawn_decor(terrain, root, 0)

func _build_interface():
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.27, 0.46, 0.61, 0.82, 1.0])
	gradient.colors = PackedColorArray([Color(0.94, 0.98, 1.0, 0.96), Color(0.94, 0.98, 1.0, 0.88), Color(0.94, 0.98, 1.0, 0.10), Color(0.94, 0.98, 1.0, 0.10), Color(0.96, 0.98, 0.98, 0.88), Color(0.96, 0.98, 0.98, 0.97)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 2; texture.height = 512
	texture.fill_from = Vector2(0.0, 0.0); texture.fill_to = Vector2(0.0, 1.0)
	veil = TextureRect.new(); veil.texture = texture
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	english = _label("HONGSHAN IN BLOOM", 15, MUTED)
	heading = _label("花满洪山", 96, INK)
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["KaiTi", "STKaiti", "Noto Serif CJK SC", "Source Han Serif SC", "serif"])
	heading.add_theme_font_override("font", title_font)
	heading.add_theme_color_override("font_outline_color", Color(0.98, 1.0, 1.0, 0.9))
	heading.add_theme_constant_override("outline_size", 4)
	tagline = _label("一城山水，四季花开", 16, MUTED)
	footer = _label("武汉 · 洪山     /     GGJ 2026", 12, MUTED)
	for index in 4:
		var viewport := _make_preview(TERRAIN_IDS[index])
		var button := TerrainChoice.new()
		button.name = "Start%dPlayers" % (index + 1)
		button.number = index + 1; button.caption = CHOICE_NAMES[index]
		button.accent = game.PLAYER_COLORS[index]
		button.preview = viewport.get_texture()
		button.tooltip_text = "开始%d人游戏" % (index + 1)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for style in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		add_child(button); choices.append(button)
		button.pressed.connect(_choose.bind(index + 1))
	music_button = Button.new()
	music_button.icon = preload("res://assets/ui/volume-2.svg")
	music_button.toggle_mode = true
	music_button.tooltip_text = "关闭音乐"
	music_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1.0, 1.0, 1.0, 0.65 if style != "normal" else 0.3)
		box.set_corner_radius_all(8)
		music_button.add_theme_stylebox_override(style, box)
	music_button.toggled.connect(_toggle_music)
	add_child(music_button)
	game.game_audio.settings_changed.connect(_sync_music_button)
	_sync_music_button()

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label

func _make_preview(terrain: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 320)
	viewport.transparent_bg = true; viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport); previews.append(viewport)
	var root := Node3D.new(); viewport.add_child(root)
	_build_tile(root, terrain)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0 if terrain != 4 else 2.25
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(3.2, 3.8, 4.2), Vector3(0.0, 0.12, 0.0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0); light.light_energy = 0.8
	viewport.add_child(light)
	var environment := WorldEnvironment.new()
	var ambient := Environment.new()
	ambient.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	ambient.ambient_light_color = Color("#e0edf0"); ambient.ambient_light_energy = 0.65
	environment.environment = ambient; viewport.add_child(environment)
	return viewport

func _layout():
	if not is_instance_valid(heading): return
	var compact := size.y < 540.0
	var narrow := size.x < 600.0
	var margin := 20.0 if narrow else 36.0
	var heading_size := 50 if compact else (64 if narrow else 96)
	heading.add_theme_font_size_override("font_size", heading_size)
	var title_top := size.y * (0.095 if compact else 0.13)
	english.position = Vector2(margin, title_top - 24.0)
	english.size = Vector2(size.x - margin * 2.0, 22.0)
	heading.position = Vector2(margin, title_top)
	heading.size = Vector2(size.x - margin * 2.0, heading_size + 30.0)
	tagline.position = Vector2(margin, heading.position.y + heading.size.y + 3.0)
	tagline.size = Vector2(size.x - margin * 2.0, 28.0)
	var row_width := minf(864.0, size.x - margin * 2.0)
	var height := minf(220.0, size.y * 0.31)
	var row_y := size.y - height - (42.0 if compact else 65.0)
	for index in choices.size():
		choices[index].position = Vector2((size.x - row_width) * 0.5 + row_width * index / 4.0, row_y)
		choices[index].size = Vector2(row_width / 4.0, height)
	footer.position = Vector2(margin, size.y - 33.0)
	footer.size = Vector2(size.x - margin * 2.0, 20.0)
	music_button.position = Vector2(size.x - margin - 40.0, 20.0)
	music_button.size = Vector2(40.0, 40.0)

func advance(delta: float):
	elapsed += delta
	var target := (get_local_mouse_position() / size.max(Vector2.ONE) - Vector2(0.5, 0.5)).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	pointer_offset = pointer_offset.lerp(target, 1.0 - exp(-delta * 2.0))
	var center := Vector3(pointer_offset.x * 0.24 + sin(elapsed * 0.10) * 0.12, 0.0, pointer_offset.y * 0.16)
	var camera: Camera3D = game.camera
	camera.size = minf(14.0, 26.0 / maxf(size.x / maxf(size.y, 1.0), 0.1))
	camera.rotation_degrees = Vector3(-42.0, 42.0, 0.0)
	camera.position = center + camera.basis.z * 28.0

func _unhandled_key_input(event: InputEvent):
	if leaving or not visible or not event.is_pressed() or event.is_echo(): return
	if event is InputEventKey and event.keycode >= KEY_1 and event.keycode <= KEY_4:
		_choose(event.keycode - KEY_1 + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		var focused := choices.find(get_viewport().gui_get_focus_owner())
		var step := -1 if event.is_action_pressed("ui_left") else 1
		choices[posmod((focused if focused >= 0 else 1) + step, 4)].grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and get_viewport().gui_get_focus_owner() == null:
		_choose(2)
		get_viewport().set_input_as_handled()

func _choose(count: int):
	if leaving: return
	leaving = true
	for choice in choices: choice.disabled = true
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.18)
	fade.tween_callback(func(): start_requested.emit(count))

func _toggle_music(muted: bool):
	game.game_audio.set_music_muted(muted)

func _sync_music_button():
	var muted: bool = game.game_audio.music_muted or game.game_audio.music_volume <= 0.0
	music_button.set_pressed_no_signal(muted)
	music_button.icon = preload("res://assets/ui/volume-x.svg") if muted else preload("res://assets/ui/volume-2.svg")
	music_button.tooltip_text = "开启音乐" if muted else "关闭音乐"

func release():
	set_process(false)
	set_process_input(false)
	for viewport in previews:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Stop repeating property animations before their model targets are removed.
	for tween in scenery_tweens:
		if tween.is_valid(): tween.kill()
	scenery_tweens.clear()
	if is_instance_valid(world):
		world.hide()
		world.queue_free()
	hide()
	queue_free()
