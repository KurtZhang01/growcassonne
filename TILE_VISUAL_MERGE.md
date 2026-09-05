# 同类地块视觉合并方案

---

## 一、核心思路

对于每个地块，检查上下左右四个方向：
- 如果相邻地块是**同类** → 删除该方向的边框 + 将该方向的所有视觉层（除装饰物外）延伸到地块边缘
- 如果相邻地块是**不同类** → 保留边框，视觉层不延伸

---

## 二、需要处理的视觉层

### 从内到外的层次关系

```
地块中心
├── Core（六棱锥）—— 不动，太深不需要延伸
├── Bot层（0.56宽）—— 不动，太窄看不到缝隙
├── Mid层（0.88宽）—— 可选延伸
├── Top层（1.06宽）—— 必须延伸（缝隙0.19）
├── Cap（1.03宽）—— 必须延伸（缝隙0.22）
├── 地形表面（0.95宽）—— 必须延伸（缝隙0.30，最明显）
├── 边框 —— 同类方向删除
└── 装饰物 —— 不动
```

### 各层需要延伸的量

以左方向为例（地块A的左边有同类地块B）：

| 层 | 当前边缘 | 目标边缘 | 需延伸量 |
|----|----------|----------|----------|
| Top层 | ±0.53 | ±0.625（缝隙中点） | +0.095 |
| Cap | ±0.515 | ±0.625 | +0.11 |
| 地形表面 | ±0.475 | ±0.625 | +0.15 |
| Mid层 | ±0.44 | 可选延伸 | +0.185 |

**关键**：每层延伸到缝隙中点（±0.625），这样两个同类地块的同层在缝隙中点处刚好对接。

---

## 三、实现方案

### 方案A：动态BoxMesh尺寸（推荐）

在生成地块时，根据合并方向调整各层BoxMesh的宽度：

```gdscript
func _spawn_island_base_merged(root: Node3D, terr: int, pos: Vector2i):
    var merge_dirs := _get_merge_directions(pos, terr)
    
    # Cap
    if terr != T_WATER:
        var cap_size = Vector3(1.03, 0.06, 1.03)
        var cap_offset = Vector3.ZERO
        if merge_dirs.has(Vector2i.LEFT):
            cap_size.x += 0.11; cap_offset.x -= 0.055
        if merge_dirs.has(Vector2i.RIGHT):
            cap_size.x += 0.11; cap_offset.x += 0.055
        if merge_dirs.has(Vector2i.UP):
            cap_size.z += 0.11; cap_offset.z -= 0.055
        if merge_dirs.has(Vector2i.DOWN):
            cap_size.z += 0.11; cap_offset.z += 0.055
        _building_box(root, cap_size, Vector3(0, 0.12, 0) + cap_offset, edge_materials[terr])
    
    # Top层
    var top_size = Vector3(1.06, 0.13, 1.06)
    var top_offset = Vector3.ZERO
    if merge_dirs.has(Vector2i.LEFT):
        top_size.x += 0.19; top_offset.x -= 0.095
    if merge_dirs.has(Vector2i.RIGHT):
        top_size.x += 0.19; top_offset.x += 0.095
    if merge_dirs.has(Vector2i.UP):
        top_size.z += 0.19; top_offset.z -= 0.095
    if merge_dirs.has(Vector2i.DOWN):
        top_size.z += 0.19; top_offset.z += 0.095
    # ... 生成top层mesh

func _get_merge_directions(pos: Vector2i, terr: int) -> Array:
    var dirs := []
    for dir in DIRS:
        var n = pos + dir
        if _in_bounds(n) and grid[n.x][n.y] == terr:
            dirs.append(dir)
    return dirs
```

### 方案B：使用额外的"填充块"

不改变原始层的尺寸，而是在合并方向追加一个填充BoxMesh：

```gdscript
func _spawn_merge_fill(root: Node3D, terr: int, dir: Vector2i):
    """在合并方向追加填充块，覆盖缝隙"""
    var fill_material = StandardMaterial3D.new()
    fill_material.albedo_color = TERRAIN_TOP[terr]
    fill_material.roughness = 0.92
    
    # 地形表面填充（从表面边缘到缝隙中点）
    var surface_fill = MeshInstance3D.new()
    var sfm = BoxMesh.new()
    var is_horizontal = dir.x != 0
    sfm.size = Vector3(
        0.15 if is_horizontal else 0.95,  # 填充宽度
        0.06,  # 与草地表面同高
        0.15 if not is_horizontal else 0.95
    )
    surface_fill.mesh = sfm
    surface_fill.material_override = fill_material
    surface_fill.position = Vector3(dir.x * 0.53, 0.13, dir.y * 0.53)
    root.add_child(surface_fill)
    
    # Top层填充
    var top_fill = MeshInstance3D.new()
    var tfm = BoxMesh.new()
    tfm.size = Vector3(
        0.095 if is_horizontal else 1.06,
        0.13,
        0.095 if not is_horizontal else 1.06
    )
    top_fill.mesh = tfm
    var top_mat = StandardMaterial3D.new()
    top_mat.albedo_color = TERRAIN_MID[terr]
    top_mat.roughness = 0.94
    top_fill.material_override = top_mat
    top_fill.position = Vector3(dir.x * 0.58, 0.025, dir.y * 0.58)
    root.add_child(top_fill)
    
    # Cap填充（非水域）
    if terr != T_WATER:
        var cap_fill = MeshInstance3D.new()
        var cfm = BoxMesh.new()
        cfm.size = Vector3(
            0.11 if is_horizontal else 1.03,
            0.06,
            0.11 if not is_horizontal else 1.03
        )
        cap_fill.mesh = cfm
        cap_fill.material_override = edge_materials[terr]
        cap_fill.position = Vector3(dir.x * 0.57, 0.12, dir.y * 0.57)
        root.add_child(cap_fill)
```

---

## 四、边框处理

当前边框逻辑已经正确——同类地块不生成边框（`if grid[neighbor.x][neighbor.y] == terr: continue`）。

但合并后，需要确保**被合并方向的边框也被删除**。当前代码已经处理了这个逻辑，不需要修改。

---

## 五、地形表面合并细节

### 草地（0.95宽 → 延伸到1.25/2=0.625）

当前草地表面 BoxMesh(0.95, 0.06, 0.95)，位置 y=0.13。

合并左方向时：
- 宽度从0.95增加到0.95+0.15=1.10
- X位置从0偏移到-0.075
- 这样左边缘从-0.475延伸到-0.55（更接近缝隙中点-0.625）

**问题**：两个同类草地的延伸块在缝隙中点附近会有微小重叠或缝隙（取决于精确计算）。需要确保延伸量精确对齐。

**精确计算**：
```
缝隙中点 = TILE_SPACING / 2 = 0.625
草地表面左边缘 = -0.475
需要延伸到 = -0.625
延伸量 = 0.625 - 0.475 = 0.15
```

左方向延伸块：
- 宽度 = 0.15
- 中心X = -(0.475 + 0.15/2) = -0.55
- 位置 = Vector3(-0.55, 0.13, 0)

### Top层（1.06宽）

```
Top层左边缘 = -0.53
需要延伸到 = -0.625
延伸量 = 0.095
```

左方向延伸块：
- 宽度 = 0.095
- 中心X = -(0.53 + 0.095/2) = -0.5775
- 位置 = Vector3(-0.5775, 0.025, 0)

### Cap（1.03宽）

```
Cap左边缘 = -0.515
需要延伸到 = -0.625
延伸量 = 0.11
```

左方向延伸块：
- 宽度 = 0.11
- 中心X = -(0.515 + 0.11/2) = -0.57
- 位置 = Vector3(-0.57, 0.12, 0)

---

## 六、转角处理（L形合并）

当一个地块同时在左和上方向有同类邻居时：

```
┌─────────┬─────────┐
│  草地 A  │  草地 B  │
├─────────┤         │
│  草地 C  │         │
└─────────┴─────────┘
```

A在右方向合并B，A在下方向合并C。B在下方向合并C。

转角处（B的左下角，即A的右上角交汇点）：
- A向右延伸的填充块 和 A向下延伸的填充块 在角上相交
- 需要一个角部填充块来覆盖交汇处

**角部填充**：当两个合并方向都存在时，在角上追加一个小方块：

```gdscript
if merge_dirs.has(Vector2i.RIGHT) and merge_dirs.has(Vector2i.DOWN):
    var corner = MeshInstance3D.new()
    var cm = BoxMesh.new()
    cm.size = Vector3(0.15, 0.06, 0.15)  # 与延伸块同尺寸
    corner.mesh = cm; corner.material_override = fill_material
    corner.position = Vector3(0.55, 0.13, 0.55)
    root.add_child(corner)
```

---

## 七、水域合并特殊处理

水域没有Cap，所以只需要延伸：
1. 水面（0.92宽）→ 延伸到0.625
2. Top层（1.06宽）→ 延伸到0.625

```
水面左边缘 = -0.46
需要延伸到 = -0.625
延伸量 = 0.165
```

水面延伸块材质应使用与水面相同的ShaderMaterial（如果可行），否则使用同色半透明材质。

---

## 八、实施步骤

1. **修改 `_spawn_island_base`**：接受 `pos` 参数，调用 `_get_merge_directions`，动态调整各层尺寸
2. **修改地形表面函数**：接受 `pos` 参数，根据合并方向调整表面尺寸
3. **修改 `_spawn_edge_trim`**：当前逻辑已正确（同类跳过），无需修改
4. **处理转角**：在合并方向超过1个时，追加角部填充块
5. **刷新逻辑**：新地块放置后，刷新邻居的合并状态（类似 `_refresh_neighbor_trims`）

### 需要修改的函数

| 函数 | 修改内容 |
|------|----------|
| `_spawn_tile` | 传递 `pos` 给子函数 |
| `_spawn_island_base` | 接受 `pos`，动态调整尺寸 |
| `_tile_grass_surface` 等 | 接受 `pos`，动态调整表面尺寸 |
| `_refresh_neighbor_trims` | 同时刷新邻居的合并状态 |

### 不需要修改的部分

- `_spawn_edge_trim`：已有同类跳过逻辑
- 装饰物函数：保持原样
- 花朵模型：保持原样

---

## 九、预期效果

合并前：
```
┌──────┐  缝隙0.30  ┌──────┐
│草地A │  ▓▓▓▓▓▓▓  │草地B │
│      │  看到底座  │      │
└──────┘   侧面    └──────┘
```

合并后：
```
┌──────────────────────────────┐
│         草地 A+B             │
│   装饰物A   ···   装饰物B    │
└──────────────────────────────┘
```

- 两个草地的表面、底座、Cap在缝隙处完全连接
- 只保留各自内部的装饰物（花簇、丘陵等）
- 边框消失
- 视觉上成为一个大地块
