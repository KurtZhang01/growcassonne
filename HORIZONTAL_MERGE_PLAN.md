# 水平方向缝隙修复方案

---

## 问题分析

### 关键尺寸
- `TILE_SPACING` = **1.25**（地块中心间距）
- 地块中心到边缘 = 1.25 / 2 = **0.625**

### 缝隙1：边框水平不连接

当前边框尺寸和位置：
```
边框宽度: 0.03
边框中心: ±0.53（从地块中心算）
边框内边: ±0.515
边框外边: ±0.545
```

两个相邻地块的边框之间的缝隙：
```
地块A右外边: +0.545
地块B左外边: (1.25 - 0.545) = +0.705
缝隙 = 0.705 - 0.545 = 0.16 ← 这就是水平方向的缝
```

### 缝隙2：水面水平不连接

当前水面尺寸：
```
水面宽度: 0.92（±0.46）
```

两个相邻水面之间的缝隙：
```
缝隙 = 1.25 - 0.46 - 0.46 = 0.33 ← 水面之间有大缝
```

有cap时（1.03宽，±0.515），cap覆盖了大部分缝隙（缝隙=1.25-1.03=0.22，两个cap之间仅0.22缝）。但水域跳过了cap，所以水面之间裸露0.33缝隙。

---

## 修复方案

### 一、边框水平延伸

**原理**：让边框足够宽，使得相邻地块的边框在地块间隙中**重叠**，形成连续边框。

**关键计算**：
```
地块间隙中点 = 0.625（即 TILE_SPACING / 2）
边框中心改为 ±0.625（对准间隙中点）
边框宽度改为 0.72（向两侧各延伸 0.36）
```

**重叠验证**：
```
地块A右边框: 中心 0.625, 范围 [0.265, 0.985]
地块B左边框: 中心 0.625(=1.25-0.625), 范围 [0.265+1.25, 0.985+1.25] → 等效 [0.265, 0.985] 相对B

在全局坐标中:
A右边框右边缘 = A中心 + 0.985
B左边框左边缘 = B中心 - 0.985 = (A中心 + 1.25) - 0.985 = A中心 + 0.265

A右边框右边缘(A+0.985) > B左边框左边缘(A+0.265)
重叠 = 0.985 - 0.265 = 0.72
```

边框在间隙中完全重叠，视觉上无缝连接。

**修改代码**：
```gdscript
func _spawn_edge_trim(root: Node3D, terr: int, pos: Vector2i):
    var trim_material = StandardMaterial3D.new()
    trim_material.albedo_color = TERRAIN_TOP[terr].lightened(0.08)
    trim_material.roughness = 0.76
    for side in 4:
        var neighbor = pos + DIRS[side]
        if _in_bounds(neighbor) and grid[neighbor.x][neighbor.y] == terr: continue
        var trim = MeshInstance3D.new(); var mesh = BoxMesh.new()
        var horizontal = side == 0 or side == 2
        # 宽度 0.72，中心在间隙中点(±0.625)
        mesh.size = Vector3(0.72 if horizontal else 0.03, 0.14, 0.03 if horizontal else 0.72)
        trim.mesh = mesh; trim.material_override = trim_material
        trim.position = Vector3(
            DIRS[side].x * (TILE_SPACING * 0.5),
            0.10,
            DIRS[side].y * (TILE_SPACING * 0.5)
        )
        trim.set_meta("edge_trim", true)
        root.add_child(trim)
```

**注意**：当相邻是同类地块时，边框不生成（原有逻辑 `if grid[neighbor.x][neighbor.y] == terr: continue`），所以同类地块之间依然没有边框，表面靠地形面延伸覆盖。

---

### 二、水面水平延伸（无cap渐变连接）

**目标**：水域之间不加cap，水面直接延伸到地块边缘，并在相邻水域的间隙处用**连接条**过渡。

**方案**：在 `_tile_water_surface` 中，为水面增加4条边缘连接条，延伸到地块边缘：

```gdscript
func _tile_water_surface(root: Node3D, road_mask: int):
    # 主水面（保持不变）
    var top = MeshInstance3D.new()
    var tm = BoxMesh.new(); tm.size = Vector3(0.92, 0.04, 0.92)
    top.mesh = tm
    var mat = ShaderMaterial.new(); mat.shader = WATER_TILE_SHADER
    top.material_override = mat; top.position.y = 0.10
    root.add_child(top)

    # 深度底层（保持不变）
    var depth = MeshInstance3D.new()
    var dm = CylinderMesh.new(); dm.top_radius = 0.30; dm.bottom_radius = 0.30; dm.height = 0.02
    depth.mesh = dm
    var dmat = StandardMaterial3D.new()
    dmat.albedo_color = TERRAIN_BOT[1].lerp(TERRAIN_MID[1], 0.5)
    depth.material_override = dmat; depth.position.y = 0.09
    root.add_child(depth)

    # ---- 新增：4条边缘连接条 ----
    # 每条连接条从水面边缘延伸到地块边缘(±0.53)
    # 宽度 = (0.53 - 0.46) * 2 = 0.14（每侧0.07）
    # 但为了与邻居重叠，每条宽 0.20，中心在 ±0.48
    var connector_mat = StandardMaterial3D.new()
    connector_mat.albedo_color = TERRAIN_TOP[1]  # 水面蓝色
    connector_mat.albedo_color.a = 0.6
    connector_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    connector_mat.emission_enabled = true
    connector_mat.emission = Color(0.2, 0.5, 0.8)
    connector_mat.emission_energy_multiplier = 0.15

    for side in 4:
        var horizontal = side == 0 or side == 2
        var connector = MeshInstance3D.new(); var cm = BoxMesh.new()
        # 沿地块边方向拉长(1.06覆盖整个边)，垂直方向窄(0.20)
        cm.size = Vector3(1.06 if horizontal else 0.20, 0.03, 0.20 if horizontal else 1.06)
        connector.mesh = cm; connector.material_override = connector_mat
        connector.position = Vector3(
            DIRS[side].x * 0.48,  # 从水面边缘向外延伸
            0.10,
            DIRS[side].y * 0.48
        )
        root.add_child(connector)

    # 涟漪、反射等装饰（保持不变）
```

**重叠验证**：
```
水面连接条外边: ±0.48 + 0.10 = ±0.58
邻居水面连接条外边: 1.25 - 0.58 = 0.67 → 邻居的 +0.58 相对A = 1.25 - 0.58 = 0.67
缝隙中重叠: 0.67 - (0.48 - 0.10) = 0.67 - 0.38 = 0.29... 

实际：A连接条外边 = A中心 + 0.58
B连接条外边 = B中心 - 0.58 = A中心 + 1.25 - 0.58 = A中心 + 0.67
缝隙 = 0.67 - 0.58 = 0.09 ← 仍有小缝

修正：连接条中心改为 ±0.53（地块边缘），宽度 0.28
外边 = 0.53 + 0.14 = 0.67
邻居外边 = 1.25 - 0.67 = 0.58
重叠 = 0.67 - 0.58 = 0.09（重叠）
```

**最终方案**：
```gdscript
# 连接条：宽0.28，中心在±0.53（地块边缘），与邻居重叠0.09
cm.size = Vector3(1.06 if horizontal else 0.28, 0.03, 0.28 if horizontal else 1.06)
connector.position = Vector3(DIRS[side].x * 0.53, 0.10, DIRS[side].y * 0.53)
```

---

### 三、非水域地块的cap处理

当前cap（1.03宽）在非水域地块上仍然保留，用于覆盖接缝。对于非水域地块，cap已经覆盖了大部分间隙（1.25 - 1.03 = 0.22缝隙，两个cap之间仅0.22）。配合加宽后的边框（0.72），视觉上无缝。

---

## 修改总结

| 修改项 | 当前值 | 修改后 | 原因 |
|--------|--------|--------|------|
| 边框宽度 | 0.03 | **0.72** | 覆盖地块间隙 |
| 边框中心 | ±0.53 | **±0.625** | 对准间隙中点 |
| 边框高度 | 0.14 | 0.14（不变） | 不改高度 |
| 水面主面 | 0.92 | 0.92（不变） | 不改高度 |
| 水面连接条 | 无 | **0.28宽, ±0.53** | 填充水面间隙 |

**不修改**：所有y坐标（高度）不变。
