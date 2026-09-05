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

## 12. 所有UI和卡牌改为方角 + 深色边框 + 立体投影

### 当前问题
- `_draw_glass_card` 使用圆角矩形（`corner_radius = 10-18`），风格偏软
- 没有明确边框，没有投影，缺乏立体感

### 方案
统一改为**直角方块**，边框颜色略深于内部，加上底部/右侧投影：

```gdscript
func _draw_flat_card(rect: Rect2, fill: Color, border: Color, shadow_offset: Vector2 = Vector2(3, 4)):
    # 1. 投影（底部偏右偏下）
    ui_ctrl.draw_rect(
        Rect2(rect.position + shadow_offset, rect.size),
        Color(0, 0, 0, 0.25), 0, false
    )
    # 2. 边框（比fill略大的深色矩形）
    var border_width = 2.0
    ui_ctrl.draw_rect(
        Rect2(rect.position - Vector2(border_width, border_width),
              rect.size + Vector2(border_width * 2, border_width * 2)),
        border, 0, false
    )
    # 3. 内部填充
    ui_ctrl.draw_rect(rect, fill, 0, false)
```

**使用场景**：
- 手牌卡牌：`_draw_flat_card(rect, base, base.darkened(0.3))`
- 右侧UI面板：`_draw_flat_card(panel_rect, glass, glass.darkened(0.15))`
- 市场卡堆：同上
- 所有现有 `_draw_glass_card` 调用替换为 `_draw_flat_card`

---

## 13. 右侧UI文字溢出窗口

### 当前问题
右侧UI面板的x坐标使用固定值（如 `vp.x - 320`），当窗口变窄时文字跑到窗口外面。

### 原因
面板宽度固定，但没有检查是否超出左边界。

### 方案
限制面板x坐标，确保不超出左边界：

```gdscript
# 在 _draw_ui() 中：
var ux = vp.x - 320.0
# 关键：确保面板不超出左边界，留至少20px边距
ux = maxf(ux, 20.0)
# 如果面板空间不足，缩小面板宽度
var panel_width = minf(280.0, vp.x - 40.0)

# 所有右侧UI元素的x坐标基于ux，而非vp.x
# 文字宽度限制：draw_string 的 width 参数设为 panel_width - 20
ui_ctrl.draw_string(font, Vector2(ux + 12, uy), "文字内容",
    HORIZONTAL_ALIGNMENT_LEFT, panel_width - 24, 14, ink)
```

**关键修改**：
1. `ux` 加 `maxf(ux, 20.0)` 下限
2. 所有 `draw_string` 的 width 参数改为 `panel_width - 24`（而非 -1 或固定值）
3. 天气信息、操作提示等底部文字也要限制宽度

### 实际完成
- 右侧面板宽度按窗口可用宽度动态限制，左右各保留 20px 安全边距。
- 标题、回合进度、播种信息、天气、结算播报、操作记录和底部快捷提示全部改用受限宽度文本。
- 玩家排名的名称、进度条和分数按 `content_width` 比例重新计算，不再依赖 60/125/50px 固定列宽。
- 操作记录按窗口剩余高度计算可见行数，避免低分辨率下越过底部提示和窗口边界。
- 验收标准：任意宽度下右侧面板及其文字不得越过窗口左右边界；低高度下操作记录不得越过底部提示。

---

## 14. 结算字幕未分散（重叠聚集）

### 当前问题
结算时多个地块的字幕Label3D同时出现，位置太近导致重叠看不清。

### 原因
`_float_label` 使用 `randf_range(-0.15, 0.15)` 的随机x偏移，但地块间距1.25，0.15的随机范围太小，相邻地块的字幕容易重叠。

### 方案
加大随机偏移 + 错开出现时间 + 相邻地块字幕分散到不同高度：

```gdscript
func _float_label(pos: Vector2i, text: String, color: Color, delay: float = 0.0):
    var label = Label3D.new()
    label.text = text; label.font_size = 22
    label.modulate = color
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.no_depth_test = true; label.pixel_size = 0.005
    label.render_priority = 90
    label.outline_modulate = Color(0, 0, 0, 0.8); label.outline_size = 8
    # 加大随机偏移范围，避免重叠
    label.position = _world(pos) + Vector3(
        randf_range(-0.35, 0.35),  # 从±0.15扩大到±0.35
        0.5 + randf_range(0, 0.15),  # y也加随机
        randf_range(-0.35, 0.35)
    )
    settle_fx_root.add_child(label)
    
    # 延迟出现，错开相邻地块的字幕
    var tw = create_tween()
    tw.tween_interval(delay)
    tw.tween_property(label, "modulate:a", 1.0, 0.01)  # 延迟后才显示
    tw.set_parallel(true)
    tw.tween_property(label, "position:y", label.position.y + 0.8, 3.0)
    tw.tween_property(label, "modulate:a", 0.0, 3.0).set_delay(1.5)
    tw.chain().tween_callback(label.queue_free)

# 在 _emit_settlement_labels 中，为每个地块加递增延迟：
var delay := 0.0
for x in _grid_width():
    for y in _grid_height():
        # ... 检测变化 ...
        if changed:
            _float_label(pos, text, color, delay)
            delay += 0.08  # 每个地块间隔0.08秒
```

---

## 实施优先级

| 优先级 | 问题 | 复杂度 | 状态 |
|--------|------|--------|------|
| P0 | ~~#1 彩虹下半部分消失 + 位置偏移到缝隙~~ | 低 | ✅ 已完成 |
| P0 | ~~#2 雨滴变大~~ | 低 | ✅ 已完成 |
| P0 | ~~#3 天气覆盖全屏+跟随相机~~ | 低 | ✅ 已完成 |
| P0 | ~~#5 信息面板字体加大+扩散信息~~ | 中 | ✅ 已完成 |
| P0 | ~~#6 结算字幕字体+颜色+时长~~ | 低 | ✅ 已完成 |
| P0 | ~~#8 开发卡地块预览（右下角）~~ | 中 | ✅ 已完成 |
| P0 | ~~#10 沙漠容量提示~~ | 低 | ✅ 已完成 |
| P0 | ~~#11 信息面板精简+行间距~~ | 中 | ✅ 已完成 |
| P0 | ~~#12 UI方角+深色边框+立体投影~~ | 中 | ✅ 已完成 |
| P0 | ~~#13 右侧UI文字溢出修复~~ | 低 | ✅ 已完成 |
| P0 | ~~#14 结算字幕分散+延迟~~ | 低 | ✅ 已完成 |
| P0 | ~~#15 可放置地块白色呼吸光效+Q/E更新~~ | 中 | ✅ 已完成 |
| P0 | ~~#16 卡牌使用条件规则文档化~~ | 低 | ✅ 已完成 |
| P0 | ~~#17 卡牌暗纹裁剪+排列修正~~ | 低 | ✅ 已完成 |
| P0 | ~~#18 UI布局优化+顶部系统信息栏~~ | 中 | ✅ 已完成 |
| P1 | ~~#4 闭合道路奖励播种卡~~ | 中 | ✅ 已完成 |
| P1 | ~~#19 道路连接两黄鹤楼变科技大厦bug~~ | 中 | ✅ 已修复 |
| P1 | ~~#20 彩虹严格只渲染上半弧~~ | 低 | ✅ 已完成 |
| P1 | ~~#21 旱季与雨季/台风互斥~~ | 低 | ✅ 已完成 |
| P1 | ~~#22 旱季追加水域退化为草地~~ | 中 | ✅ 已完成 |
| P1 | ~~#23 开发放置奖励1级播种卡~~ | 中 | ✅ 已完成 |
| P1 | ~~#7 彩虹位置偏移到地块缝隙~~ | 低 | ✅ 已完成 |
| P1 | ~~#9 手牌卡牌视觉重设计~~ | 高 | ✅ 已完成 |

---

## 15. 选中卡牌后可放置地块白色呼吸发光

### 现象
选中卡牌后，不知道哪些地块可以放置。需要在可放置的地块上显示白色呼吸光效。

### 方案

**选中卡牌时**：遍历所有地块，找出所有可放置位置，对每个可放置地块的3D模型叠加白色半透明呼吸光效。

**Q/E旋转时**：重新计算可放置位置，更新呼吸光效。

**取消选中/出牌后**：清除所有呼吸光效。

```gdscript
# 状态
var placement_highlights := []  # 存储当前呼吸光效节点

func _update_placement_highlights():
    """清除旧光效，为当前选中卡牌的所有可放置位置生成白色呼吸光效"""
    _clear_placement_highlights()
    var card = _selected_card()
    if card.is_empty(): return

    # 遍历所有地块，找出可放置位置
    for x in _grid_width():
        for y in _grid_height():
            var pos = Vector2i(x, y)
            if _can_play_selected_card_at(pos):
                _spawn_tile_breathing_glow(pos)

func _can_play_selected_card_at(pos: Vector2i) -> bool:
    """检查当前选中的卡牌能否在pos处使用（复用已有逻辑）"""
    var card = _selected_card()
    if card.is_empty(): return false
    match card["kind"]:
        "seed":
            return _can_seed(pos)
        "develop":
            return _can_develop_cells(_develop_card_cells(pos, int(card["level"]), piece_rotation))
        "building_develop":
            var cells = [pos] if int(card["level"]) == 1 else [pos, pos + DIRS[piece_rotation]]
            for cell in cells:
                if not _in_bounds(cell) or grid[cell.x][cell.y] != T_GAP: return false
            return true
        "road":
            # 道路卡需要拖拽路径，暂不做全图高亮
            return false
    return false

func _spawn_tile_breathing_glow(pos: Vector2i):
    """在地块模型上叠加白色半透明呼吸光效"""
    var glow = MeshInstance3D.new()
    var gm = BoxMesh.new(); gm.size = Vector3(1.06, 0.06, 1.06)
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
    glow.set_meta("placement_glow", true)
    grid_root.add_child(glow)
    placement_highlights.append(glow)

    # 呼吸脉冲动画（共用同一个mat引用）
    var tw = create_tween().set_loops()
    tw.tween_property(mat, "albedo_color:a", 0.30, 0.8).set_trans(Tween.TRANS_SINE)
    tw.tween_property(mat, "albedo_color:a", 0.10, 0.8).set_trans(Tween.TRANS_SINE)
    var tw2 = create_tween().set_loops()
    tw2.tween_property(mat, "emission_energy_multiplier", 0.6, 0.8).set_trans(Tween.TRANS_SINE)
    tw2.tween_property(mat, "emission_energy_multiplier", 0.15, 0.8).set_trans(Tween.TRANS_SINE)

func _clear_placement_highlights():
    """清除所有呼吸光效"""
    for glow in placement_highlights:
        if is_instance_valid(glow): glow.queue_free()
    placement_highlights.clear()
```

### 接入点

1. **选中卡牌时**（`_select_card` / 点击手牌）：调用 `_update_placement_highlights()`
2. **Q/E旋转时**（`piece_rotation` 改变后）：调用 `_update_placement_highlights()` 重新计算
3. **取消选中/出牌后**（`_cancel_armed_card` / 打出卡牌后）：调用 `_clear_placement_highlights()`

```gdscript
# Q/E旋转接入（已有逻辑，追加调用）：
elif state == S.PLAY_CARDS and event.keycode == KEY_Q:
    piece_rotation = posmod(piece_rotation - 1, 4)
    _update_placement_highlights()  # 新增
    ui_ctrl.queue_redraw()
elif state == S.PLAY_CARDS and event.keycode == KEY_E:
    piece_rotation = posmod(piece_rotation + 1, 4)
    _update_placement_highlights()  # 新增
    ui_ctrl.queue_redraw()
```

---

## 16. 各类卡牌使用条件判断规则（完整）

### 播种卡

| 条件 | 说明 |
|------|------|
| `grid[pos]` 是植物地块 | 森林/草地/荒漠 ✓，水域/建筑/山体/缺口 ✗ |
| `_flower_total(pos) < _tile_capacity(pos)` | **花朵未满** ✓，已满 ✗ |
| `seeds[current_player] > 0` | 有剩余种子 ✓，用完 ✗ |
| 不检查道路状态 | 有道路的地块也可以播种（但播种后不扩散） |

**已满判定**：`_flower_total(pos)` 统计所有玩家花朵总和，与地块容量对比。
- 森林容量100，草地50，荒漠10
- 建筑相邻时容量翻倍（×2，不叠加）

### 开发卡（山体开发）

| 条件 | 说明 |
|------|------|
| 形状覆盖的所有格子都是 `T_MOUNTAIN` | 不能覆盖缺口/已开发地块 |
| 至少有一格与已开发地块相邻 | 不能在孤立山体中开发 |
| 形状不越界 | 所有格子在棋盘范围内 |

### 建筑开发卡

| 条件 | 说明 |
|------|------|
| 形状覆盖的所有格子都是 `T_GAP` | 只能作用于缺口 |
| 不越界 | 所有格子在棋盘范围内 |
| 不检查相邻条件 | 缺口本身已满足"被包围"条件 |

### 道路卡

| 条件 | 说明 |
|------|------|
| 路径长度 = 卡牌等级 + 1 | 1级=2格，2级=3格，3级=4格 |
| 路径上所有格子不是可开发地块 | 山体/缺口不能修路 |
| 路径连续 | 相邻格子必须上下左右相邻 |
| 不检查已有道路 | 可以在已有道路上叠加（增加连接方向） |

### 天气卡

| 条件 | 说明 |
|------|------|
| 无位置限制 | 任何时候都可以打出 |
| 同类型不叠加 | 已有台风时再打台风无效，且不消耗卡牌 |

### 通用规则

| 规则 | 说明 |
|------|------|
| 每回合可打出任意数量卡牌 | 无出牌上限 |
| 右键/ESC 取消选中 | 退出放置模式 |
| 无可用位置时提示 | "当前卡牌无法使用" + 自动退回 |
| Q/E 旋转更新可放置区域 | 旋转后重新计算并刷新呼吸光效 |

---

## 呼吸光效接入（#15补充）

将 `_can_play_selected_card_at()` 统一调用 `_can_play_selected_card(pos)`：

```gdscript
func _can_play_selected_card_at(pos: Vector2i) -> bool:
    return _can_play_selected_card(pos)
```

已有的 `_can_play_selected_card()` 已包含所有判断逻辑（播种满检测、开发卡山体检测、建筑缺口检测等），无需重复实现。

---

## 17. 卡牌暗纹溢出 + 排列不整齐

### 问题1：暗纹超出卡牌边界

**原因**：`_draw_repeating_card_pattern` 在固定位置绘制图案（line/circle），当卡牌尺寸较小或位置偏移时，图案可能绘制到卡牌rect之外。Godot的 `draw_line`/`draw_circle` 不会自动裁剪。

**方案**：在绘制暗纹前设置裁剪区域：

```gdscript
func _draw_repeating_card_pattern(rect: Rect2, kind: String, color: Color):
    # 裁剪到卡牌区域内
    ui_ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    # 使用 clip_rect 限制绘制区域（Godot 4 的 Control 没有原生 clip，
    # 但可以通过手动检查坐标来避免越界）
    
    for row in 5:
        var center = rect.position + Vector2(16 + (row % 2) * 31, 43 + row * 22)
        for column in 2:
            var p = center + Vector2(column * 55, -column * 13)
            # 检查图案中心是否在卡牌范围内
            if not rect.has_point(p): continue
            # ... 原有绘制逻辑 ...
```

**更简洁的方案**：缩小暗纹的行数和偏移，确保所有图案都在rect内：

```gdscript
func _draw_repeating_card_pattern(rect: Rect2, kind: String, color: Color):
    for row in 4:  # 5行→4行，避免底部溢出
        var center = rect.position + Vector2(12 + (row % 2) * 25, 40 + row * 24)
        for column in 2:
            var p = center + Vector2(column * 42, -column * 10)  # 缩小偏移
            # ... 绘制逻辑 ...
```

### 问题2：手牌排列不整齐

**原因**：`_bottom_card_rect` 的step计算在卡牌多时过度压缩（step最小值无下限），导致卡牌完全重叠。

**方案**：限制最小step，超出空间时居中排列并允许溢出滚动：

```gdscript
func _bottom_card_rect(index: int, count: int, vp: Vector2) -> Rect2:
    var card_size = Vector2(100, 145)  # 略微缩小卡牌
    var available = maxf(250.0, vp.x - UI_SIDEBAR_WIDTH - 50.0)
    var min_step = 32.0  # 最小间距，保证卡牌不完全重叠
    var step = maxf(min_step, minf(65.0, (available - card_size.x) / maxf(float(count - 1), 1.0)))
    var total_width = card_size.x + step * maxf(float(count - 1), 0.0)
    var start_x = maxf(20.0, (available - total_width) * 0.5 + 20.0)
    var y = vp.y - 105.0
    if index == hovered_card_index or index == selected_card: y -= 25.0
    return Rect2(Vector2(start_x + index * step, y), card_size)
```

**关键改动**：
1. `min_step = 32.0` — 保证卡牌之间至少有32px间距，不完全重叠
2. 卡牌尺寸从112×158缩小到100×145 — 给排列更多空间
3. `start_x` 加 `maxf(20.0, ...)` — 防止左侧溢出

---

## 18. UI布局优化 + 顶部系统信息栏

### 问题1：右侧UI排版混乱

当前 `_draw_ui` 中右侧面板各区块位置用硬编码偏移（`sy+70`, `sy+92`, `sy+243`等），字体大小不统一（12-22混用），间距不一致。

**方案**：统一字号体系 + 规范间距：

```
标题字号: 18
副标题: 14
正文: 12-13
辅助: 10-11

区块间距: 16px
行间距: 22px
面板内边距: 12px
```

### 问题2：缺少顶部系统信息栏

玩家需要随时看到各类地块的**实际生长率**（受天气影响）和**升级/降级概率翻倍状态**。

**方案**：在屏幕顶部（跨越整个窗口宽度）添加一个系统信息栏：

```gdscript
func _draw_top_info_bar(vp: Vector2, font: Font, ink: Color, muted: Color):
    var bar_y = 8.0
    var bar_h = 36.0
    _draw_flat_card(Rect2(8, bar_y, vp.x - 16, bar_h),
        Color(0.08, 0.10, 0.12, 0.82), Color(0.3, 0.35, 0.3, 0.6))

    var x = 20.0
    var terrain_colors = [
        Color("#5fae55"),  # 草地
        Color("#3f94bd"),  # 水域
        Color("#2f7048"),  # 森林
        Color("#c8944e"),  # 荒漠
    ]
    var terrain_names_short = ["草", "水", "林", "漠"]
    var caps = [50, 0, 100, 10]
    var base_rates = [0.3, 0.0, 0.5, 0.1]

    for i in 4:
        var rate = base_rates[i]
        # 天气影响
        if _has_extreme_weather(): rate *= 0.5
        if rainbow_turns > 0: rate *= 2.0

        # 色块
        ui_ctrl.draw_rect(Rect2(x, bar_y + 8, 14, 14), terrain_colors[i], 0, true, 3.0)
        # 名称 + 生长率
        var text = "%s %.1f" % [terrain_names_short[i], rate]
        ui_ctrl.draw_string(font, Vector2(x + 18, bar_y + 20), text,
            HORIZONTAL_ALIGNMENT_LEFT, 60, 12, Color("#d0d8d4"))
        x += 82.0

    # 分隔线
    ui_ctrl.draw_line(Vector2(x, bar_y + 6), Vector2(x, bar_y + bar_h - 6),
        Color(1, 1, 1, 0.15), 1.0)
    x += 12.0

    # 升级/降级翻倍状态
    var upgrade_text = "升级"
    var downgrade_text = "降级"
    var up_color = Color("#88aa88", 0.6)
    var down_color = Color("#aa8888", 0.6)

    if active_weather.has("雨季"):
        upgrade_text = "升级×2"
        up_color = Color("#60dd80")
    if active_weather.has("旱季"):
        downgrade_text = "降级×2"
        down_color = Color("#dd6060")
    if rainbow_turns > 0:
        upgrade_text = "升级×2"
        up_color = Color("#60dd80")

    ui_ctrl.draw_string(font, Vector2(x, bar_y + 15), upgrade_text,
        HORIZONTAL_ALIGNMENT_LEFT, 60, 12, up_color)
    ui_ctrl.draw_string(font, Vector2(x, bar_y + 30), downgrade_text,
        HORIZONTAL_ALIGNMENT_LEFT, 60, 12, down_color)
    x += 72.0

    # 当前天气（紧凑显示）
    if not active_weather.is_empty() or rainbow_turns > 0:
        ui_ctrl.draw_line(Vector2(x, bar_y + 6), Vector2(x, bar_y + bar_h - 6),
            Color(1, 1, 1, 0.15), 1.0)
        x += 12.0
        var wt = ""
        for w in active_weather.keys(): wt += "%s%d " % [w, active_weather[w]]
        if rainbow_turns > 0: wt += "彩虹 "
        ui_ctrl.draw_string(font, Vector2(x, bar_y + 22), wt.strip_edges(),
            HORIZONTAL_ALIGNMENT_LEFT, 200, 12, Color("#d4c080"))
```

### 在 `_draw_ui()` 中调用

```gdscript
func _draw_ui():
    # ... 现有逻辑 ...
    if state == S.TITLE: _draw_title(vp, font); return
    if state == S.GAME_OVER: _draw_gameover(vp, font); return

    _draw_top_info_bar(vp, font, ink, muted)  # 新增：顶部信息栏

    # 右侧UI的 uy 从30改为50（为顶部栏留空间）
    var ux = maxf(vp.x - 320.0, 20.0); var uy = 50.0
    # ... 后续布局 ...
```

### 信息栏内容总结

| 位置 | 内容 | 说明 |
|------|------|------|
| 最左 | 🟢草0.3 🔵水0.0 🟢林0.5 🟡漠0.1 | 各地形实际生长率（受天气影响实时变化） |
| 中间 | 升级 / 降级 | 雨季时升级变绿×2，旱季时降级变红×2 |
| 右侧 | 当前天气 | 台风3 沙尘暴2 等 |

---

## 19. Bug：道路连接两个相邻黄鹤楼时预览变科技大厦

### 现象
当两个1×1的黄鹤楼建筑相邻放置，使用道路卡连接它们时，黄鹤楼的模型/预览会变成洪山科技大厦（1×2双格建筑）的样式。

### 原因推测
`_apply_road_path` 或 `_redraw_tile` 在重建建筑地块视觉时，可能错误地将两个相邻的1×1建筑识别为一个2×1的洪山科技大厦。`special_buildings` 字典的 key 逻辑可能在道路重绘时被错误覆盖。

### 修复
1. 普通黄鹤楼不写入 `special_buildings`，只有洪山科技大厦写入 `hongshan_tech` 元数据。
2. 道路重绘只读取现有 `special_buildings`，不会把相邻两个1×1建筑重新识别为1×2建筑。
3. `_apply_building_develop_card()` 在1级建筑放置时清理当前位置元数据，避免旧的2格建筑残留。

---

## 20. 彩虹严格只显示上半部分

### 现象
目前彩虹已经被抬高并移动到地块缝隙中心，但实现上仍可能是完整环形或接近完整环形，只是下半部分被场景遮挡。视觉上需要明确为“上半拱桥”，不能依赖遮挡来假装隐藏。

### 方案
- 将彩虹从 `TorusMesh` 改为自定义半圆弧 mesh，角度只生成 `0..PI`。
- 每道颜色独立生成一条半圆带，保留透明材质和轻微 emission。
- 彩虹位置仍固定在地块缝隙中心，不随天气根节点平移。
- 下半部分不生成任何顶点，因此从任何视角都不会看到完整圆环。

### 验收
- 画面中只能看到上半彩虹弧线。
- 相机移动后彩虹仍在原地块缝隙位置。
- 不出现地面遮挡造成的“断圈”或“露出下半圈”。

---

## 21. 旱季与雨季/台风互斥

### 现象
当前天气可以叠加，旱季可能和雨季、台风同时存在，规则语义冲突：旱季代表干燥退水，雨季/台风代表降水增强。

### 方案
- 打出旱季时，移除 `雨季` 和 `台风`。
- 打出雨季或台风时，移除 `旱季`。
- 沙尘暴是否与旱季共存暂时保留，因为二者都偏干燥，可以形成叠加压力。
- 彩虹仍然清除所有极端天气。

### 验收
- `active_weather` 中不会同时存在 `旱季` 与 `雨季`。
- `active_weather` 中不会同时存在 `旱季` 与 `台风`。
- 顶部天气信息栏同步显示互斥后的结果。

---

## 22. 旱季追加：水域退化为草地

### 现象
旱季目前只放大植物地块降级概率，但没有直接影响水域，导致“干旱”表现不够明确。

### 方案
- 回合结算时，如果存在 `旱季`，每个水域有概率退化为草地。
- 建议基础概率：每个水域每回合 `30%` 变为草地。
- 山体、缺口、建筑不受影响。
- 若水域变为草地，需要调用地块重绘、边框/顶层连接、道路连接更新和邻居边框刷新。

### 验收
- 旱季回合结束后，部分水域会变为草地。
- 水域退化后不会破坏已有道路数据；如果该格有道路，草地上继续显示道路。
- 地块改变后接缝状态立即更新。

---

## 23. 开发放置奖励1级播种卡

### 现象
开发行为消耗开发资源但没有即时手牌回补，玩家会更倾向保守出牌。

### 方案
- 使用普通山体开发卡并成功放置后，当前玩家获得1张最低级播种卡。
- 使用建筑开发卡并成功放置后，当前玩家也获得1张最低级播种卡。
- 奖励只在成功放置后发放，取消预览、非法放置、未消耗卡牌时不发放。
- 操作播报加入“开发完成，获得1级播种卡”。

### 验收
- 普通开发卡成功后，当前玩家手牌增加1张1级播种卡。
- 黄鹤楼、洪山科技大厦等建筑开发卡成功后，当前玩家手牌增加1张1级播种卡。
- 失败放置不会发放奖励。
