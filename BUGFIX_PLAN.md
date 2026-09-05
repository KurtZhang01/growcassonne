# GrowCassonne Bug修复与交互优化方案 v2

---

## 问题1：地块边框与底座未完全融合

### 现象
- 边框（edge trim）与底座（island base）之间有空隙，不是一体的
- 不同地块之间的边框下方底座没有融合，中间有可见空档
- 道路边缘与地块之间也有空档

### 原因分析
- `_spawn_edge_trim()` 的 trim 位置 y=0.172，而底座上层 y=0.155，trim 悬浮在底座之上
- trim 宽度 0.035 太窄，无法覆盖底座侧面
- 道路面高度 y=0.285，与地块表面 y≈0.16 之间有明显缝隙

### 修复方案

**边框与底座融合**：
```gdscript
# _spawn_edge_trim() 修改：trim 应覆盖底座侧边，从底座顶部到地面
func _spawn_edge_trim(root: Node3D, terr: int, pos: Vector2i):
    var trim_material = StandardMaterial3D.new()
    trim_material.albedo_color = TERRAIN_TOP[terr].lightened(0.08)
    trim_material.roughness = 0.76
    for side in 4:
        # 只在不同地形之间显示边框
        var neighbor = pos + DIRS[side]
        if _in_bounds(neighbor) and grid[neighbor.x][neighbor.y] == terr:
            continue
        var horizontal = side < 2
        var trim = MeshInstance3D.new(); var mesh = BoxMesh.new()
        # 边框从地面延伸到底座顶部，覆盖整个侧面
        mesh.size = Vector3(
            1.10 if horizontal else 0.04,
            0.18,  # 从 y=0 到 y=0.18，覆盖整个底座高度
            0.04 if horizontal else 1.10
        )
        trim.mesh = mesh; trim.material_override = trim_material
        if horizontal:
            trim.position = Vector3(0, 0.09, -0.53 if side == 0 else 0.53)
        else:
            trim.position = Vector3(-0.53 if side == 2 else 0.53, 0.09, 0)
        trim.set_meta("edge_trim", true)
        root.add_child(trim)
```

**道路与地块融合**：
```gdscript
# 道路面高度调整，紧贴地块表面
# 当前: road.position.y = 0.285（太高，悬浮）
# 修改为: road.position.y = 0.172（与地块表面齐平）
# under.position.y = 0.165
```

**邻居边框刷新**：新地块放置后，刷新所有邻居的边框（已有逻辑 `_refresh_neighbor_trims`，需确认已接入）。

---

## 问题2：道路生成后花朵移位

### 现象
道路放置后，原来有花朵的位置被道路占据，花朵模型卡在道路中间。

### 修复方案

在道路放置函数中，检查并移走重合的花朵：
```gdscript
func _displace_flowers_for_road(pos: Vector2i):
    """道路放置后，将该地块上已有的花朵模型移动到其他空位"""
    # 当前地块上的花朵数量不变（逻辑层面）
    # 但花朵的3D模型需要重新排列，避开道路区域
    _refresh_plant_visual(pos)
```

核心修改：在 `_refresh_plant_visual()` 或花朵渲染逻辑中，花朵模型的摆放位置应使用 `_feature_position()` 避开道路区域（当前装饰物已有此逻辑，花朵模型也需要复用）。

```gdscript
func _refresh_plant_visual(pos: Vector2i):
    # 清除旧的植物模型
    # 重新生成时，每个花朵的摆放位置调用 _feature_position(roads[pos.x][pos.y])
    # 确保花朵模型不与道路重叠
```

---

## 问题3：建筑范围光环增强

### 现象
金色光幕太低，且缺乏动感。

### 修复方案

**提高光幕高度**：
```gdscript
# 当前: 光幕 y = 0.17（贴地）
# 修改为: y = 0.40（地块上方明显位置）
# 光幕高度从 0.12 → 0.20（更高更显眼）
```

**增加金色粒子特效**：
```gdscript
func _spawn_aura_particles(pos: Vector2i):
    """在光幕位置生成向上飘飞的金色粒子"""
    var base_pos = _world(pos) + Vector3(0, 0.40, 0)
    for i in randi_range(2, 4):
        var mote = MeshInstance3D.new()
        var mesh = SphereMesh.new()
        mesh.radius = randf_range(0.012, 0.020)
        mesh.height = mesh.radius * 2
        mote.mesh = mesh
        var mat = StandardMaterial3D.new()
        mat.albedo_color = Color("#ffd860", 0.7)
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.emission_enabled = true; mat.emission = Color("#ffc020")
        mat.emission_energy_multiplier = 1.2
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        mote.material_override = mat
        mote.position = base_pos + Vector3(
            randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35)
        )
        aura_root.add_child(mote)
        # 向上飘升动画
        var tw = create_tween().set_loops()
        tw.tween_property(mote, "position:y",
            mote.position.y + randf_range(0.3, 0.6), randf_range(1.5, 2.5))
        tw.tween_property(mote, "position:y",
            mote.position.y, randf_range(1.5, 2.5))
        # 透明度呼吸
        var tw2 = create_tween().set_loops()
        tw2.tween_property(mat, "albedo_color:a", 0.2, 1.0)
        tw2.tween_property(mat, "albedo_color:a", 0.7, 1.0)
```

在 `_refresh_building_auras()` 中对每个受影响地块调用 `_spawn_aura_particles()`。

---

## 问题4：建筑永远遮挡道路

### 现象
建筑地块上可能显示道路，视觉上不合理。

### 修复方案

在道路生成/刷新时，建筑地块不渲染道路：
```gdscript
func _spawn_road(root: Node3D, road_mask: int, pos: Vector2i):
    # 新增：如果当前地块是建筑，跳过道路渲染
    if _in_bounds(pos) and grid[pos.x][pos.y] == T_BUILDING:
        return
    # ... 原有道路渲染逻辑
```

同时在 `_update_road_bridges()` 中，建筑地块也跳过道路桥接：
```gdscript
func _update_road_bridges(pos: Vector2i):
    if grid[pos.x][pos.y] < 0: return
    if grid[pos.x][pos.y] == T_BUILDING: return  # 新增
    # ...
```

---

## 问题5：结算数字文字上浮动画未实现

### 现象
结算时没有看到花朵数量变化的上浮文字。

### 原因
结算动效系统（OPTIMIZATION_PLAN.md 第一节）尚未实现。

### 需实现的最小版本

在 `_settle_turn()` 中记录花朵快照，结算后对比并触发 Label3D 上浮：

```gdscript
func _settle_turn():
    # 快照
    var snap_flowers = _snapshot_flowers()
    var snap_grid = _snapshot_grid()

    _apply_weather_tile_changes()
    _apply_neighbor_terrain_changes()
    _grow_flowers()
    _spread_flowers()

    # 对比并生成上浮动效
    _emit_settle_labels(snap_grid, snap_flowers)

    _tick_weather()
    _refresh_all_plants()
    _calc_all_scores()

func _emit_settle_labels(snap_grid, snap_flowers):
    for x in _grid_width():
        for y in _grid_height():
            var pos = Vector2i(x, y)
            # 花朵变动
            for pid in player_count:
                var old_val = snap_flowers[x][y][pid]
                var new_val = flowers[x][y][pid]
                if new_val > old_val:
                    _float_label(pos, "+%d" % (new_val - old_val), PLAYER_COLORS[pid])
            # 地块变动
            if snap_grid[x][y] != grid[x][y]:
                _float_label(pos, "%s→%s" % [
                    TERRAIN_NAMES[snap_grid[x][y]],
                    TERRAIN_NAMES[grid[x][y]]
                ], Color("#e8c840"))

func _float_label(pos: Vector2i, text: String, color: Color):
    var label = Label3D.new()
    label.text = text; label.font_size = 14
    label.modulate = color
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.no_depth_test = true; label.pixel_size = 0.006
    label.position = _world(pos) + Vector3(randf_range(-0.15, 0.15), 0.5, 0)
    settle_fx_root.add_child(label)
    var tw = create_tween()
    tw.set_parallel(true)
    tw.tween_property(label, "position:y", label.position.y + 0.6, 2.0)
    tw.tween_property(label, "modulate:a", 0.0, 2.0).set_delay(1.0)
    tw.chain().tween_callback(label.queue_free)
```

---

## 问题6：卡牌预览改为半透明实际效果

### 现象
当前开发/建造卡的预览是简单的半透明色块，不够直观。

### 修复方案

鼠标悬浮在可放置位置时，直接显示**半透明的实际地块效果**：

```gdscript
func _update_card_preview():
    """在鼠标悬浮位置生成半透明的实际地块预览"""
    # 清除旧预览
    for child in preview_root.get_children(): child.queue_free()

    if hovered_cell.x < 0 or not _in_bounds(hovered_cell): return
    var card = _selected_card()
    if card.is_empty(): return

    match card["kind"]:
        "develop":
            # 预览开发后的地块（随机roll地形类型）
            var preview_terr = _roll_preview_terrain(card)
            _spawn_preview_tile(hovered_cell, preview_terr)
        "building_develop":
            _spawn_preview_tile(hovered_cell, T_BUILDING)
        "seed":
            # 预览播种后的花朵效果
            _spawn_preview_seed(hovered_cell, current_player)
        "road":
            # 预览道路路径
            _spawn_preview_road(hovered_cell, card)

func _spawn_preview_tile(pos: Vector2i, terr: int):
    """生成半透明的实际地块预览"""
    var root = Node3D.new()
    root.position = _world(pos); root.position.y = 0.20
    preview_root.add_child(root)

    # 复用 _spawn_tile 的逻辑，但材质改为半透明
    var preview_material = StandardMaterial3D.new()
    preview_material.albedo_color = TERRAIN_TOP[terr]
    preview_material.albedo_color.a = 0.45
    preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    preview_material.no_depth_test = true

    var surface = MeshInstance3D.new()
    var sm = BoxMesh.new(); sm.size = Vector3(0.95, 0.06, 0.95)
    surface.mesh = sm; surface.material_override = preview_material
    surface.position.y = 0.06; root.add_child(surface)

func _spawn_preview_seed(pos: Vector2i, pid: int):
    """预览播种效果：半透明花朵"""
    var root = Node3D.new()
    root.position = _world(pos); root.position.y = 0.06
    preview_root.add_child(root)
    # 用玩家颜色生成半透明花朵模型（复用 _plant_mushroom 等，但材质半透明）
    var preview_mat = StandardMaterial3D.new()
    preview_mat.albedo_color = PLAYER_COLORS[pid]
    preview_mat.albedo_color.a = 0.40
    preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    preview_mat.emission_enabled = true
    preview_mat.emission = PLAYER_COLORS[pid]; preview_mat.emission_energy_multiplier = 0.3
    # ... 生成花朵形状
```

---

## 问题7：卡牌无法放置时卡死

### 现象
选中建筑开发卡等，但没有可放置位置，无法取消，游戏卡死。

### 修复方案

**选中卡牌时立即检查可用位置**：

```gdscript
func _select_card(index: int):
    selected_card = index
    var card = _selected_card()
    if card.is_empty(): return

    # 检查是否有可用位置
    var valid_cells = _find_valid_cells(card)
    if valid_cells.is_empty():
        # 无可用位置：提示 + 退回卡牌
        _show_toast("当前卡牌无法使用，没有可放置的位置")
        selected_card = -1
        ui_ctrl.queue_redraw()
        return

    # 有可用位置：标记为可放置状态
    _enter_placement_mode(card, valid_cells)

func _find_valid_cells(card: Dictionary) -> Array:
    """找出所有可用的放置位置"""
    var valid := []
    for x in _grid_width():
        for y in _grid_height():
            var pos = Vector2i(x, y)
            if _can_use_card_at(card, pos):
                valid.append(pos)
    return valid

func _enter_placement_mode(card: Dictionary, valid_cells: Array):
    """进入放置模式：可用位置呼吸发光"""
    placement_cells = valid_cells
    _start_placement_highlight(valid_cells)

func _start_placement_highlight(cells: Array):
    """可用位置呼吸发光"""
    for child in placement_highlight_root.get_children(): child.queue_free()
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.4, 1.0, 0.6, 0.22)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.no_depth_test = true
    for pos in cells:
        var highlight = MeshInstance3D.new()
        var hm = BoxMesh.new(); hm.size = Vector3(1.05, 0.025, 1.05)
        highlight.mesh = hm; highlight.material_override = mat
        highlight.position = _world(pos) + Vector3(0, 0.18, 0)
        placement_highlight_root.add_child(highlight)
    # 呼吸脉冲（共用同一个材质引用）
    var tw = create_tween().set_loops()
    tw.tween_property(mat, "albedo_color:a", 0.38, 0.8).set_trans(Tween.TRANS_SINE)
    tw.tween_property(mat, "albedo_color:a", 0.15, 0.8).set_trans(Tween.TRANS_SINE)

func _show_toast(text: String):
    """屏幕中央显示提示文字，2秒后消失"""
    var toast = Label.new()
    toast.text = text; toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    toast.add_theme_font_size_override("font_size", 18)
    toast.modulate = Color("#ffcc44")
    # 居中放置...
    ui_ctrl.add_child(toast)
    var tw = create_tween()
    tw.tween_interval(2.0)
    tw.tween_property(toast, "modulate:a", 0.0, 0.5)
    tw.tween_callback(toast.queue_free)

# 右键/ESC 取消选中
func _cancel_card_selection():
    selected_card = -1
    placement_cells.clear()
    for child in placement_highlight_root.get_children(): child.queue_free()
    for child in preview_root.get_children(): child.queue_free()
    ui_ctrl.queue_redraw()
```

**输入处理中增加 ESC/右键取消**：
```gdscript
# 在 _input() 中：
if selected_card >= 0:
    if event is InputEventKey and event.keycode == KEY_ESCAPE:
        _cancel_card_selection(); return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
        _cancel_card_selection(); return
```

---

## 问题8：天气特效未显示

### 现象
打出天气卡后，没有看到任何全局天气视觉效果。

### 原因
天气特效系统（OPTIMIZATION_PLAN.md 第六节）尚未实现。

### 最小可实现版本

至少实现2种最常用的天气特效：

```gdscript
# 天气特效容器（在 _setup_scene() 中创建）
var weather_fx_root: Node3D

func _apply_weather_visual(weather_name: String):
    _clear_weather_visual()
    match weather_name:
        "台风": _weather_fx_typhoon()
        "沙尘暴": _weather_fx_sandstorm()
        "雨季": _weather_fx_rain()
        "旱季": _weather_fx_drought()
        "彩虹": _weather_fx_rainbow()

func _clear_weather_visual():
    for child in weather_fx_root.get_children(): child.queue_free()

# ---- 台风：乌云 + 雨滴 ----
func _weather_fx_typhoon():
    # 乌云
    var cloud_mat = StandardMaterial3D.new()
    cloud_mat.albedo_color = Color(0.2, 0.2, 0.25, 0.35)
    cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    for i in 4:
        var cloud = MeshInstance3D.new()
        var cm = BoxMesh.new()
        cm.size = Vector3(randf_range(3.0, 5.0), 0.3, randf_range(2.0, 3.5))
        cloud.mesh = cm; cloud.material_override = cloud_mat
        cloud.position = Vector3(randf_range(-3, 8), 3.5, randf_range(-3, 8))
        weather_fx_root.add_child(cloud)
        # 缓慢漂移
        var tw = create_tween().set_loops()
        tw.tween_property(cloud, "position:x", cloud.position.x + 2.0, 4.0)
        tw.tween_property(cloud, "position:x", cloud.position.x - 2.0, 4.0)
    # 雨滴
    var rain_mat = StandardMaterial3D.new()
    rain_mat.albedo_color = Color(0.6, 0.7, 0.9, 0.4)
    rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    for i in 40:
        var drop = MeshInstance3D.new()
        var dm = CylinderMesh.new()
        dm.top_radius = 0.004; dm.bottom_radius = 0.004; dm.height = 0.08
        drop.mesh = dm; drop.material_override = rain_mat
        drop.position = Vector3(randf_range(-3, 8), randf_range(0.5, 3.0), randf_range(-3, 8))
        weather_fx_root.add_child(drop)
        var tw = create_tween().set_loops()
        tw.tween_property(drop, "position:y", -0.5, randf_range(0.3, 0.6))
        tw.tween_callback(func(): drop.position.y = randf_range(2.0, 3.5))

# ---- 沙尘暴：黄色雾 + 沙粒 ----
func _weather_fx_sandstorm():
    var fog_mat = StandardMaterial3D.new()
    fog_mat.albedo_color = Color(0.8, 0.7, 0.4, 0.08)
    fog_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    fog_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    for i in 6:
        var fog = MeshInstance3D.new()
        var fm = BoxMesh.new()
        fm.size = Vector3(randf_range(4.0, 7.0), 0.02, randf_range(2.0, 4.0))
        fog.mesh = fm; fog.material_override = fog_mat
        fog.position = Vector3(randf_range(-4, 9), 0.8, randf_range(-4, 9))
        weather_fx_root.add_child(fog)
        var tw = create_tween().set_loops()
        tw.tween_property(fog, "position:x", fog.position.x + 6.0, 6.0)
        tw.tween_callback(func(): fog.position.x = randf_range(-4, -1))
    # 沙粒
    var sand_mat = StandardMaterial3D.new()
    sand_mat.albedo_color = Color(0.9, 0.8, 0.5, 0.6)
    sand_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    sand_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    for i in 50:
        var grain = MeshInstance3D.new()
        var gm = SphereMesh.new()
        gm.radius = 0.006; gm.height = 0.012
        grain.mesh = gm; grain.material_override = sand_mat
        grain.position = Vector3(randf_range(-5, 10), randf_range(0.2, 2.0), randf_range(-5, 10))
        weather_fx_root.add_child(grain)
        var tw = create_tween().set_loops()
        tw.tween_property(grain, "position:x", grain.position.x + 12.0, randf_range(1.5, 3.0))
        tw.tween_callback(func():
            grain.position.x = randf_range(-5, -2)
            grain.position.y = randf_range(0.2, 2.0)
        )

# ---- 雨季：细雨 ----
func _weather_fx_rain():
    var rain_mat = StandardMaterial3D.new()
    rain_mat.albedo_color = Color(0.5, 0.6, 0.8, 0.25)
    rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    for i in 25:
        var drop = MeshInstance3D.new()
        var dm = CylinderMesh.new()
        dm.top_radius = 0.003; dm.bottom_radius = 0.003; dm.height = 0.06
        drop.mesh = dm; drop.material_override = rain_mat
        drop.position = Vector3(randf_range(-3, 8), randf_range(0.5, 2.5), randf_range(-3, 8))
        weather_fx_root.add_child(drop)
        var tw = create_tween().set_loops()
        tw.tween_property(drop, "position:y", -0.5, randf_range(0.4, 0.8))
        tw.tween_callback(func(): drop.position.y = randf_range(1.5, 2.5))

# ---- 旱季：太阳光晕 ----
func _weather_fx_drought():
    var sun = MeshInstance3D.new()
    var sm = SphereMesh.new()
    sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 12; sm.rings = 6
    sun.mesh = sm
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.9, 0.3, 0.06)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.emission_enabled = true; mat.emission = Color("#ffe040")
    mat.emission_energy_multiplier = 1.5
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    sun.material_override = mat
    sun.position = Vector3(3.5, 5.0, 3.5)
    weather_fx_root.add_child(sun)
    # 脉冲
    var tw = create_tween().set_loops()
    tw.tween_property(mat, "emission_energy_multiplier", 2.5, 2.0).set_trans(Tween.TRANS_SINE)
    tw.tween_property(mat, "emission_energy_multiplier", 1.0, 2.0).set_trans(Tween.TRANS_SINE)

# ---- 彩虹：7色弧形 ----
func _weather_fx_rainbow():
    var colors = [
        Color("#ff4040"), Color("#ff8800"), Color("#ffee00"),
        Color("#40ff40"), Color("#40ffff"), Color("#4040ff"), Color("#ff40ff")
    ]
    for i in 7:
        var arc = MeshInstance3D.new()
        var am = CylinderMesh.new()
        am.top_radius = 4.0 - i * 0.12; am.bottom_radius = 4.0 - i * 0.12
        am.height = 0.06; am.radial_segments = 24
        arc.mesh = am
        var mat = StandardMaterial3D.new()
        mat.albedo_color = colors[i]; mat.albedo_color.a = 0.20
        mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        mat.emission_enabled = true; mat.emission = colors[i]
        mat.emission_energy_multiplier = 0.5
        mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        arc.material_override = mat
        arc.position = Vector3(3.5, 3.0, 3.5)
        arc.rotation_degrees.x = 90
        arc.rotation_degrees.z = 30 * (i - 3)
        weather_fx_root.add_child(arc)
        # 渐入
        mat.albedo_color.a = 0.0
        var tw = create_tween()
        tw.tween_property(mat, "albedo_color:a", 0.20, 1.5)
```

### 接入点

在打出天气卡的函数中调用 `_apply_weather_visual(weather_name)`。
在 `_tick_weather()` 结束后，如果天气过期则调用 `_clear_weather_visual()`。

---

## 实施优先级

| 优先级 | 问题 | 修复内容 |
|--------|------|----------|
| P0 | #7 卡牌卡死 | 选卡时检查可用位置 + 无位置提示 + ESC/右键取消 |
| P0 | #1 边框融合 | 边框覆盖底座侧面 + 道路贴地 + 邻居刷新 |
| P0 | #2 花朵移位 | 花朵模型避开道路区域 |
| P0 | #5 结算上浮 | Label3D 上浮 + 淡出动画 |
| P1 | #6 预览效果 | 半透明实际地块/花朵预览 |
| P1 | #3 光幕增强 | 提高高度 + 金色粒子 |
| P1 | #4 建筑遮挡道路 | 建筑地块跳过道路渲染 |
| P1 | #8 天气特效 | 至少实现台风/沙尘暴的粒子效果 |
