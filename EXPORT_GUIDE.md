# 花满洪山 — 多平台导出指南

## 前提条件

- Godot 4.7.2（你已在用的版本）
- 项目路径：`/Users/zhangborui/project/growcassonne/`

---

## 1. macOS 导出

### 前置准备
macOS 无需额外模板，Godot 自带 macOS 导出支持。

### 操作步骤
1. 打开 Godot 编辑器
2. 菜单 → **项目(Project)** → **导出(Export)**
3. 点击 **添加(Add)** → 选择 **macOS**
4. 配置：
   - **导出路径**：`build/mac/花满洪山.app`
   - **应用名称**：`花满洪山`
   - **图标**：需要 512×512 的 `.icns` 文件（可从 PNG 生成）
   - **代码签名**：如果只是本地测试，不填也行
5. 点击 **导出项目(Export Project)**

### 命令行导出
```bash
cd /Users/zhangborui/project/growcassonne
godot --headless --export-release "macOS" build/mac/花满洪山.app
```

---

## 2. Windows 导出

### 前置准备
1. 下载 Windows 导出模板：
   - 菜单 → **编辑(Editor)** → **管理导出模板(Manage Export Templates)**
   - 下载 Windows 模板（约 600MB）
2. 或者命令行：
   ```bash
   godot --headless --download-windows-templates
   ```

### 操作步骤
1. 添加 **Windows Desktop** 导出配置
2. 配置：
   - **导出路径**：`build/win/花满洪山.exe`
   - **图标**：需要 `.ico` 文件（从 PNG 生成）
   - **架构**：x86_64（默认）
3. 导出

### 命令行导出
```bash
godot --headless --export-release "Windows" build/win/花满洪山.exe
```

---

## 3. iOS 导出

### 前置准备
1. **Xcode**：需要安装（App Store 免费）
2. **Apple Developer 账号**：免费账号可真机调试，上架需付费（$99/年）
3. 下载 iOS 导出模板：
   ```bash
   godot --headless --download-ios-templates
   ```
4. 在 Godot 中配置 iOS 签名：
   - 菜单 → **编辑(Editor)** → **编辑器设置(Editor Settings)**
   - 找到 **导出 → iOS**
   - 设置 **Apple Team ID**（在 Apple Developer 后台获取）

### 操作步骤
1. 添加 **iOS** 导出配置
2. 配置：
   - **导出路径**：`build/ios/花满洪山.xcodeproj`
   - **Bundle Identifier**：`com.yourname.hongshan`
   - **App 名称**：`花满洪山`
   - **图标**：需要多种尺寸的 PNG（从1024×1024自动生成）
3. 导出 → 生成 Xcode 项目
4. 用 Xcode 打开 `.xcodeproj`
5. 连接 iPhone/iPad → 在 Xcode 中运行

### 命令行导出
```bash
godot --headless --export-release "iOS" build/ios/花满洪山.xcodeproj
```

---

## 4. Android 导出

### 前置准备
1. **Android Studio**：下载安装（developer.android.com）
2. **JDK 17**：Android Studio 自带，或单独安装
3. **Android SDK**：在 Android Studio 中安装 SDK 34+
4. 在 Godot 中配置 Android 路径：
   - 菜单 → **编辑(Editor)** → **编辑器设置(Editor Settings)**
   - 找到 **导出 → Android**
   - 设置 **Android SDK 路径**（通常 `~/Android/Sdk`）
   - 设置 **JDK 路径**
5. 下载 Android 导出模板：
   ```bash
   godot --headless --download-android-templates
   ```

### 操作步骤
1. 添加 **Android** 导出配置
2. 配置：
   - **导出路径**：`build/android/花满洪山.apk`
   - **包名**：`com.yourname.hongshan`
   - **版本号**：`1.0.0`
   - **最小 SDK**：21（Android 5.0）
   - **目标 SDK**：34
   - **图标**：需要多种尺寸的 PNG
3. 导出为 APK（调试用）或 AAB（上架用）

### 命令行导出
```bash
# APK（调试）
godot --headless --export-debug "Android" build/android/花满洪山.apk

# AAB（上架）
godot --headless --export-release "Android" build/android/花满洪山.aab
```

---

## 5. 图标生成

所有平台都需要图标，从一张 1024×1024 的 PNG 开始：

```bash
# 如果你有 ImageMagick
convert icon_1024.png -resize 512x512 icon_512.png
convert icon_1024.png -resize 256x256 icon_256.png
convert icon_1024.png -resize 128x128 icon_128.png
convert icon_1024.png -resize 64x64 icon_64.png
# .icns (macOS) 和 .ico (Windows) 可用在线工具生成
```

---

## 6. 快速检查清单

- [ ] macOS：直接导出，无需额外模板
- [ ] Windows：需下载 Windows 导出模板
- [ ] iOS：需 Xcode + Apple Developer 账号
- [ ] Android：需 Android Studio + JDK + SDK
- [ ] 图标：准备 1024×1024 PNG，各平台自动缩放
- [ ] 测试：每个平台导出后先在模拟器/真机测试
