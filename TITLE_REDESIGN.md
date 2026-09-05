# 花满洪山 — 开始页面重设计

---

## 1. 命名变更

所有出现以下文字的地方统一修改：

| 原文 | 改为 |
|------|------|
| 花之江城 | 花满洪山 |
| Wuhan in Bloom | Hongshan in Bloom |
| 蔓延江城 | 蔓延洪山 |

涉及文件：
- `project.godot` (config/name)
- `README.md` (标题+概述)
- `scripts/main3d.gd` (`_draw_title` 函数、卡牌描述等)

---

## 2. 开始页面整体布局

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│     ┌─ 12×10 山体地块网格（覆盖全屏，平铺）──┐         │
│     │  每个地块有3D模型（底座+山体表面）     │         │
│     │  平行俯视（非等距），不可缩放          │         │
│     └────────────────────────────────────────┘         │
│                                                      │
│              花 满 洪 山                              │
│         HONGSHAN IN BLOOM                             │
│                                                      │
│     ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐              │
│     │ 2人 │  │ 3人 │  │ 4人 │  │ ... │              │
│     └─────┘  └─────┘  └─────┘  └─────┘              │
│                                                      │
│              武汉洪山区主题                            │
│              GGJ 2025 · GROW Theme                    │
└──────────────────────────────────────────────────────┘
```

---

## 3. 山体地块网格

### 3.1 规格
- 网格：**12列 × 10行**
- 视角：**平行俯视**（Orthographic，rotation = (-90, 0, 0)），无透视
- 不可缩放、不可平移
- 地块间距：TILE_SPACING = 1.25（与游戏内一致）

### 3.2 相机设置
```gdscript
title_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
title_camera.size = 16.0  # 覆盖整个网格
title_camera.position = Vector3(7.5, 20, 6.25)  # 网格中心上方
title_camera.rotation_degrees = Vector3(-90, 0, 0)  # 正俯视
```

### 3.3 地块生成
- 全部为山体地块（T_MOUNTAIN）
- 使用现有 `_tile_mountain_surface()` 建模
- 每个地块有随机微小色差（shading ±5%）
- 地块之间有边框连接（edge trim）

### 3.4 网格尺寸计算
```
网格宽度 = 12 × 1.25 = 15.0
网格高度 = 10 × 1.25 = 12.5
中心偏移 = (15.0/2, 0, 12.5/2) = (7.5, 0, 6.25)
```

---

## 4. 标题文字

### 4.1 主标题："花满洪山"
- 字体：系统默认（黑体）
- 大小：72px
- 颜色：渐变填充（从上到下：金色 #fff8e8 → 暖白 #f5e8d0）
- 描边：深绿色 #254940，宽度8px
- 居中显示在屏幕上半部（y = 屏幕高度 × 0.25）

### 4.2 副标题："HONGSHAN IN BLOOM"
- 大小：20px
- 颜色：金色 #f3cf8d
- 描边：深绿色 #254940，宽度4px
- 位于主标题下方 50px

### 4.3 底部说明
- "武汉洪山区主题" — 16px，白色半透明
- "GGJ 2025 · GROW Theme" — 14px，暗灰

---

## 5. 玩家选择按钮

### 5.1 布局
- 横排排列，居中
- 每个按钮：宽 120px，高 60px
- 间距：16px
- 位于屏幕 y = 55% 处

### 5.2 样式
- 背景：深色半透明 `rgba(8, 18, 16, 0.85)`
- 边框：玩家颜色（绿/蓝/橙/紫）底部3px
- 文字："2人" / "3人" / "4人"
- Hover：边框变亮，背景微亮

---

## 6. 技术实现要点

### 6.1 场景切换
```gdscript
# 在 _ready() 中创建标题场景
func _setup_title_scene():
    title_root = Node3D.new(); add_child(title_root)
    title_camera = Camera3D.new()
    title_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    title_camera.size = 16.0
    title_camera.position = Vector3(7.5, 20, 6.25)
    title_camera.rotation_degrees = Vector3(-90, 0, 0)
    title_root.add_child(title_camera)
    _generate_title_mountains()

func _generate_title_mountains():
    for x in 12:
        for y in 10:
            var pos = Vector2i(x, y)
            var root = Node3D.new()
            root.position = _world(pos)
            title_root.add_child(root)
            _spawn_island_base(root, T_MOUNTAIN)
            _tile_mountain_surface(root)
            _spawn_edge_trim(root, T_MOUNTAIN, pos)
```

### 6.2 禁用交互
```gdscript
# 标题状态下禁用缩放和平移
func _input(event):
    if state == S.TITLE:
        # 只处理玩家选择按钮点击
        return
    # ... 其他状态的输入处理
```

### 6.3 状态过渡
```gdscript
# 选择玩家数后
func _start_game_with_players(count: int):
    player_count = count
    # 隐藏标题场景
    title_root.visible = false
    # 初始化游戏
    _start_game()
```

---

## 7. 视觉参考

见同目录下 `title_mockup.html` — 静态HTML示意，展示布局和配色。
