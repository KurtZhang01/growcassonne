# GrowCassonne 视觉优化方案

---

## 一、结算动效系统

回合结束结算时，在棋盘上显示浮动动画，让玩家清楚看到本回合发生了什么变化。

### 1.1 动效类型

#### 类型A：地块变动
- **外观**：旧地块缩略图 → 箭头 → 新地块缩略图
- **实现**：在地块上方约 0.6 高度处生成3D组节点
  - 左侧：小方块（旧地形色），尺寸 0.15×0.06×0.15
  - 中间：三角箭头（PrismMesh 或扁平三角形），朝右，金色
  - 右侧：小方块（新地形色），尺寸 0.15×0.06×0.15
- **动画**：整体从 y=0.5 浮升到 y=1.2，持续 2 秒，最后 0.5 秒淡出（alpha 从 1→0）
- **触发位置**：`_apply_weather_tile_changes()` 和 `_apply_neighbor_terrain_changes()` 结束后

#### 类型B：花朵量变动
- **外观**：红色向上箭头 + 花朵小模型 + 增加数字
- **实现**：在地块上方生成3D组节点
  - 箭头：PrismMesh 朝上，红色，尺寸 0.08×0.12×0.04
  - 花朵模型：复用 `_spawn_growth_burst` 中的粒子样式，但只有1-2个
  - 数字：用 Label3D 显示 "+N"，字体大小 12，白色带阴影
- **动画**：同类型A，浮升 + 淡出
- **触发位置**：`_grow_flowers()` 和 `_spread_flowers()` 中每个地块增值时

### 1.2 核心函数设计

```gdscript
# 结算动效容器
var settle_fx_root: Node3D  # 在 _setup_scene() 中创建

# 通用浮动文字节点
func _spawn_settle_fx(pos: Vector2i, fx_type: String, data: Dictionary):
    # fx_type: "terrain_change" | "flower_gain"
    # data: {"old_terr": int, "new_terr": int} 或 {"amount": int, "color": Color}
    var anchor = Node3D.new()
    anchor.position = _world(pos) + Vector3(0, 0.5, 0)
    settle_fx_root.add_child(anchor)

    if fx_type == "terrain_change":
        _build_terrain_change_fx(anchor, data)
    elif fx_type == "flower_gain":
        _build_flower_gain_fx(anchor, data)

    # 通用浮升 + 淡出动画
    var tw = create_tween()
    tw.set_parallel(true)
    tw.tween_property(anchor, "position:y", anchor.position.y + 0.7, 2.0)
    tw.tween_property(anchor, "modulate:a", 0.0, 2.0).set_delay(1.2)
    tw.chain().tween_callback(anchor.queue_free)

func _build_terrain_change_fx(anchor: Node3D, data: Dictionary):
    # 旧地形色块
    var old_block = MeshInstance3D.new()
    var bm = BoxMesh.new(); bm.size = Vector3(0.15, 0.06, 0.15)
    old_block.mesh = bm
    var om = StandardMaterial3D.new(); om.albedo_color = TERRAIN_TOP[data["old_terr"]]
    old_block.material_override = om; old_block.position.x = -0.18
    anchor.add_child(old_block)

    # 箭头
    var arrow = MeshInstance3D.new()
    var am = PrismMesh.new(); am.size = Vector3(0.06, 0.08, 0.04)
    arrow.mesh = am
    var amm = StandardMaterial3D.new(); amm.albedo_color = Color("#e8c840")
    arrow.material_override = amm; arrow.rotation.z = -PI / 2
    anchor.add_child(arrow)

    # 新地形色块
    var new_block = MeshInstance3D.new()
    new_block.mesh = bm
    var nm = StandardMaterial3D.new(); nm.albedo_color = TERRAIN_TOP[data["new_terr"]]
    new_block.material_override = nm; new_block.position.x = 0.18
    anchor.add_child(new_block)

func _build_flower_gain_fx(anchor: Node3D, data: Dictionary):
    # 向上箭头
    var arrow = MeshInstance3D.new()
    var am = PrismMesh.new(); am.size = Vector3(0.05, 0.08, 0.04)
    arrow.mesh = am
    var amm = StandardMaterial3D.new(); amm.albedo_color = Color("#e04040")
    arrow.material_override = amm; arrow.position.x = -0.10
    anchor.add_child(arrow)

    # +N 数字
    var label = Label3D.new()
    label.text = "+%d" % data["amount"]
    label.font_size = 14; label.modulate = Color("#ffee66")
    label.position = Vector3(0.06, 0.02, 0)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    anchor.add_child(label)
```

### 1.3 接入点

在 `_settle_turn()` 中，结算前记录快照，结算后对比并触发动效：

```gdscript
func _settle_turn():
    # 记录快照
    var snap_grid = _snapshot_grid()
    var snap_flowers = _snapshot_flowers()

    _apply_weather_tile_changes()
    _apply_neighbor_terrain_changes()
    _grow_flowers()
    _spread_flowers()

    # 对比并生成动效
    _emit_settle_effects(snap_grid, snap_flowers)

    _tick_weather()
    _refresh_all_plants()
    _calc_all_scores()
```

---

## 二、建筑范围光环

被建筑增益覆盖的地块（建筑上下左右4格内的植物地块），在地块外边界显示动态金色光幕。

### 2.1 视觉设计

- **形状**：在受影响地块的外边界（与非增益区域相邻的边）上，生成一个薄金色半透明矩形
- **动画**：光幕缓慢脉冲（scale 在 0.95~1.05 之间循环），颜色在金色和亮金色之间缓慢过渡
- **高度**：与地块边缘齐平，y = 0.17
- **材质**：半透明金色，alpha ≈ 0.35，带 emission

### 2.2 实现方案

```gdscript
# 光环容器
var aura_root: Node3D

# 存储当前光环节点，用于动态刷新
var aura_nodes := {}  # Vector2i -> [MeshInstance3D, ...]

func _refresh_building_auras():
    # 清除旧光环
    for key in aura_nodes:
        for node in aura_nodes[key]:
            node.queue_free()
    aura_nodes.clear()

    # 遍历所有建筑，标记受影响地块
    var boosted := {}
    for x in _grid_width():
        for y in _grid_height():
            if grid[x][y] != T_BUILDING: continue
            for dx in range(-1, 2):
                for dy in range(-1, 2):
                    var p = Vector2i(x + dx, y + dy)
                    if _in_bounds(p) and _is_plant_terrain(grid[p.x][p.y]):
                        boosted[p] = true

    # 为受影响地块创建边界光幕
    for pos in boosted:
        _spawn_aura_borders(pos)

func _spawn_aura_borders(pos: Vector2i):
    var borders := []
    for dir_index in DIRS.size():
        var n = pos + DIRS[dir_index]
        # 只在与非增益区域相邻的边上显示光幕
        var show_border = false
        if not _in_bounds(n):
            show_border = true
        elif not _is_in_building_range(n):
            show_border = true
        if show_border:
            borders.append(dir_index)

    if borders.is_empty(): return
    aura_nodes[pos] = []

    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color("#f0d060", 0.35)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.emission_enabled = true; mat.emission = Color("#ffd040")
    mat.emission_energy_multiplier = 0.6
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.no_depth_test = true

    for dir_index in borders:
        var mi = MeshInstance3D.new()
        var bm = BoxMesh.new()
        var horizontal = dir_index < 2
        bm.size = Vector3(1.07 if horizontal else 0.025, 0.12, 0.025 if horizontal else 1.07)
        mi.mesh = bm; mi.material_override = mat
        var offset = Vector3.ZERO
        match dir_index:
            0: offset = Vector3(0, 0.17, -0.515)  # UP
            1: offset = Vector3(0, 0.17, 0.515)   # DOWN
            2: offset = Vector3(-0.515, 0.17, 0)   # LEFT
            3: offset = Vector3(0.515, 0.17, 0)    # RIGHT
        mi.position = _world(pos) + offset
        aura_root.add_child(mi)
        aura_nodes[pos].append(mi)

    # 脉冲动画
    var tw = create_tween().set_loops()
    tw.tween_property(mat, "emission_energy_multiplier", 1.2, 1.0).set_trans(Tween.TRANS_SINE)
    tw.tween_property(mat, "emission_energy_multiplier", 0.4, 1.0).set_trans(Tween.TRANS_SINE)
```

### 2.3 刷新时机

在以下位置调用 `_refresh_building_auras()`：
- 地块被开发卡改变后
- 建筑开发卡使用后
- 结算阶段地块变动后

---

## 三、同类地块边界合并

当前每个地块都画4条边框，同类相邻地块之间会出现两条重复边框。改为**只在不同地形类型之间显示边框**。

### 3.1 修改 `_spawn_edge_trim()`

将当前"总是画4边"改为"只画与不同地形相邻的边"：

```gdscript
func _spawn_edge_trim(root: Node3D, terr: int, pos: Vector2i):
    var trim_material = StandardMaterial3D.new()
    trim_material.albedo_color = TERRAIN_TOP[terr].lightened(0.08)
    trim_material.roughness = 0.76

    for side in 4:
        var neighbor = pos + DIRS[side]
        # 如果邻居存在且地形相同，跳过这条边
        if _in_bounds(neighbor) and grid[neighbor.x][neighbor.y] == terr:
            continue

        var horizontal = side < 2
        var trim = MeshInstance3D.new(); var mesh = BoxMesh.new()
        mesh.size = Vector3(1.07 if horizontal else 0.035, 0.018, 0.035 if horizontal else 1.07)
        trim.mesh = mesh; trim.material_override = trim_material
        if horizontal: trim.position = Vector3(0, 0.172, -0.515 if side == 0 else 0.515)
        else: trim.position = Vector3(-0.515 if side == 2 else 0.515, 0.172, 0)
        root.add_child(trim)
```

### 3.2 需要修改的地方

1. **`_spawn_tile()`**：调用 `_spawn_edge_trim` 时传入 pos 参数
2. **`_force_tile()`**：同上
3. **邻居放置后刷新**：当新地块放置时，已存在的邻居地块也需要重建 edge trim（类似 `_update_edge_bridges` 的逻辑）

```gdscript
# 在 _spawn_tile() 中修改调用：
_spawn_edge_trim(root, terr, pos)  # 原来只传 terr

# 新地块放置后，刷新邻居的边框
func _refresh_neighbor_trims(pos: Vector2i):
    for dir in DIRS:
        var n = pos + dir
        if _in_bounds(n) and tile_nodes[n.x][n.y] != null:
            _rebuild_edge_trim(n)

func _rebuild_edge_trim(pos: Vector2i):
    # 移除旧的 trim 子节点，重新生成
    var root = tile_nodes[pos.x][pos.y]
    if root == null: return
    for child in root.get_children():
        if child.has_meta("edge_trim"):
            child.queue_free()
    _spawn_edge_trim(root, grid[pos.x][pos.y], pos)
```

### 3.3 效果

- 同类地块（如两块草地相邻）之间不再有分隔线，视觉上连成一片
- 不同地形之间的边框保留，保持清晰的地形边界
- 整体视觉更干净，地块融合感更强

---

## 四、缺口地块建模优化

### 4.1 当前问题

缺口地块（`_tile_gap_surface`，main3d.gd:1090-1102）当前只有4条半透明淡蓝边框线，没有底座模型，视觉上像一个空洞，与其他有底座的地块风格不统一。

### 4.2 方案

缺口地块增加与其他地块类似的底座模型，但改为**半透明白色**，保持"空缺"的视觉暗示：

```gdscript
func _tile_gap_surface(root: Node3D):
    # 半透明白色底座（与其他地块底座结构一致）
    var gap_material = StandardMaterial3D.new()
    gap_material.albedo_color = Color(0.95, 0.98, 1.0, 0.25)
    gap_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    gap_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

    # 主平台（与 _spawn_island_base 相似的分层结构）
    # 上层
    var top = MeshInstance3D.new(); var tm = BoxMesh.new()
    tm.size = Vector3(1.06, 0.025, 1.06)
    top.mesh = tm; top.material_override = gap_material
    top.position.y = 0.155; root.add_child(top)

    # 中层
    var mid = MeshInstance3D.new(); var mm = BoxMesh.new()
    mm.size = Vector3(0.88, 0.025, 0.88)
    mid.mesh = mm; mid.material_override = gap_material
    mid.position.y = 0.120; root.add_child(mid)

    # 底层
    var bot = MeshInstance3D.new(); var bm = BoxMesh.new()
    bm.size = Vector3(0.56, 0.030, 0.56)
    bot.mesh = bm; bot.material_override = gap_material
    bot.position.y = 0.080; root.add_child(bot)

    # 四边边框（保留，但颜色也改为半透明白）
    var edge_material = StandardMaterial3D.new()
    edge_material.albedo_color = Color(0.95, 0.98, 1.0, 0.35)
    edge_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    edge_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    for side in 4:
        var edge = MeshInstance3D.new(); var mesh = BoxMesh.new()
        var horizontal = side < 2
        mesh.size = Vector3(0.88 if horizontal else 0.025, 0.018, 0.025 if horizontal else 0.88)
        edge.mesh = mesh; edge.material_override = edge_material
        if horizontal: edge.position = Vector3(0, 0.16, -0.44 if side == 0 else 0.44)
        else: edge.position = Vector3(-0.44 if side == 2 else 0.44, 0.16, 0)
        root.add_child(edge)
```

### 4.3 效果

- 缺口地块有与其他地块一致的分层底座结构（上层/中层/底层）
- 半透明白色材质（alpha ≈ 0.25），视觉上"空缺"但不突兀
- 保留边框线增强边界感
- 与山体的灰色实体、其他地块的彩色实体形成对比

---

## 五、道路视觉修复与优化

### 5.1 移除闭合道路脉冲圆环

**问题**：闭合道路（`_spawn_road_fx`，main3d.gd:759-772）在每个闭合节点上生成一个金色 TorusMesh 圆环，旋转并脉冲放大缩小。视觉上突兀，与整体风格不协调。

**方案**：移除 `_spawn_road_fx` 中的圆环，替换为更柔和的地面光晕效果：

```gdscript
func _spawn_road_fx(pos: Vector2i):
    # 改为：地面金色光圈（扁平圆盘，贴地脉冲）
    var disc = MeshInstance3D.new()
    var dm = CylinderMesh.new()
    dm.top_radius = 0.22; dm.bottom_radius = 0.22; dm.height = 0.008
    dm.radial_segments = 20
    disc.mesh = dm
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.88, 0.4, 0.18)
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.emission_enabled = true; mat.emission = Color("#ffd040")
    mat.emission_energy_multiplier = 0.4
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    disc.material_override = mat
    disc.position = _world(pos) + Vector3(0, 0.165, 0)
    disc.set_meta("road_fx", true); edge_root.add_child(disc)

    # 缓慢呼吸脉冲
    var tw = create_tween().set_loops()
    tw.tween_property(mat, "emission_energy_multiplier", 0.8, 1.5).set_trans(Tween.TRANS_SINE)
    tw.tween_property(mat, "emission_energy_multiplier", 0.3, 1.5).set_trans(Tween.TRANS_SINE)
```

### 5.2 道路建模优化

**当前问题**：道路是简单的扁平 BoxMesh，视觉上不够明显。

**优化方案**：
- 道路宽度从 0.16 调整为 0.20，更清晰
- 道路材质改为带微弱 emission 的暖色，增加辨识度
- 道路桥接（跨地块连接处）增加微弱发光，提示连通性

```gdscript
func _spawn_road(root: Node3D, road_mask: int):
    var under_material = _road_material(Color("#5a4430"), 0.95)
    var road_material = _road_material(Color("#d8bd80"), 0.82)
    road_material.emission_enabled = true
    road_material.emission = Color("#a89060")
    road_material.emission_energy_multiplier = 0.08
    root.set_meta("road_material", road_material)
    # ... 其余逻辑不变，仅调整宽度参数
    # 路面宽度从 0.16 → 0.20
    # 路面高度从 0.028 → 0.022（更贴地）
```

---

## 六、天气全局动效

天气卡打出后，在整个棋盘上显示对应的环境氛围效果。

### 6.1 台风：乌云 + 下雨

```
效果层：
1. 乌云遮罩 — 棋盘上方 4 高度处生成 3-5 个大灰色半透明云团（BoxMesh + SphereMesh 混合），
   缓慢左右漂移，alpha ≈ 0.35，遮挡部分阳光
2. 雨滴粒子 — 从 y=3 到 y=0 的下落粒子，数量 40-60，
   使用细长 CylinderMesh（半径 0.005，高度 0.08），浅蓝色半透明
   每帧下落，落到地面后重置到顶部
3. 整体色调偏暗偏蓝 — 调整 ambient_light_energy 降低 0.15
```

### 6.2 沙尘暴：黄色雾 + 沙粒 + 风

```
效果层：
1. 黄色雾气 — 棋盘高度 y=0.5~2.0 区域生成大面积黄色半透明平面
   alpha ≈ 0.12，缓慢水平移动模拟风向
2. 沙粒粒子 — 60-80 个微小球体（半径 0.008），黄褐色，
   从左侧飘入右侧飘出，带有随机上下浮动
3. 整体色调偏暖偏黄 — ambient_light_color 调为偏黄
```

### 6.3 雨季：雨 + 水域涟漪增强

```
效果层：
1. 细雨 — 比台风雨更细更稀疏（20-30 粒子），更柔和的蓝色
2. 水域涟漪增强 — 所有水域地块的涟漪动画速度加快 1.5 倍，
   涟漪圈数 +1，颜色偏亮蓝
3. 整体色调微亮 — ambient_light_energy 微增
```

### 6.4 旱季：太阳光晕

```
效果层：
1. 太阳光晕 — 棋盘上方 y=5 处生成一个大 SphereMesh（半径 1.5），
   金黄色半透明（alpha ≈ 0.08），带强 emission（energy 2.0+）
2. 光线散射 — 从太阳位置向四周发射 8-12 条细长光柱
   （BoxMesh，极细，半透明金黄），缓慢旋转
3. 整体色调偏暖偏亮 — ambient_light_color 偏暖黄
```

### 6.5 彩虹：半透明彩虹弧

```
效果层：
1. 彩虹弧 — 用 7 个薄弧形 BoxMesh（或 CylinderMesh 环段）拼成彩虹，
   位于棋盘上方 y=3，半径 4-5，跨越整个棋盘
   7 色：红 #ff4040、橙 #ff8800、黄 #ffee00、绿 #40ff40、
         青 #40ffff、蓝 #4040ff、紫 #ff40ff
   alpha ≈ 0.25，带 emission
2. 缓慢出现 — 从 alpha=0 渐入到 0.25，持续 1 秒
3. 花朵粒子 — 整个棋盘范围内随机飘落彩色小花瓣粒子（可选）
```

### 6.6 天气动效管理器

```gdscript
# 天气动效根节点
var weather_fx_root: Node3D
var weather_particles := []  # 存储当前活跃的天气粒子节点
var weather_ambient_backup: Color  # 备份原始环境光

func _apply_weather_fx(weather_name: String):
    _clear_weather_fx()
    weather_ambient_backup = ambient_light_color
    match weather_name:
        "台风": _fx_typhoon()
        "沙尘暴": _fx_sandstorm()
        "雨季": _fx_rainy()
        "旱季": _fx_drought()
        "彩虹": _fx_rainbow()

func _clear_weather_fx():
    for child in weather_fx_root.get_children():
        child.queue_free()
    weather_particles.clear()
    # 恢复环境光
    ambient_light_color = weather_ambient_backup
    ambient_light_energy = 0.60

func _process_weather_fx(delta: float):
    # 每帧更新粒子位置（雨滴下落、沙粒飘动等）
    for particle in weather_particles:
        _update_particle(particle, delta)
```

### 6.7 接入点

在 `_play_weather_card()` 中调用 `_apply_weather_fx(weather_name)`。
在 `_tick_weather()` 结束后，如果天气已过期则调用 `_clear_weather_fx()`。

---

## 七、地块选中与信息面板

### 7.1 触发条件

- 当前状态为**空闲**（不在使用卡牌、不在出牌阶段）时，鼠标左键点击地块触发选中
- 已有卡牌被选中时，点击行为保持原有逻辑（出牌/播种），不触发信息面板
- 再次点击同一地块取消选中，点击另一地块切换选中

### 7.2 选中高光

- 在被选中地块上方生成白色半透明光幕（BoxMesh，尺寸 1.07×0.02×1.07）
- 材质：白色，alpha ≈ 0.30，unshaded，no_depth_test
- 位置：y = 0.19（略高于地块表面）
- 带微弱呼吸脉冲（alpha 在 0.20~0.40 之间缓慢变化）

### 7.3 信息面板内容

在被选中地块**上方**用 Label3D 显示详细属性，从上到下依次排列：

#### 植物地块（森林/草地/荒漠）

```
┌─────────────────────────┐
│  ● 森林（高级）          │  ← 地块名称 + 等级
│  生长率：0.5             │  ← 花朵生长率
│  容积：42 / 100          │  ← 当前花朵总数 / 最大容积
│  ─────────────────────── │
│  🔴 玩家1：15 朵         │  ← 各玩家花朵数量（用玩家颜色）
│  🟣 玩家2：27 朵         │
│  ─────────────────────── │
│  相邻增益：              │
│   水域 ×2 → 翡率翻倍     │  ← 水域影响（3×3范围）
│   建筑 ×1 → 容积翻倍     │  ← 建筑影响（4格范围内）
│  ─────────────────────── │
│  道路：无 / 已连通       │  ← 道路状态
│  花朵扩散：允许 / 禁止   │  ← 道路地块不扩散
└─────────────────────────┘
```

#### 增益地块（水域）

```
┌─────────────────────────┐
│  ● 水域                  │
│  效果：相邻植物地块升级概率翻倍 │
│  影响范围：3×3（8格）     │
│  当前影响：3 个植物地块   │
└─────────────────────────┘
```

#### 增益地块（建筑）

```
┌─────────────────────────┐
│  ● 建筑                  │
│  效果：相邻植物地块容积翻倍 │
│  影响范围：4格（十字形）  │
│  当前影响：2 个植物地块   │
└─────────────────────────┘
```

#### 可开发地块（山体/缺口）

```
┌─────────────────────────┐
│  ● 山体 / 缺口           │
│  可被开发卡作用           │
│  （缺口可被建筑开发卡作用）│
└─────────────────────────┘
```

### 7.4 实现方案

```gdscript
# 状态
var selected_tile := Vector2i(-1, -1)
var tile_select_root: Node3D  # 选中高光容器
var tile_info_labels := []    # Label3D 列表

# 触发选中（在 _input 的鼠标点击处理中）
func _try_select_tile(cell: Vector2i):
    if cell.x < 0 or not _in_bounds(cell):
        _clear_tile_selection()
        return
    if cell == selected_tile:
        _clear_tile_selection()
        return
    selected_tile = cell
    _update_tile_selection()

func _clear_tile_selection():
    selected_tile = Vector2i(-1, -1)
    for child in tile_select_root.get_children(): child.queue_free()
    for label in tile_info_labels: label.queue_free()
    tile_info_labels.clear()

func _update_tile_selection():
    # 清除旧的
    for child in tile_select_root.get_children(): child.queue_free()
    for label in tile_info_labels: label.queue_free()
    tile_info_labels.clear()

    if not _in_bounds(selected_tile): return
    var terr = grid[selected_tile.x][selected_tile.y]
    if terr < 0: return

    # 白色高光
    var highlight = MeshInstance3D.new()
    var hm = BoxMesh.new(); hm.size = Vector3(1.07, 0.02, 1.07)
    highlight.mesh = hm
    var hmat = StandardMaterial3D.new()
    hmat.albedo_color = Color(1, 1, 1, 0.30)
    hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    hmat.no_depth_test = true
    highlight.material_override = hmat
    highlight.position = _world(selected_tile) + Vector3(0, 0.19, 0)
    tile_select_root.add_child(highlight)

    # 呼吸脉冲
    var tw = create_tween().set_loops()
    tw.tween_property(hmat, "albedo_color:a", 0.40, 1.2).set_trans(Tween.TRANS_SINE)
    tw.tween_property(hmat, "albedo_color:a", 0.20, 1.2).set_trans(Tween.TRANS_SINE)

    # 信息面板
    _spawn_tile_info_panel(selected_tile)
```

### 7.5 Label3D 信息面板实现

```gdscript
func _spawn_tile_info_panel(pos: Vector2i):
    var terr = grid[pos.x][pos.y]
    var base_pos = _world(pos) + Vector3(0, 0.55, 0)
    var line_height = 0.12
    var lines := []

    if _is_plant_terrain(terr):
        var names = ["草地", "水域", "森林", "荒漠", "楼阁"]
        var levels = ["中级", "", "高级", "低级", ""]
        var rates = [0.3, 0.0, 0.5, 0.1, 0.0]
        var cap = _tile_capacity(pos)
        var total = _flower_total(pos)

        lines.append({"text": "● %s（%s）" % [names[terr], levels[terr]], "color": Color.WHITE, "size": 16})
        lines.append({"text": "生长率：%.1f" % rates[terr], "color": Color("#aaddaa"), "size": 13})
        lines.append({"text": "容积：%d / %d" % [total, cap], "color": Color("#eeeecc"), "size": 13})
        lines.append({"text": "─────────", "color": Color(1,1,1,0.3), "size": 10})

        for pid in player_count:
            var amount = flowers[pos.x][pos.y][pid]
            if amount > 0:
                lines.append({"text": "%s：%d 朵" % [PLAYER_NAMES[pid], amount], "color": PLAYER_COLORS[pid], "size": 13})

        # 相邻增益
        var water_count = 0; var building_count = 0
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                if dx == 0 and dy == 0: continue
                var n = pos + Vector2i(dx, dy)
                if _in_bounds(n):
                    if grid[n.x][n.y] == T_WATER: water_count += 1
                    if grid[n.x][n.y] == T_BUILDING: building_count += 1
        if water_count > 0 or building_count > 0:
            lines.append({"text": "相邻增益：", "color": Color("#ccccaa"), "size": 11})
            if water_count > 0:
                lines.append({"text": " 水域×%d → 升级翻倍" % water_count, "color": Color("#60a0dd"), "size": 11})
            if building_count > 0:
                lines.append({"text": " 建筑×%d → 容积翻倍" % building_count, "color": Color("#dd6040"), "size": 11})

        # 道路状态
        if roads[pos.x][pos.y] != 0:
            lines.append({"text": "道路：已连通（不可扩散）", "color": Color("#d8b870"), "size": 11})
        else:
            lines.append({"text": "道路：无", "color": Color(1,1,1,0.4), "size": 11})

    elif terr == T_WATER:
        lines.append({"text": "● 水域", "color": Color("#60b0dd"), "size": 16})
        lines.append({"text": "相邻植物地块升级概率翻倍", "color": Color("#a0d0ee"), "size": 12})
        lines.append({"text": "影响范围：3×3（8格）", "color": Color(1,1,1,0.6), "size": 11})
    elif terr == T_BUILDING:
        lines.append({"text": "● 建筑", "color": Color("#dd6040"), "size": 16})
        lines.append({"text": "相邻植物地块容积翻倍", "color": Color("#eea080"), "size": 12})
        lines.append({"text": "影响范围：4格（十字形）", "color": Color(1,1,1,0.6), "size": 11})
    elif _is_developable(terr):
        var name = "山体" if terr == T_MOUNTAIN else "缺口"
        lines.append({"text": "● %s" % name, "color": Color("#aaaaaa"), "size": 16})
        lines.append({"text": "可被开发卡作用", "color": Color(1,1,1,0.5), "size": 12})

    # 生成 Label3D
    for i in lines.size():
        var label = Label3D.new()
        label.text = lines[i]["text"]
        label.font_size = lines[i]["size"]
        label.modulate = lines[i]["color"]
        label.position = base_pos + Vector3(0, (lines.size() - i) * line_height, 0)
        label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        label.no_depth_test = true
        label.pixel_size = 0.008
        tile_info_labels.append(label)
        tile_select_root.add_child(label)
```

### 7.6 接入点

在 `_input()` 的鼠标点击处理中，当 `state` 为出牌/使用卡牌状态时保持原有逻辑；否则调用 `_try_select_tile(cell)`。

---

## 实施优先级

| 优先级 | 功能 | 复杂度 | 影响范围 |
|--------|------|--------|----------|
| P0 | 同类地块边界合并 | 低 | `_spawn_edge_trim` + 邻居刷新 |
| P0 | 道路圆环移除 + 道路优化 | 低 | `_spawn_road_fx` + `_spawn_road` |
| P0 | 缺口地块建模优化 | 低 | `_tile_gap_surface` |
| P0 | 地块选中 + 信息面板 | 中 | 新增选中状态 + Label3D 面板 |
| P1 | 建筑范围光环 | 中 | 新增 aura 系统 + 刷新逻辑 |
| P2 | 结算动效系统 | 高 | 快照对比 + 3D动效 + Label3D |
| P2 | 天气全局动效 | 高 | 粒子系统 + 环境光 + 多种天气 |

建议按 P0 → P1 → P2 顺序实施。
