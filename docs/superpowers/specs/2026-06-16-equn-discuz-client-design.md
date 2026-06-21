# equn Discuz 客户端适配设计

## 背景

当前产品 FluxDO 是面向 Linux.do 的 Discourse 客户端。用户要求将产品适配为 `https://equn.com/forum` 的客户端。目标站点是 Discuz! X3.5 论坛，不是 Discourse，也不是 `https://equn.com` 根站。

这次改造不能只替换域名。现有首页列表、分类、详情、登录态、通知、书签、实时消息等大量代码都依赖 Discourse API。第一阶段目标是建立 equn Discuz 的可浏览闭环，并隐藏或移除会继续访问 Discourse 的入口。

## 目标

第一阶段交付一个可用的 equn 论坛浏览客户端：

- 所有主浏览请求使用 `https://equn.com/forum/` 作为站点根地址。
- 首页默认显示“最新回复”，来源为 `forum.php?mod=guide&view=new`。
- 首页提供“最新回复”和“最新发表”两个选项。
- “最新发表”来源为 `forum.php?mod=guide&view=newthread`。
- 右侧或侧边栏展示 equn 的 Discuz 分区和板块。
- 点击板块后显示该板块主题列表。
- 点击主题后显示主题详情；权限不足时显示明确状态。
- 强依赖 Discourse 的功能先隐藏或下线，避免出现无法工作的入口。

## 非目标

第一阶段不实现以下能力：

- Discourse MessageBus 实时推送。
- Discourse 通知、徽章、投票、solved、标签、书签、已读/未读同步。
- 发帖、回帖、编辑、上传、私信等登录后写操作。
- 完整账号体系迁移。
- equn 根站、百科、门户页面的客户端适配。
- 彻底删除所有历史 Discourse 文件。物理删除放在第二阶段，以避免一次性扩大构建风险。

## 数据来源

### 板块分区

使用 Discuz mobile API：

`https://equn.com/forum/api/mobile/index.php?version=4&module=forumindex`

该接口返回：

- `Variables.catlist`：分区列表，包含分区 fid、名称和子板块 fid 列表。
- `Variables.forumlist`：板块列表，包含 fid、名称、主题数、帖子数、图标和子板块信息。

客户端将这些数据映射为现有 `Category` 概念，或新增更清晰的 `DiscuzForum` / `DiscuzForumGroup` 模型。推荐新增 Discuz 专用模型，再在 UI 边界转换，避免把 Discuz 字段硬塞进 Discourse 命名模型。

### 首页导读列表

Discuz mobile API 没有可用的 `guide` module。首页两个列表使用 HTML 解析：

- 最新回复：`forum.php?mod=guide&view=new`
- 最新发表：`forum.php?mod=guide&view=newthread`

解析 `#threadlist tbody[id^=normalthread_]` 中的主题条目：

- 主题 id：从 `normalthread_<tid>` 或 `thread-<tid>-...html` 提取。
- 标题：从 `a.xst` 提取文本。
- 链接：转换为 `https://equn.com/forum/thread-<tid>-1-1.html` 或保留原始相对链接解析结果。
- 板块：从“版块/圈子”列提取名称和 fid。
- 作者：从作者列提取用户名。
- 回复数和浏览数：从 `td.num` 提取。
- 最后发表：从最后发表列提取用户名和时间文本。
- 权限信息：保留标题旁的阅读权限文本，用于列表提示。

时间先按原站文本展示。若 API 返回 Unix 时间戳则转为本地时间；不要复用 Discourse 的 UTC 时间假设。

### 板块主题列表

优先使用 Discuz mobile API：

`api/mobile/index.php?version=4&module=forumdisplay&fid=<fid>&page=<page>`

该接口返回 `Variables.forum_threadlist`，可用于主题列表和分页。字段包括 tid、fid、subject、author、dateline、lastpost、lastposter、views、replies、readperm、displayorder、digest、attachment 等。

如果 API 返回异常或字段缺失，第二选择解析：

`forum-<fid>-<page>.html`

### 主题详情

优先使用 Discuz mobile API：

`api/mobile/index.php?version=4&module=viewthread&tid=<tid>&page=<page>`

处理规则：

- 正常主题：使用 `Variables.thread` 和 `Variables.postlist` 渲染。
- 权限不足：如果 `Message.messageval` 为 `thread_nopermission...`，显示“权限不足或需要登录后查看”，并提供“在网页中打开”。
- 空 `postlist` 且存在权限错误时不能显示为空列表。
- 图片和附件先以链接或已有 HTML 内容渲染能力降级展示，不做完整上传/下载管理。

## 架构设计

### 服务层

新增 Discuz 专用服务边界：

- `lib/services/discuz/equn_discuz_service.dart`
- `lib/services/discuz/equn_discuz_models.dart`
- `lib/services/discuz/equn_discuz_parser.dart`

服务职责：

- 统一 base URL 为 `https://equn.com/forum/`。
- 通过 Dio 请求 mobile API 和 HTML 页面。
- 调用 parser 将 API/HTML 转换为 Discuz 专用模型。
- 对权限不足、网络错误、解析错误返回明确异常或状态对象。

不要在 `DiscourseService` mixin 中继续增加 Discuz 逻辑。旧 `discourseServiceProvider` 可以暂时保留给未改造页面，但首页浏览链路必须切到新的 Discuz provider。

### Provider 层

新增或替换首页所需 provider：

- `equnDiscuzServiceProvider`
- `equnGuideFilterProvider`
- `equnGuideTopicsProvider`
- `equnForumGroupsProvider`
- `equnForumTopicsProvider(fid)`
- `equnThreadDetailProvider(tid, page)`

`equnGuideFilterProvider` 只有两个值：

- `latestReplies`：最新回复，默认值，URL view 为 `new`。
- `latestThreads`：最新发表，URL view 为 `newthread`。

### UI 层

第一阶段尽量复用现有首页列表和帖子卡片视觉，但降低 Discourse 专属控件：

- 首页筛选栏只显示“最新回复”和“最新发表”。
- 隐藏“新话题”“未读”“Top”“Hot”等 Discourse 筛选。
- 隐藏标签筛选、排序参数、实时新主题提示。
- 侧栏或右侧分类入口改为 equn 分区和板块列表。
- 板块主题页复用现有列表布局。
- 详情页复用现有内容渲染组件，但移除 Discourse 专属操作按钮。

导航仍使用现有 Flutter 路由结构，但传入 tid/fid 而不是 Discourse slug/category。

## Discourse 功能处理

第一阶段隐藏或禁用这些入口：

- 通知页和通知角标。
- 书签页。
- 徽章页。
- 私信页。
- 创建话题、编辑话题、回复和上传。
- MessageBus 相关 provider。
- Discourse 搜索和标签搜索。
- Notion 同步中与 Discourse topic/post 结构强绑定的入口。
- Linux.do 专属 LDC、connect、CDK 入口。

保留通用设置、主题外观、网络设置、日志、WebView 打开网页等非站点专属能力。

## 错误处理

- 网络错误：列表显示可重试错误状态。
- HTML 结构变化：parser 抛出解析异常，UI 显示“页面结构无法识别”。
- 权限不足：详情页显示权限提示，不作为普通错误。
- 空列表：显示“没有相关主题”。
- 跳转到 equn 根站或外链：使用现有外链打开策略。

## 测试策略

先写测试再实现：

- `equn_discuz_parser_test.dart`
  - 解析 guide 最新回复 HTML。
  - 解析 guide 最新发表 HTML。
  - 解析 forumindex JSON 的分区和板块。
  - 解析 forumdisplay JSON 的主题列表。
  - 识别 viewthread 权限不足响应。
- Provider 测试
  - 默认 guide filter 是最新回复。
  - 切换最新发表后请求 view 为 `newthread`。
  - 板块 provider 按 fid 请求主题列表。
- Widget 测试
  - 首页只显示“最新回复”和“最新发表”。
  - 权限不足详情显示明确提示。

测试样本使用最小化 fixture，不直接依赖在线站点，避免 CI 受网络影响。

## 实施顺序

1. 新增 Discuz 模型、parser 和失败测试。
2. 实现 parser，让解析测试通过。
3. 新增 Equn Discuz service 和 provider。
4. 改造首页筛选和列表数据源。
5. 改造分区/板块侧栏。
6. 改造板块主题页。
7. 改造主题详情页的读取和权限状态。
8. 隐藏 Discourse 专属入口。
9. 运行 `flutter test` 和静态分析，修复回归。

## 验收标准

- App 启动后主浏览页访问 `https://equn.com/forum/` 相关资源。
- 首页默认显示 equn 的“最新回复”列表。
- 可切换到“最新发表”。
- 右侧或侧栏能看到 equn 分区和板块。
- 点击板块能看到对应主题列表。
- 点击可访问主题能看到详情。
- 点击权限不足主题显示权限提示。
- 主浏览链路不再请求 Discourse 的 `/latest.json`、`/site.json`、MessageBus 频道。
