# 花满洪山 — 开始页面重设计 v2

---

## 1. 命名变更

| 原文 | 改为 |
|------|------|
| 花之江城 | 花满洪山 |
| Wuhan in Bloom | Hongshan in Bloom |
| 蔓延江城 | 蔓延洪山 |

涉及文件：`project.godot`、`README.md`、`scripts/main3d.gd`

---

## 2. 核心设计思路

**完全复用游戏场景的地块模型和渲染系统**，在开始界面铺满整个屏幕的地块，不新建任何UI绘制逻辑。

---

## 3. 地块世界

### 3.1 规格
- 网格：**20列 × 16行**（铺满整个屏幕）
- 地块类型：大部分为**山体**（约85%），少量**草地**（约15%）
- 使用游戏内 `_spawn_tile()` / `_force_tile()` 生成完整3D地块（底座+表面+边框+装饰）
- 地块间距：TILE_SPACING = 1.25（与游戏内一致）

### 3.2 水域拼字 "GGJ 2026"
- 使用水域地块拼出 "GGJ 2026" 字样
- 位于画面的**中左下角**（非正中，偏左偏下）
- 5×7像素字体模板，每个"像素"对应1个水域地块
- 文字大约占据 35×7 = 245个地块格子中的约50个水域

### 3.3 建筑点缀
- 在文字周围空位放置 3-5 个建筑地块
- 建筑使用 `_tile_pavilion_surface()` 渲染完整模型

### 3.4 网格布局示意（20×16）
```
山山山山山山山山山山山山山山山山山山山山
山山山山山山山山山山山山山山山山山山山山
山山山山山山山山山山山山山山山山山山山山
山山山山山山山山山山山山山山山山山山山山
山山山山山山山山山山山山山山山山山山山山
山山水水水山水山水水水山水山水水水山山山  ← GGJ 2026 水域文字
山山水山山山水山水山山水山水山山山山山山
山山水水水山水山水水水山水山水水山山山山
山山山山水山水山水山山山山山山山水山山山
山山水水水山水山水水水山水山水水水山山山
山山山山山山山山山山山山山山山山山山山山
山山山山山山山山山山山山山山山山山山山山
山山山山山山山山山山山山山山山山山山山山
山山山山山山山山山山山山山山山山山山山山
山山山山山山山山山山山山山山山山山山山山
山山山山山山山山山山山山山山山山山山山山
```

---

## 4. 相机设置

### 4.1 2.5D 等距视角（与游戏一致）
```gdscript
title_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
title_camera.size = 22.0  # 更大的size = 更远的视角，铺满屏幕
title_camera.position = Vector3(12.5, 20, 10)  # 棋盘中心偏上
title_camera.rotation_degrees = Vector3(-42, 42, 0)  # 标准等距视角
```

### 4.2 不可交互
- 禁用缩放、平移
- 只响应玩家人数按钮点击

---

## 5. 标题文字

### 5.1 "花满洪山" — 平行于2.5D平面
- 使用 **Label3D** 渲染在3D场景中
- **躺在地块平面上**，沿着等距轴方向排列
- 旋转：`rotation_degrees = Vector3(-90, 0, -45)`（平躺在XZ平面，沿对角线方向）
- 位置：棋盘上方偏右，不遮挡水域文字
- 字体大小：大号（font_size = 80+）
- 颜色：金色渐变，深绿描边
- Billboard模式：**关闭**（固定在地面上，不随相机旋转）

```gdscript
var title_label = Label3D.new()
title_label.text = "花满洪山"
title_label.font_size = 84
title_label.modulate = Color("#fff8e8")
title_label.outline_size = 10
title_label.outline_modulate = Color("#254940")
title_label.position = Vector3(6, 0.3, 2)  # 在地块平面上方
title_label.rotation_degrees = Vector3(-90, 0, -45)  # 平躺，沿对角线
title_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
title_root.add_child(title_label)
```

### 5.2 副标题 "HONGSHAN IN BLOOM"
- 同样 Label3D，躺在主标题下方
- 字体更小（font_size = 32）
- 金色描边

### 5.3 底部信息（2D UI叠加）
- "武汉洪山区主题 · GGJ 2026 · GROW Theme"
- 2D UI绘制在屏幕底部居中

---

## 6. 玩家选择按钮

### 6.1 布局
- 横排排列，居中偏下
- 每个按钮：宽 120px，高 60px
- 间距：18px
- 位于屏幕 y = 70% 处

### 6.2 样式
- 背景：深色半透明 `rgba(8, 18, 16, 0.88)`
- 边框：玩家颜色底部4px
- 文字："2人" / "3人" / "4人"
- Hover：上浮4px + 边框变亮

---

## 7. 技术实现

### 7.1 标题场景初始化
```gdscript
func _setup_title_world():
    _init_grid()
    var text_cells = _ggj2026_cells()
    var building_cells = _title_building_cells()
    # 遍历20×16网格生成地块
    for x in 20:
        for y in 16:
            var pos = Vector2i(x, y)
            if building_cells.has(pos):
                _force_tile(pos, T_BUILDING, false, 0)
            elif text_cells.has(pos):
                _force_tile(pos, T_WATER, false, 0)
            elif randf() < 0.15:
                _force_tile(pos, T_GRASS, false, 0)
            else:
                _force_tile(pos, T_MOUNTAIN, false, 0)
    # 建筑渲染
    for cell in building_cells:
        if _in_bounds(cell) and grid[cell.x][cell.y] == T_BUILDING:
            var root = tile_nodes[cell.x][cell.y]
            if root: _tile_pavilion_surface(root, 0)
    # Label3D 标题
    _create_title_labels()
    # 相机设置
    camera.size = 22.0
    camera.position = Vector3(12.5, 20, 10)
    camera.rotation_degrees = Vector3(-42, 42, 0)
```

### 7.2 网格大小适配
- 标题场景使用独立的网格大小（20×16）
- 游戏开始时重新初始化为标准 GRID_SIZE（8×8）
- `_init_grid()` 接受尺寸参数或使用全局常量

### 7.3 GGJ2026 文字坐标
- 文字起始位置：ox=3, oy=5（中左下区域）
- 使用5×7像素字体模板
- 每个像素 = 1个水域地块

### 7.4 状态过渡
```gdscript
# 选择玩家数后
func _start_game_from_title(count: int):
    player_count = count
    # 清除标题场景
    _clear_title_world()
    # 初始化游戏
    _start_game()
```

---

## 8. 视觉效果

- 山体地块有随机小山峰和色差
- 水域地块有涟漪动画（游戏内已有）
- 建筑有完整3D模型（黄鹤楼等）
- Label3D标题平躺在地面上，沿等距轴排列
- 2D UI只负责玩家按钮和底部说明文字
