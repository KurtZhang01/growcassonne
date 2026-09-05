# Scripts 拆分方案

## 现状

- 单文件 `main3d.gd`：3171行，193个函数
- 所有状态变量、逻辑、渲染、UI混在一起
- 修改任何功能都容易引入意外副作用

---

## 拆分架构

```
scripts/
├── main3d.gd          # 主控制器（~400行）：状态变量、_ready、_process、_input、节点引用
├── grid_manager.gd    # 棋盘管理（~350行）：网格初始化、扩展、地块类型操作、地形生成
├── tile_meshes.gd     # 地块渲染（~900行）：所有地形3D模型、装饰物、边框
├── card_system.gd     # 卡牌系统（~400行）：卡牌生成、手牌管理、出牌逻辑、卡牌验证
├── settlement.gd      # 结算引擎（~350行）：天气结算、地形变化、花朵增值/扩散、计分
├── weather_fx.gd      # 天气动效（~150行）：天气视觉效果（雨/沙/彩虹等）
├── road_system.gd     # 道路系统（~200行）：道路连接、桥接、闭合检测、道路奖励
├── ui_renderer.gd     # UI渲染（~500行）：所有_draw_ui相关、卡牌绘制、面板绘制
└── camera_ctrl.gd     # 相机控制（~80行）：缩放、平移、视角重置
```

---

## 各文件详细说明

### 1. `main3d.gd` — 主控制器（~400行）

**职责**：游戏入口、状态管理、全局协调

**包含内容**：
- `extends Node3D`
- 所有 `const` 和 `var` 状态变量声明（约100行）
- `_ready()`：初始化场景、调用各子模块初始化
- `_process(delta)`：主循环，调用动画更新、UI刷新
- `_input(event)`：输入分发，调用各子模块的输入处理
- 节点引用：camera、grid_root、plant_root、decor_root、ui_ctrl 等
- 枚举 `S { TITLE, DRAW_CARDS, PLACE_TILE, PLACE_SEED, PLAY_CARDS, GAME_OVER }`

**依赖**：所有其他模块（作为子模块调用）

---

### 2. `grid_manager.gd` — 棋盘管理（~350行）

**职责**：网格数据结构、扩展、地块类型查询

**包含内容**：
- `_init_grid()`：初始化网格数组
- `_world(pos)` / `_logical_cell(pos)`：坐标转换
- `_grid_width()` / `_grid_height()`：网格尺寸
- `_new_column()` / `_new_int_column()` / `_new_flower_column()` / `_new_node_column()`：数组工厂
- `_expand_board_ring()`：棋盘扩展（外围山体）
- `_ensure_growth_margin()`：确保开发后有增长空间
- `_non_developable_cells()`：查询可开发地块
- `_rebuild_mountain_envelope()`：重建山体外围
- `_draw_terrain()`：随机地形类型
- `_generate_piece()`：生成地块拼图
- `_rotate_cell()` / `_rotate_road_mask()` / `_piece_cells()`：旋转逻辑
- `_force_tile()` / `_set_tile_type()` / `_redraw_tile()`：地块数据修改
- `_is_plant_terrain()` / `_is_bonus_terrain()` / `_is_developable()`：地形查询
- `_tile_capacity()` / `_has_neighbor_bonus()`：容量查询
- `_trim_flowers_to_capacity()` / `_flower_total()`：花朵数据操作
- `_in_bounds()`：边界检查
- `_update_gaps()`：缺口生成检测
- `_refill_mountain_border()`：外围山体补充

**依赖**：无（纯数据操作，通过参数接收 grid/roads/flowers 引用）

---

### 3. `tile_meshes.gd` — 地块渲染（~900行）

**职责**：所有3D地块模型、装饰物、边框生成

**包含内容**：
- `_spawn_tile()`：地块渲染入口
- `_spawn_island_base()`：底座分层模型
- `_spawn_edge_trim()` / `_refresh_neighbor_trims()` / `_rebuild_edge_trim()`：边框
- `_update_edge_bridges()` / `_rebuild_bridges_for()` / `_spawn_bridge()`：地形桥接
- `_feature_position()` / `_position_clear_of_road()`：装饰物定位
- 5种地形表面函数：
  - `_tile_grass_surface()`：草地（丘陵+三叶草）
  - `_tile_water_surface()`：水域（涟漪+荷叶+芦苇）
  - `_tile_forest_surface()`：森林（树冠+苔藓+树桩）
  - `_tile_desert_surface()`：荒漠（沙丘+岩石+仙人掌）
  - `_tile_pavilion_surface()`：黄鹤楼建筑
  - `_tile_mountain_surface()`：山体
  - `_tile_gap_surface()`：缺口
- 装饰物函数：
  - `_decor_grass()` / `_decor_water()` / `_decor_forest()` / `_decor_desert()`
- 花朵模型函数：
  - `_spawn_plant()` / `_plant_mushroom()` / `_plant_flower()` / `_plant_crystal()` / `_plant_star()`
  - `_plant_mature_scale()` / `_animate_plant_growth()` / `_spawn_growth_burst()`
  - `_refresh_plant_visual()` / `_refresh_all_plants()`
- 材质辅助函数：
  - `_soft_material()` / `_sky_prop_material()` / `_road_material()`
  - `_building_box()`

**依赖**：grid_manager（查询地块数据）

---

### 4. `card_system.gd` — 卡牌系统（~400行）

**职责**：卡牌生成、手牌管理、出牌逻辑、卡牌验证

**包含内容**：
- `_make_seed_card()`：生成播种卡
- `_draw_public_card()` / `_draw_card_from_deck()`：从卡堆抽牌
- `_card_sort_value()` / `_card_sort_less()` / `_sort_current_hand()`：手牌排序
- `_take_card_from_deck()`：抽取逻辑
- `_start_player_turn()` / `_start_game()` / `_end_turn()`：回合流程
- `_selected_card()`：获取当前选中卡
- `_card_description()` / `_card_accent()` / `_card_base_color()`：卡牌属性
- `_begin_card_drag()` / `_release_hand_drag()` / `_cancel_armed_card()`：拖拽逻辑
- `_card_has_valid_target()`：卡牌可用性检查
- `_extend_road_drag()`：道路拖拽路径
- `_apply_road_path()`：应用道路路径
- `_consume_dragged_card()` / `_finish_card_drag()`：出牌完成
- `_apply_pending_develop()`：开发卡放置
- `_generate_development_roads()`：开发后自动生成道路
- `_can_play_selected_card()` / `_play_selected_card()`：出牌逻辑
- `_apply_develop_card()` / `_can_develop_cells()`：开发卡
- `_apply_building_develop_card()`：建筑开发卡
- `_develop_card_cells()` / `_development_shape_offsets()`：开发形状计算
- `_apply_road_card()` / `_connect_road()`：道路卡
- `_apply_weather_card()`：天气卡
- `_record_action()`：操作记录

**依赖**：grid_manager、settlement、road_system

---

### 5. `settlement.gd` — 结算引擎（~350行）

**职责**：回合结算、地形变化、花朵增值/扩散、计分

**包含内容**：
- `_settle_turn()`：结算入口
- `_emit_settlement_labels()` / `_float_settlement_label()`：结算动效
- `_tick_weather()`：天气计时
- `_apply_weather_tile_changes()` / `_weather_convert_neighbor()`：天气地形变化
- `_apply_neighbor_terrain_changes()`：邻居地形影响
- `_grow_flowers()`：花朵增值
- `_spread_flowers()`：花朵扩散
- `_has_extreme_weather()`：天气状态查询
- `_calc_all_scores()`：计分
- `_roads_connect()` / `_player_road_score()` / `_flood_p()`：得分计算辅助
- `_do_grow()`：旧版生长逻辑（如已废弃可移除）

**依赖**：grid_manager（读写 grid/flowers 数据）

---

### 6. `weather_fx.gd` — 天气动效（~150行）

**职责**：天气视觉效果

**包含内容**：
- `_apply_weather_visual()`：天气效果入口
- `_spawn_weather_rain()`：雨滴/台风乌云
- `_spawn_weather_drift()`：沙尘暴粒子
- `_spawn_weather_bands()`：彩虹/旱季光晕
- 天气动效清理逻辑

**依赖**：无（独立的3D节点生成）

---

### 7. `road_system.gd` — 道路系统（~200行）

**职责**：道路连接、桥接、闭合检测、奖励

**包含内容**：
- `_update_road_bridges()` / `_rebuild_road_bridges_for()` / `_spawn_road_bridge_pair()`：道路桥接
- `_refresh_road_effects()`：道路效果刷新
- `_road_component()` / `_road_component_is_closed()` / `_road_component_key()`：闭合检测
- `_road_pair_key()`：道路标识
- `_set_road_visual()` / `_spawn_closed_road_fx()` / `_spawn_road_fx()`：道路视觉
- `_refresh_building_auras()` / `_spawn_aura_particles()`：建筑光幕

**依赖**：grid_manager

---

### 8. `ui_renderer.gd` — UI渲染（~500行）

**职责**：所有2D UI绘制

**包含内容**：
- `_draw_ui()`：UI主入口
- `_draw_public_decks()`：公共卡堆面板
- `_draw_bottom_hand()`：手牌区
- `_draw_fitted_text()` / `_player_text_color()`：文字辅助
- `_draw_card_symbol()` / `_draw_repeating_card_pattern()`：卡牌图案
- `_draw_glass_card()`：面板绘制
- `_draw_title()`：标题画面
- `_draw_gameover()`：游戏结束画面
- `_hand_card_rect()` / `_bottom_card_rect()` / `_deck_rect()`：布局计算
- `_card_at_pointer()`：点击检测
- `_update_piece_preview()` / `_rotate_selected_piece()`：地块预览
- `_update_card_drag_preview()` / `_spawn_preview_tile_model()` / `_make_preview_translucent()`：卡牌预览

**依赖**：card_system（获取手牌数据）、grid_manager（获取地块数据）

---

### 9. `camera_ctrl.gd` — 相机控制（~80行）

**职责**：相机缩放、平移、视角重置

**包含内容**：
- 缩放处理（滚轮/双指捏合）
- 平移处理（中键拖拽/双指滑动）
- 视角重置（C键）
- `_ui_scale()` / `_ui_point()`：UI坐标转换
- `_mouse_to_grid()`：鼠标→网格坐标
- `_cover_source_rect()`：纹理裁剪

**依赖**：无（独立的相机操作）

---

## 拆分策略

### 方案A：静态类（推荐）

每个模块作为 `class_name` 静态类，主脚本实例化并调用：

```gdscript
# grid_manager.gd
class_name GridManager

var grid: Array
var roads: Array
# ...

func init_grid(): ...
func world(pos: Vector2i) -> Vector3: ...
```

```gdscript
# main3d.gd
var grid_mgr: GridManager
var tile_mesh: TileMeshBuilder
var card_sys: CardSystem
# ...

func _ready():
    grid_mgr = GridManager.new()
    tile_mesh = TileMeshBuilder.new()
    # ...
```

**优点**：每个模块独立、可测试、职责清晰
**缺点**：需要传递状态引用，初始重构工作量大

### 方案B：Autoload 单例

将各模块注册为 Autoload，全局访问：

```gdscript
# Project Settings > Autoload
GridManager → grid_manager.gd
TileMeshBuilder → tile_meshes.gd
```

**优点**：全局访问简单
**缺点**：增加全局状态，不利于测试

### 方案C：Node 组合（最保守）

各模块作为子节点脚本挂载在场景树上：

```gdscript
# main3d.gd
onready var grid_mgr = $GridManager
onready var tile_mesh = $TileMeshBuilder
```

**优点**：不需要 class_name，最接近当前结构
**缺点**：依赖场景树结构

---

## 实施步骤

1. **第一步**：提取 `tile_meshes.gd`（最大、最独立、纯视觉）
2. **第二步**：提取 `ui_renderer.gd`（第二大、相对独立）
3. **第三步**：提取 `camera_ctrl.gd`（最小、最独立）
4. **第四步**：提取 `grid_manager.gd`（核心数据层）
5. **第五步**：提取 `settlement.gd`（依赖 grid_manager）
6. **第六步**：提取 `road_system.gd`
7. **第七步**：提取 `weather_fx.gd`
8. **第八步**：提取 `card_system.gd`（最复杂，最后处理）

---

## 依赖关系图

```
main3d.gd（主控制器）
├── camera_ctrl.gd（无依赖）
├── grid_manager.gd（无依赖，核心数据层）
│   ├── tile_meshes.gd（依赖 grid_manager）
│   ├── road_system.gd（依赖 grid_manager）
│   ├── settlement.gd（依赖 grid_manager）
│   └── card_system.gd（依赖 grid_manager + settlement + road_system）
├── weather_fx.gd（无依赖）
└── ui_renderer.gd（依赖 card_system + grid_manager）
```

---

## 注意事项

- 所有模块需要能访问 `grid`、`roads`、`flowers`、`tile_nodes` 等共享数据
- 建议通过构造函数注入或 setter 注入共享引用
- `_process` 和 `_input` 保留在 main3d.gd，分发给各子模块
- 渐进式拆分：每次拆一个模块，测试通过后再拆下一个
