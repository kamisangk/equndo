# polyfill-bundle

给老 WKWebView (主要 iOS 15+) 打包 ES2022+ polyfill。产物 `assets/polyfill/compat-polyfill.js` 由 Flutter 侧 `WebViewSettings` 作为 `InAppWebView.initialUserScripts` 注入。

## 为什么

iOS 15 的 WKWebView 永远停在 Safari 15.x（Apple 不会单独升级 WebView），Discourse 前端持续升级用了越来越多 ES2022 / ES2023 / ES2024 API。手写 polyfill 容易漏；这里改成 `@babel/preset-env` + `core-js` + `browserslist` 一站式覆盖。

## 工作流

抬基线 / 升级 polyfill / 修改错误捕获都走 build：

```bash
cd tools/polyfill-bundle
pnpm install          # 仅首次
pnpm build            # 产物直接写到 ../../assets/polyfill/compat-polyfill.js
```

产物 **入仓**：开发者拉代码即可运行，不依赖本地 Node。

## 配置点

| 想做的事 | 改哪 |
|---|---|
| 抬高 / 降低浏览器基线 | `package.json` → `browserslist` |
| 升级 core-js 拿新 polyfill | `pnpm up core-js` → `pnpm build` |
| 加自定义脚本（如错误捕获） | `src/error-reporter.js` 之类，再 `import` 进 `src/index.js` |

## 产物特征

- IIFE 包裹，无 `import` / `export` 残留
- 顶部 `/* @generated */` banner，提示不要手改
- minified，~30–60 KB（按 iOS >= 15.0 基线估算）
- 所有 polyfill 内部都有存在性检测 → 在新平台零副作用
