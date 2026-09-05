# Bug修复与功能补充清单 v3

---

## 1. 彩虹只显示上半部分

**原因**：TorusMesh 旋转 `rotation_degrees.x = 90` 后，底部被地块/地形遮挡。彩虹环直径太大（2.9~3.74），只有上半弧露出地面。

**方案**：
- 缩小彩虹环半径，使其完全在棋盘上方可见
- 或将彩虹抬高到不被遮挡的位置
- 或改用两个半圆弧（只渲染上半部分）代替完整环形

```gdscript
# 方案A：缩小半径 + 抬高
tm.inner_radius = 1.5 + index * 0.06
tm.outer_radius = tm.inner_radius + 0.06
ring.position = center + Vector3(0, 2.0, 0)  # 抬高避免遮挡

# 方案B：改用上半弧（PrismMesh拼接或只渲染上半部分的自定义mesh）
```

---

## 2. 雨滴变大更明显

**当前**：雨滴 CylinderMesh 半径 0.004，高度 0.08（台风）/ 0.06（雨季），视觉上几乎看不见。

**方案**：加大雨滴尺寸，增加数量，调亮颜色：

```gdscript
# 台风雨滴
dm.top_radius = 0.008; dm.bottom_radius = 0.008; dm.height = 0.15
# 材质更亮
rain_mat.albedo_color = Color(0.5, 0.65, 0.9, 0.55)
# 数量从40增加到60

# 雨季雨滴
dm.top_radius = 0.006; dm.bottom_radius = 0.006; dm.height = 0.12
rain_mat.albedo_color = Color(0.5, 0.65, 0.9, 0.40)
# 数量从25增加到40
```

---

## 3. 天气覆盖全屏 + 随摄像机移动

**当前**：`weather_fx_root` 使用棋盘中心的固定坐标生成特效，相机平移后特效可能偏出视野。之前有跟随相机的代码但被移除了（会导致彩虹也跟随）。

**方案**：恢复天气跟随相机的代码，但**彩虹除外**（彩虹独立为不跟随的节点）：

```gdscript
# _process() 中：
if weather_fx_root.has_meta("weather_center"):
    var weather_center: Vector3 = weather_fx_root.get_meta("weather_center")
    weather_fx_root.position = Vector3(
        cam_offset.x - weather_center.x,
        0,
        cam_offset.y - weather_center.z
    )

# 彩虹不放在 weather_fx_root 下，而是独立放在场景根节点
# 或者彩虹节点设置 set_meta("no_follow", true)，在跟随逻辑中跳过
```

具体实现：
```gdscript
# 方案A：彩虹独立容器
var rainbow_fx_root: Node3D  # 不跟随相机

# 方案B：在 _process 中只移动非彩虹节点
for child in weather_fx_root.get_children():
    if not child.has_meta("rainbow"):
        child.position += delta_offset  # 只移动非彩虹
```

---

## 4. 道路闭合奖励：获得初级播种卡

**当前**：闭合道路只在视觉上有金色光圈效果，没有游戏性奖励。

**方案**：在 `_refresh_road_effects()` 中检测到新闭合道路时，为该闭合区域内的对应玩家发放1张1级播种卡。

```gdscript
func _refresh_road_effects():
    # ... 现有闭合检测逻辑 ...
    if closed:
        # 找出闭合区域内的所有地块
        for cell in component:
            # 找出该地块上有花朵的玩家
            for pid in player_count:
                if flowers[cell.x][cell.y][pid] > 0:
                    # 该玩家获得1张1级播种卡
                    _grant_seed_card(pid, 1)
        if not closed_road_ids.has(component_id):
            last_road_event = "道路闭合！区域内玩家获得播种卡"

func _grant_seed_card(pid: int, level: int):
    """给玩家发放一张指定等级的播种卡"""
    var card = {
        "kind": "seed",
        "level": level,
        "name": "%d级播种" % level,
        "deck": "播种"
    }
    hands[pid].append(card)
```

**注意**：需要追踪哪些闭合道路已经发放过奖励（避免每回合重复发放）。复用现有的 `closed_road_ids` 字典。

---

## 5. 地块信息面板字体加大 + 最前显示 + 扩散概率/生长率

**当前**：Label3D 字体大小 13-16，可能被地形遮挡。

**方案**：

```gdscript
# 字体加大
label.font_size = 20  # 原来13-16，统一加大
label.pixel_size = 0.005  # 更精细的像素

# 最前显示
label.no_depth_test = true  # 已有
label.billboard = BaseMaterial3D.BILLBOARD_ENABLED  # 已有
# 新增：设置渲染优先级
label.render_priority = 100  # 确保在最前面

# 补充扩散概率和生长率信息
func _spawn_tile_info_panel(pos: Vector2i):
    # ... 现有信息 ...
    
    # 生长率（考虑天气影响）
    var rate: float = TERRAIN_GROWTH[grid[pos.x][pos.y]]
    if _has_extreme_weather(): rate *= 0.5
    if rainbow_turns > 0: rate *= 2.0
    lines.append({"text": "实际生长率：%.1f" % rate, "color": Color("#88ddaa"), "size": 16})
    
    # 扩散概率
    if roads[pos.x][pos.y] == 0:
        var spread_info = _calc_spread_info(pos)
        lines.append({"text": "扩散概率：%s" % spread_info, "color": Color("#aaddff"), "size": 16})
    else:
        lines.append({"text": "道路地块：不可扩散", "color": Color("#dd8888"), "size": 16})

func _calc_spread_info(pos: Vector2i) -> String:
    """计算并格式化扩散信息"""
    var free = _tile_capacity(pos) - _flower_total(pos)
    if free <= 0: return "已满"
    var neighbor_sum := 0
    for dir in DIRS:
        var n = pos + dir
        if _in_bounds(n) and _is_plant_terrain(grid[n.x][n.y]):
            for pid in player_count:
                neighbor_sum += flowers[n.x][n.y][pid]
    if neighbor_sum == 0: return "无邻居花朵"
    return "有 %d 空位，邻居 %d 朵" % [free, neighbor_sum]
```

---

## 6. 结算字幕字体加大 + 颜色区分 + 持续时间延长

**当前**：Label3D 字体14，2秒后消失。

**方案**：

```gdscript
func _float_label(pos: Vector2i, text: String, color: Color):
    var label = Label3D.new()
    label.text = text
    label.font_size = 22  # 原来14，加大
    label.modulate = color
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.no_depth_test = true
    label.pixel_size = 0.005  # 更精细
    label.render_priority = 90  # 最前面
    label.outline_modulate = Color(0, 0, 0, 0.8)
    label.outline_size = 8  # 黑色描边，更清晰
    label.position = _world(pos) + Vector3(randf_range(-0.15, 0.15), 0.5, 0)
    settle_fx_root.add_child(label)
    
    var tw = create_tween()
    tw.set_parallel(true)
    tw.tween_property(label, "position:y", label.position.y + 0.8, 3.0)  # 2秒→3秒
    tw.tween_property(label, "modulate:a", 0.0, 3.0).set_delay(1.5)  # 1.5秒后开始淡出
    tw.chain().tween_callback(label.queue_free)

# 颜色对应规则：
# 花朵增加：玩家颜色
# 地块变化：金色 (#e8c840)
# 花朵扩散：浅蓝色 (#aaddff)
# 道路闭合：亮绿色 (#60ff80)
```

---

## 7. 彩虹位置偏移到地块缝隙中

**当前**：彩虹中心在棋盘中心（地块中央），环形直接套在地块上。

**方案**：彩虹中心偏移到地块与地块的缝隙交汇处（4格交汇点），而非地块中心。

```gdscript
# 棋盘中心在 grid[3][3] 和 grid[4][4] 的缝隙处
# TILE_SPACING = 1.25，地块中心间距1.25
# 缝隙位置 = 地块中心 + TILE_SPACING * 0.5

# 计算棋盘中心的缝隙坐标
var grid_center = Vector3(
    (_grid_width() / 2.0) * TILE_SPACING,  # 缝隙X
    0,
    (_grid_height() / 2.0) * TILE_SPACING   # 缝隙Y
)

# 彩虹中心放在缝隙处
ring.position = grid_center + Vector3(0, 2.0, 0)
ring.rotation_degrees.x = 90
```

如果棋盘是8×8，中心缝隙在 grid[3][4] 和 grid[4][3] 之间（坐标约 [3.75, 0, 3.75]）。

---

## 8. 开发卡牌地块预览（右下角固定位置）

**当前**：使用开发卡时，鼠标悬浮在棋盘上才显示预览形状，离开棋盘就看不到。

**方案**：在屏幕**右下角固定位置**显示完整的卡牌地块形状预览，展示所有格子的地形类型（随机生成），并随Q/E旋转同步更新。

```gdscript
# 右下角预览面板
# 在 _draw_ui() 中绘制

func _draw_develop_preview_panel(vp: Vector2, font: Font):
    """右下角绘制开发卡的完整地块形状预览"""
    var card = _selected_card()
    if card.is_empty() or card["kind"] != "develop": return
    
    # 获取当前旋转下的地块形状
    var cells = _develop_card_cells(Vector2i.ZERO, int(card["level"]), piece_rotation)
    if cells.is_empty(): return
    
    # 随机roll每个格子的地形类型（展示可能的结果）
    var terrains := []
    for i in cells.size():
        terrains.append(_draw_terrain())
    
    # 计算形状的包围盒
    var min_cell = cells[0]; var max_cell = cells[0]
    for cell in cells:
        min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
        max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
    var shape_size = Vector2(max_cell.x - min_cell.x + 1, max_cell.y - min_cell.y + 1)
    
    # 预览面板参数
    var cell_px = 28.0  # 每个小格子像素大小
    var panel_w = shape_size.x * cell_px + 20
    var panel_h = shape_size.y * cell_px + 50
    var panel_x = vp.x - panel_w - 20
    var panel_y = vp.y - panel_h - 20
    
    # 绘制面板背景
    _draw_glass_card(Rect2(panel_x, panel_y, panel_w, panel_h),
        Color(0.1, 0.12, 0.15, 0.85), Color(1, 1, 1, 0.3))
    
    # 标题
    ui_ctrl.draw_string(font,
        Vector2(panel_x + 10, panel_y + 18),
        "地块预览（Q/E旋转）",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ccccaa"))
    
    # 绘制每个格子
    var origin = Vector2(panel_x + 10, panel_y + 30)
    for i in cells.size():
        var local = cells[i] - min_cell
        var cell_rect = Rect2(
            origin + Vector2(local.x, local.y) * cell_px,
            Vector2(cell_px - 2, cell_px - 2)
        )
        # 地形色块
        ui_ctrl.draw_rect(cell_rect, TERRAIN_TOP[terrains[i]], true, 4.0)
        # 地形名称缩写
        var abbrev = ["草", "水", "林", "沙", "建", "山", "缺"][terrains[i]]
        ui_ctrl.draw_string(font,
            cell_rect.position + Vector2(6, 20),
            abbrev,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
```

**效果**：
- 右下角固定显示卡牌的完整形状（如L形、T形、2×2等）
- 每个格子显示随机生成的地形颜色和名称缩写
- 按Q/E旋转时，预览形状同步旋转
- 使用建筑开发卡时，直接显示"建"字
- 面板在不使用卡牌时自动隐藏

---

## 9. 手牌卡牌视觉重设计

### 当前问题
- 卡牌使用 `_draw_glass_card`（方框+边框），视觉僵硬
- 选中/悬停用高光边框区分，不自然
- 卡牌平铺排列，没有扇形展开
- 后排卡牌没有遮挡阴影

### 设计方向（参考杀戮尖塔/炉石传说）
- 卡牌底部渐变背景（无边框）
- 选中卡牌上浮+放大
- 扇形排列，间距自适应
- 后排卡牌有半透明遮罩阴影

### 实现方案

```gdscript
func _draw_hand_cards(vp: Vector2, font: Font):
    var count = current_hand.size()
    if count == 0: return

    # 扇形参数
    var card_w = 100.0; var card_h = 145.0
    var fan_center_x = vp.x * 0.5
    var fan_y = vp.y - 90.0  # 扇形底部
    var max_fan_angle = 15.0  # 最大扇形角度（度）
    var fan_radius = 600.0  # 扇形半径（越大弧度越平）

    # 计算每张卡的角度和位置
    for draw_index in range(count - 1, -1, -1):
        var i = draw_index
        var card = current_hand[i]
        var is_selected = (i == selected_card)
        var is_hovered = (i == hovered_card_index)

        # 扇形角度
        var t = (float(i) / maxf(float(count - 1), 1.0) - 0.5)  # -0.5 ~ 0.5
        var angle = t * max_fan_angle
        var rad = deg_to_rad(angle)

        # 卡牌中心位置
        var cx = fan_center_x + sin(rad) * fan_radius * 0.15
        var cy = fan_y - cos(rad) * fan_radius * 0.02

        # 选中/悬停上浮
        if is_selected or is_hovered:
            cy -= 30.0

        var rect = Rect2(
            Vector2(cx - card_w * 0.5, cy - card_h),
            Vector2(card_w, card_h)
        )

        # ---- 绘制卡牌 ----
        var accent = _card_accent(card)
        var base = _card_base_color(card)

        # 1. 阴影（后排卡牌更深）
        var shadow_alpha = 0.15 + (1.0 - float(i) / maxf(float(count), 1.0)) * 0.1
        var shadow_rect = Rect2(rect.position + Vector2(3, 5), rect.size)
        ui_ctrl.draw_rect(shadow_rect, Color(0, 0, 0, shadow_alpha), 0, true, 10.0)

        # 2. 卡牌背景渐变（无边框）
        # 上半部分：accent色渐变到base色
        # 下半部分：base色
        var gradient_top = accent.lerp(base, 0.3)
        var gradient_mid = base
        var gradient_bot = base.darkened(0.15)

        # 上部渐变条（卡牌顶部彩色区域）
        var top_strip = Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.35))
        ui_ctrl.draw_rect(top_strip, gradient_top, 0, true, 10.0)
        # 中部
        var mid_strip = Rect2(rect.position + Vector2(0, rect.size.y * 0.35),
            Vector2(rect.size.x, rect.size.y * 0.45))
        ui_ctrl.draw_rect(mid_strip, gradient_mid, 0, false)
        # 底部
        var bot_strip = Rect2(rect.position + Vector2(0, rect.size.y * 0.80),
            Vector2(rect.size.x, rect.size.y * 0.20))
        ui_ctrl.draw_rect(bot_strip, gradient_bot, 0, true, 10.0)

        # 3. 微弱内发光（选中时）
        if is_selected:
            var glow = Color(accent.r, accent.g, accent.b, 0.20)
            ui_ctrl.draw_rect(rect, glow, 0, true, 10.0)

        # 4. 卡牌内容
        _draw_repeating_card_pattern(rect, card["kind"], base.darkened(0.10))
        _draw_fitted_text(card["name"],
            Rect2(rect.position + Vector2(8, 12), Vector2(rect.size.x - 16, 20)),
            font, 13, Color("#f0ece4"))
        _draw_card_symbol(card, rect.get_center() + Vector2(0, -8), accent.lightened(0.2))
        _draw_fitted_text(_card_description(card),
            Rect2(rect.position + Vector2(6, rect.size.y - 40), Vector2(rect.size.x - 12, 16)),
            font, 10, Color("#d8d0c0"))
        _draw_fitted_text(card["deck"],
            Rect2(rect.position + Vector2(6, rect.size.y - 20), Vector2(rect.size.x - 12, 14)),
            font, 9, Color("#a09888"))

        # 5. 旋转弧度（整张卡旋转）
        ui_ctrl.draw_set_transform(rect.get_center(), rad * 0.3, Vector2.ONE)
        # ... 绘制内容后重置 transform
        ui_ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
```

### 关键变化
| 项目 | 原来 | 改为 |
|------|------|------|
| 背景 | `_draw_glass_card` 方框 | 三段渐变（accent→base→dark） |
| 边框 | 有明确边框线 | **无边框**，靠渐变和阴影区分 |
| 选中 | 高亮边框 | 上浮30px + 微弱内发光 |
| 排列 | 水平平铺 | 扇形展开，卡牌微旋转 |
| 阴影 | 无 | 每张卡底部有半透明阴影，后排更深 |

---

## 10. 沙漠地块种花问题排查

### 现象
沙漠地块无法播种花朵。

### 分析
- `_can_seed()` 要求：`_is_plant_terrain(terrain)` ✓（沙漠是植物地块）+ 容量未满 + 有种子
- `TERRAIN_CAPACITY` 沙漠 = **10**（非常小）
- `_add_flowers()` 检查 `free = capacity - _flower_total(pos)`，若已满返回 false
- 光幕/粒子是 MeshInstance3D，`_mouse_to_grid()` 用数学射线检测（非物理碰撞），**不会阻挡点击**

### 结论
**最可能原因**：沙漠容量仅10，扩散和播种很容易填满。建议：
1. 在信息面板中明确显示"沙漠容量：10，已满"提示
2. 考虑是否需要提高沙漠容量（如改为20）

---

## 11. 地块信息面板文字拥挤

### 现象
地块上显示的各玩家花朵数量和地块属性文字互相重叠，看不清。

### 原因
当前所有信息用 Label3D 堆叠在地块上方，行间距太小（line_height = 0.12），且字体大小13-16在3D空间中很密。

### 方案
1. **加大行间距**：line_height 从 0.12 → **0.16**
2. **精简信息**：去掉冗余行（如"相邻增益"可以只显示数量，不显示详细描述）
3. **分层显示**：
   - 第一行：地块名称 + 容积（如"森林 42/100"）
   - 第二行：各玩家花朵（用玩家颜色圆点+数字，一行显示所有玩家）
   - 第三行：生长率 + 道路状态
4. **字体统一加大**：font_size 统一为 18-20
5. **位置抬高**：基准 y 从 0.55 → **0.70**，避免与地形装饰重叠

```gdscript
# 精简版信息面板
func _spawn_tile_info_panel(pos: Vector2i):
    var base_pos = _world(pos) + Vector3(0, 0.70, 0)
    var line_height = 0.16
    var lines := []

    # 第1行：地块名 + 容积
    var name = TERRAIN_NAMES[terr]
    var cap = _tile_capacity(pos)
    var total = _flower_total(pos)
    lines.append({
        "text": "%s  %d/%d" % [name, total, cap],
        "color": TERRAIN_TOP[terr].lightened(0.3),
        "size": 20
    })

    # 第2行：各玩家花朵（一行紧凑显示）
    var flower_parts := []
    for pid in player_count:
        var amount = flowers[pos.x][pos.y][pid]
        if amount > 0:
            flower_parts.append({"pid": pid, "amount": amount})
    if not flower_parts.is_empty():
        var text = ""
        for part in flower_parts:
            text += "%s:%d " % [PLAYER_NAMES[part["pid"]].substr(0, 2), part["amount"]]
        lines.append({"text": text.strip_edges(), "color": Color.WHITE, "size": 16})

    # 第3行：生长率 + 状态
    if _is_plant_terrain(terr):
        var rate = TERRAIN_GROWTH[terr]
        if _has_extreme_weather(): rate *= 0.5
        if rainbow_turns > 0: rate *= 2.0
        var road_status = "路" if roads[pos.x][pos.y] != 0 else ""
        lines.append({
            "text": "生长%.1f %s" % [rate, road_status],
            "color": Color("#88ddaa"), "size": 16
        })
```

---

## 实施优先级

| 优先级 | 问题 | 复杂度 |
|--------|------|--------|
| P0 | #3 天气覆盖全屏+跟随相机 | 低 |
| P0 | #2 雨滴变大 | 低 |
| P0 | #1 彩虹下半部分消失 + 位置偏移到缝隙 | 低 |
| P0 | #5 信息面板字体加大+扩散信息 | 中 |
| P0 | #6 结算字幕字体+颜色+时长 | 低 |
| P0 | #8 开发卡地块预览（右下角） | 中 |
| P0 | #10 沙漠容量提示 | 低 |
| P0 | #11 信息面板精简+行间距 | 中 |
| P1 | #4 闭合道路奖励播种卡 | 中 |
| P1 | #7 彩虹位置偏移到地块缝隙 | 低 |
| P1 | #9 手牌卡牌视觉重设计 | 高 |
