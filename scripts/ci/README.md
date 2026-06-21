# CI 脚本目录

`scripts/ci/` 只保留 CI / 打包链路内部脚本，不作为日常开发入口。

当前按领域分层：

- `scripts/ci/linux/`
  - Linux bundle 构建与 Linux 插件补丁
- `scripts/ci/flatpak/`
  - Flatpak source tree、WPE layer、容器内打包及离线修补

约定：

- 本地开发、运行、构建、发版统一走 `just`；需要脱离 `just` 时直接调用 `tool/*.dart`
- `melos` 只保留 workspace bootstrap，不再扩张为本地开发命令面
- CI shell/python 脚本只保留工作流级环境胶水，不承载项目业务逻辑
