# EqunDO

> [中国分布式计算论坛](https://equn.com/forum/)（Equn）第三方客户端

EqunDO 是一个基于 Flutter 的 Equn 论坛客户端，面向 Android、iOS、Windows、macOS、Linux 等平台。项目在 [FluxDO](https://github.com/Lingyan000/fluxdo) 的基础上适配 Discuz / Equn 论坛。

本项目是非官方客户端，与 Equn 官方无直接关联。

## 下载

正式包以 GitHub Releases 为准：

[![GitHub Releases](https://img.shields.io/github/v/release/kamisangk/equndo?style=for-the-badge&logo=github&label=GitHub%20Releases)](https://github.com/kamisangk/equndo/releases)

## 快速开始

### 环境要求

- Flutter / Dart，项目当前 SDK 约束为 `^3.10.4`
- Android Studio 或对应平台 SDK
- Rust / Cargo，部分 native 依赖需要编译
- `just` 可选，用于简化常用命令

### 克隆与初始化

```bash
git clone https://github.com/kamisangk/equndo.git
cd equndo
dart run melos bootstrap
dart run tool/project_prep.dart app
```

如果安装了 `just`，可以使用：

```bash
just bootstrap
just sync
```

### 运行

```bash
dart run tool/flutterw.dart run -d android
dart run tool/flutterw.dart run -d windows
dart run tool/flutterw.dart run -d macos
```

使用 `just`：

```bash
just run -- -d android
```

## 常用开发命令

```bash
dart run tool/gen_l10n.dart
dart run tool/flutterw.dart test
dart run tool/flutterw.dart analyze
dart run tool/project_tasks.dart app:clean
```

使用 `just`：

```bash
just l10n
just test
just analyze
just clean
```

## 项目结构

```text
equndo/
├── android/                 # Android 工程
├── ios/                     # iOS 工程
├── macos/                   # macOS 工程
├── linux/                   # Linux 工程
├── windows/                 # Windows 工程
├── lib/
│   ├── models/              # 话题、用户、统计等模型
│   ├── pages/               # 页面
│   ├── providers/           # Riverpod 状态管理
│   ├── services/
│   │   ├── discuz/          # Equn Discuz 数据源、解析器、会话适配
│   │   ├── discourse/       # 历史兼容层
│   │   └── network/         # 网络、Cookie、代理与拦截器
│   ├── widgets/             # 通用组件
│   └── main.dart
├── packages/                # 本地 Flutter/Dart 包
├── core/                    # Native / Rust 相关模块
├── tool/                    # 项目脚本
├── docs/                    # 开发与打包文档
└── test/                    # 单元测试与组件测试
```

## 技术栈

- Flutter + Material Design 3
- Riverpod
- Dio / Native Dio Adapter
- Discuz mobile API + HTML 解析
- flutter_inappwebview
- shared_preferences / flutter_secure_storage
- Rust / FFI native 组件

## 关于更新源

应用内更新检查使用：

```text
https://api.github.com/repos/kamisangk/equndo/releases/latest
```

## 许可证

本项目沿用 [GPL-3.0](LICENSE) 协议开源。

## 致谢

- [FluxDO](https://github.com/Lingyan000/fluxdo)
- [中国分布式计算论坛](https://equn.com/forum/)
