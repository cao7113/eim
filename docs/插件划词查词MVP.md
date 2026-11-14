# 插件划词查词 MVP 技术方案

*方案 · 2026-11-10 · 基于现有 ECDICT 查询 API 和 WXT/Svelte 插件骨架*

## 1. 目标与范围

### 目标

在普通网页中选中英文单词或短语后，插件自动显示释义浮层；结果来自 Eim 自有词典 API，至少展示原文、词条原型、音标、词性和中文释义。

### MVP 范围

- 复用现有 Chrome MV3 / WXT / Svelte 插件及 Shadow DOM 浮层。
- 复用 `GET /api/dict/lookup?text=...`，不新建翻译服务。
- 选中文本后自动发起查询并展示结果，不增加“翻译”按钮。
- 只使用词典结果；未命中时明确提示“词典暂无结果”。
- 处理加载、无结果、请求失败及连续选词等基本状态。

### 暂不实现

- LLM 整句翻译、登录、收藏、生词本与同步。
- 生产环境 API 地址、认证、限流、发布和商店上架。
- 对长句进行分句或本地翻译。当前词典层对句子会返回 miss。

## 2. 当前基础

- `extension/src/entrypoints/content/index.ts` 已注入内容脚本并通过 Shadow DOM 创建 UI。
- `extension/src/entrypoints/content/App.svelte` 监听鼠标松开，取得选区、显示加载/命中/miss/错误状态，并处理关闭、定位和旧请求竞态。
- `extension/src/entrypoints/background.ts` 校验消息后请求词典 API，执行超时与响应校验，并只返回 UI 所需的结果字段。
- `extension/wxt.config.ts` 的开发模式 host permission 已包含 `http://localhost:4000/*`。
- 后端查词 API 已可通过 `GET /api/dict/lookup?text=...` 查询，并有 OpenAPI 文档。

插件初版现已接通 Background → 本地词典 API → Shadow DOM 浮层的查词链路。浏览器中使用真实词典数据的人工端到端验收仍需在本地服务启动后完成。

## 3. 技术路线

```text
网页选区
  │ mouseup / selection
  ▼
Content UI (Svelte + Shadow DOM)
  │ runtime message: { type: "lookup", text }
  ▼
Background service worker
  │ fetch + Accept: application/vnd.api+json
  ▼
GET http://localhost:4000/api/dict/lookup?text=...
  │
  ├─ hit  ─► typed lookup result ─► UI 展示词条与释义
  └─ miss ─► typed miss result   ─► UI 展示暂无词典结果
```

### 职责边界

**Content UI**

- 获取并规范化选中文本，负责浮层定位与渲染。
- 通过 `browser.runtime.sendMessage` 向 background 发起查词。
- 不直接请求后端，不持有 API 地址或网络错误细节。

**Background**

- 校验消息类型和文本长度。
- 集中封装 API 地址、请求头、URL 编码、超时和 HTTP/API 错误处理。
- 将后端响应转换为插件使用的有限类型，再通过 runtime message 返回。
- Background 是 MV3 service worker，不能依赖模块变量保存跨消息状态。

**后端**

- 继续由 `Eim.Dict.Lookup` 负责规范化和词典查询。
- MVP 不新增 endpoint、数据库表或 LLM 集成。

## 4. API 契约

### 请求

```http
GET /api/dict/lookup?text=gave
Accept: application/vnd.api+json
```

开发阶段默认地址：

```text
http://localhost:4000/api/dict/lookup
```

查询参数必须使用 URL 编码。请求由扩展 background 发出，并依赖 manifest 的 `host_permissions` 允许访问开发服务器。

### 成功响应

命中和未命中均返回同形状对象；这是当前 generic action 返回的 map，不是 JSON:API resource envelope。

```json
{
  "text": "gave",
  "kind": "word",
  "match": "exact",
  "lemma": "give",
  "phonetic": null,
  "collins": 5,
  "frq_rank": 1234,
  "senses": [
    { "pos": "vt", "domain": null, "zh": "给，授予" }
  ],
  "tags": [],
  "in_context": null,
  "sources": [
    { "name": "ecdict", "version": "..." }
  ]
}
```

未命中使用 `"match": "miss"`、`"lemma": null`、`"senses": []`。UI 仅需展示 `text`、`lemma`、`phonetic` 和 `senses` 中的词性与中文释义；其他字段留给后续扩展。

非法输入或服务端错误按 JSON:API errors 返回。Background 应从错误响应提取可展示信息，但不把任意错误对象透传给 UI。

## 5. 选区与浮层行为

1. 监听网页 `mouseup`；如果事件来自插件自身 Shadow DOM，忽略。
2. 读取 `window.getSelection()`，去除首尾空白；无选区则隐藏浮层。
3. 读取 selection range 的矩形，浮层显示在选区附近；定位应处理视口边缘，避免浮层完全跑出屏幕。
4. 更新当前查询标识并立即展示选中文本和加载状态，再发送查词消息。
5. 收到响应时仅当响应对应当前选区，才更新浮层，防止较慢的旧请求覆盖新选区。
6. 点击浮层外或按 Escape 关闭；浮层自身操作不得触发网页选区查询。
7. 清空选区、失焦或页面滚动时，按实现体验调整定位或隐藏浮层，避免展示与选区脱离的旧结果。

### 输入约束

- 复用后端上限：最多 500 个字符；超过限制时不发请求，显示简洁提示。
- 仅空白输入不请求。
- 单词和短语按词典查询；句子仍可请求并接受 miss，界面显示“词典暂无结果”，不称为“句子翻译”。
- MVP 不做复杂的 HTML/表单区域排除规则；应确认页面输入框选词时的行为，避免干扰文本编辑。

## 6. 状态和错误展示

| 状态 | 行为 |
|---|---|
| 加载中 | 显示选中文本和“查询中…”；新选区立即替换旧结果 |
| 命中 | 显示原文、lemma（若与原文不同）、音标（若有）、词性和中文释义 |
| 未命中 | 显示“词典暂无结果”，不显示 mock 或伪造译文 |
| 超长输入 | 不请求，提示缩短选区 |
| 网络不可用 / 超时 | 显示“暂时无法连接词典服务”，允许用户重新选词重试 |
| 非成功 HTTP / 无效响应 | 显示通用查询失败状态；详细错误写入 background 日志，避免泄露内部信息 |

请求需要有限超时；MVP 可先采用约 5 秒。新请求应使旧请求失效；若可使用 `AbortController`，可同时取消旧 fetch，但正确性仍需由请求标识保证。

## 7. 权限、CORS 与环境

- 词典请求只由 background service worker 发起，host permission 应按环境限制到实际 API host。
- 开发版允许 localhost、本地生产和正式服务三个固定环境；生产构建允许两个 HTTPS 服务，不包含 localhost 权限。
- 若开发环境请求仍被浏览器拦截，先检查生成的 manifest 和扩展 host permission。不要默认给 Phoenix API 增加宽泛 CORS；只有改为网页上下文直接请求时才需要重新评估 CORS。
- MVP 没有用户认证。API 暂时仅供本地开发使用；发布给真实用户前，必须先确定部署地址、身份验证、滥用防护和速率限制策略。
- 不在插件中放置服务端密钥。不要把用户整段网页内容或选区写入持久化存储或遥测。

## 8. 验收标准

### 功能验收

- 选中 `gave` 后自动出现浮层，展示原型 `give` 和中文释义。
- 选中有音标、词性或多条释义的词条时，已有字段按可读顺序展示；可选字段缺失不导致 UI 出错。
- 未命中时显示明确的词典未命中状态。
- 清除选区、点击外部或按 Escape 能关闭浮层。
- 连续快速选择两个不同词时，最终显示最后一个词的结果。
- API 未启动或请求超时时，浮层显示可理解的错误提示；页面其他功能仍可用。
- 500 字符上限被插件端提前处理，后端仍保留自身校验。

### 自动化验证

- `bun run check`：检查 Svelte/TypeScript 类型。
- `bun run build`：验证 Chrome 扩展构建与生成的 manifest。
- 后续可增加 background 请求转换自动化测试（命中、miss、HTTP 错误、超时、超长参数）。
- 浏览器手工测试覆盖加载、命中、miss、关闭和快速切换。
- 浏览器实测应以本地 Phoenix 服务和已导入 ECDICT 数据进行，不以 mock 响应作为端到端验收。

## 9. 实施顺序

1. [x] 定义插件侧 request/result 类型和 background 消息协议。
2. [x] 将 mock 查询替换为词典 API 请求，统一处理超时与错误。
3. [x] 更新 Svelte 浮层，展示真实结果和基本状态，并处理旧请求竞态。
4. [x] 检查 WXT host permission 与生成 manifest，确认只在开发构建开放本地 API。
5. [x] 运行类型检查与构建；[ ] 启动后端进行真实浏览器联调。

## 10. 后续阶段边界

LLM 句子翻译属于独立阶段，需要增加后端编排、认证、限流、成本控制、缓存和来源标识。不能在插件未命中时直接调用第三方 LLM，也不能将词典 miss 伪装成翻译结果。收藏和账号关联也应在 API 身份体系确定后再规划。
