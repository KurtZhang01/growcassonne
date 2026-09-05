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

## 实施优先级

| 优先级 | 问题 | 复杂度 |
|--------|------|--------|
| P0 | #3 天气覆盖全屏+跟随相机 | 低 |
| P0 | #2 雨滴变大 | 低 |
| P0 | #1 彩虹下半部分消失 | 低 |
| P0 | #5 信息面板字体加大+扩散信息 | 中 |
| P0 | #6 结算字幕字体+颜色+时长 | 低 |
| P1 | #4 闭合道路奖励播种卡 | 中 |
