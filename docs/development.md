# 开发环境与日常命令

## 分层约定

- `melos`：仅用于 workspace bootstrap
- `just`：本地开发者入口，定位接近 `npm run`
- `tool/*.dart`：真实脚本实现，也是 CI / IDE / 自动化调用入口

## 快速开始

1. 初始化 workspace：

   ```bash
   melos bootstrap
   ```

   如果没有全局 `melos`，可改用：

   ```bash
   dart run melos bootstrap
   ```

2. 安装 `just`：

   - Windows：`winget install --id Casey.Just --exact`
   - Windows：`scoop install just`
   - Windows：`choco install just`
   - 通用：`cargo install just`

3. 显式同步项目状态：

   ```bash
   just sync
   ```

4. 运行应用：

   ```bash
   just run -- -d windows
   just run -- -d macos
   just run -- --dart-define=cronetHttpNoPlay=true
   ```

如果你不想安装 `just`，可以直接调用 Dart 入口：

```bash
dart run tool/project_prep.dart app
dart run tool/flutterw.dart run -d windows
```

## 常用命令

- `just sync`：显式同步依赖、l10n 生成物和代理证书资源；适合首次拉代码、切分支、修改 ARB 后或 IDE 调试前预热
- `just l10n`：单独生成国际化代码
- `just l10n-check`：检查国际化生成物是否最新
- `just clean`：执行 `flutter clean` 并重置依赖指纹
- `just rebuild -- <flutter build args...>`：先清理，再执行 `flutter build`
- `just run -- <flutter run args...>`：执行 `flutter run`
- `just build -- <flutter build args...>`：执行 `flutter build`
- `just test -- <flutter test args...>`：执行 `flutter test`
- `just drive -- <flutter drive args...>`：执行 `flutter drive`
- `just native -- <args...>`：显式准备原生产物
- `just doctor`：检查 Flutter / Dart / Cargo、l10n 状态、证书状态和 Android 本地签名状态
- `just analyze -- <args...>`：执行 `flutter analyze`
- `just release-check`：执行发版前检查
- `just release`：稳定版发版入口
- `just prerelease`：预发布发版入口
- `just ipa`：构建无签名 iOS IPA

当透传参数以 `-` 开头时，记得用 `--` 分隔，例如：

```bash
just run -- -d windows
just release -- patch --dry-run
```

## 自动行为

- `just run` / `just build` / `just drive` 会自动执行项目预处理，并在能识别目标平台时自动执行对应的 `native:prepare`
- `just test` 会自动执行测试所需的 `pub get + l10n`
- `just release` / `just prerelease` 会在真正写入版本号和打 tag 前自动执行发版前检查
- `just sync` 不是 hook，而是手动的显式预热命令；日常直接 `just run` / `just build` 即可

## 国际化工作流

- 协作源文件只保留 `lib/l10n/modules/**` 下的模块化 ARB
- `lib/l10n/slang/` 和 `lib/l10n/generated/app_localizations_compat.g.dart` 不提交 Git
- 修改 ARB 后，执行 `just sync` 或 `just l10n`
- 日常运行/构建入口会自动处理 l10n，不需要额外手写 pre-run hook

## IDE 集成

- Android Studio / IntelliJ 的共享运行配置提交在 [`.run/`](</D:/teng/Documents/i/ldx/.run/>)，不放进被忽略的 `.idea/`
- `FluxDO` 运行配置的 before-launch 只保留一个 `Run Prepare`
- 这个 before-launch 会串行执行 `app:prepare` 和 `native:prepare auto`，避免 IDE 按多个步骤反复弹终端
- VS Code 的 [launch.json](/D:/teng/Documents/i/ldx/.vscode/launch.json:1) 和 [tasks.json](/D:/teng/Documents/i/ldx/.vscode/tasks.json:1) 也已切到同一套预处理链路

## 平台约定

- Android 只有在 `android/key.properties` 和 keystore 都完整可用时才使用本地签名
- 当本地签名材料完整时，`debug/profile/release` 都会使用本地签名
- 当本地签名材料缺失时，`debug` 使用默认 debug signing，`profile/release` 自动回退到 debug signing
- Android 构建会优先使用 Android Studio 自带 JBR；如需手动指定，可设置 `FLUXDO_ANDROID_JAVA_HOME`
- Apple 平台不再把 `DEVELOPMENT_TEAM` 写死在共享 `pbxproj`
- 如需 Xcode 真机签名或本地签名构建，复制 [apple/Local.xcconfig.example](/D:/teng/Documents/i/ldx/apple/Local.xcconfig.example:1) 为 `apple/Local.xcconfig` 并填入自己的 `FLUXDO_APPLE_DEVELOPMENT_TEAM`
- 原生产物准备统一走 `just native -- ...` 或 `dart run tool/project_tasks.dart native:prepare ...`
- Windows / iOS 平台工程已移除内置 cargo / shell build hook，只消费仓库脚本预先落盘的 native 产物
- macOS 保留一个轻量级 bundle copy/sign 阶段，只负责拷贝和签名已准备好的 native 产物
