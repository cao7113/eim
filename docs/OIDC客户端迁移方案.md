# Eim 接入 Authx OIDC —— 实施备案

> **文档类型**：架构决策与迁移实施记录（可复用样板）
> **项目**：Eim（Phoenix + Ash）
> **关联系统**：Authx（OIDC Provider）
> **状态**：已实施
> **实施日期**：2026-11-18
> **适用范围**：Eim Web 登录、浏览器插件登录、本地管理员与插件凭据
>
> **维护约定**：认证链路、Authx 客户端登记、OIDC 配置或插件凭据模型发生
> 变化时，必须同步更新本文件。相关协议与安全边界以 Authx 仓库
> `_local/authx/docs/` 为准。
>
> **复用到其它项目**：先读第 10 节“复用到其它项目”，其中区分了可复制的
> 通用做法与 Eim 特有实现。

---

## 1. 背景与目标

Eim 原先基于 `ash_authentication` 维护本地密码、邮箱确认、找回密码与
magic link。现改为让 Authx 统一负责认证，Eim 只保留业务身份：

- Authx：账号、密码、邮箱确认、登录、consent、ID Token 签发。
- Eim：本地用户记录、`user` / `admin` 角色、业务数据、Eim 会话与插件
  API key。

### 目标

- Web 使用 Authorization Code + S256 PKCE 接入 Authx。
- 浏览器插件直接向 Authx 发起授权，Eim 后端完成 token 交换与 ID Token
  校验，再签发 Eim API key。
- 移除 Eim 的本地密码登录、注册、找回、确认与 magic link。
- 保留 Eim 本地角色管理和管理员页面。

### 非目标

- 不合并 Eim 与 Authx 用户表。
- 不引入 refresh token、全局注销、动态客户端注册。
- 不升级 `ash_authentication`，不引入额外的 OIDC server 依赖。
- 不让业务 API 直接接受 Authx access token。

---

## 2. 版本基线

| 组件 | 版本 | 说明 |
|---|---|---|
| Elixir | `~> 1.17` | `mix.exs` 约束 |
| Phoenix | `1.8.16` | |
| Phoenix LiveView | `1.2.x` | |
| Ash | `3.37.3` | |
| ash_authentication | `4.15.1` | 提供 OIDC strategy、UserIdentity、会话与 Token |
| ash_authentication_phoenix | `2.17.4` | 登录页、auth routes、LiveView 会话 |
| Assent | `0.2.13` | OIDC discovery、token 交换、ID Token 校验 |
| Finch | `0.24.0` | 通过 `Assent.HTTPAdapter.Finch` 使用 |

> **已知问题**：`ash_authentication 4.15.1` 的默认 `:http_adapter` 指向
> `Finch` 模块而非 Assent 适配器，必须显式修正，见 4.3。

Authx 服务端使用较新的 `ash_authentication_oauth2_server`；客户端实现不
依赖该库，两侧版本可以不同。

---

## 3. 最终架构

```text
Web 浏览器
  │ 1. GET /auth/user/authx
  ▼
Eim（AshAuthentication OIDC strategy）
  │ 2. discovery + state/nonce/PKCE，302
  ▼
Authx（http://localhost:4000）
  │ 3. 登录 + consent（openid email）
  ▼
Eim /auth/user/authx/callback
  │ 4. 服务端兑换 code，校验 ID Token
  │ 5. 按 (strategy, sub) 关联/创建本地用户
  ▼
Eim 会话 Token → 浏览器

浏览器插件
  │ 1. launchWebAuthFlow 直接打开 Authx /oidc/authorize
  ▼
Authx
  │ 2. 登录 + consent
  ▼
插件回调（chromiumapp.org）→ 取 code
  │ 3. POST /api/extension/authx（code/state/nonce/verifier）
  ▼
Eim 后端
  │ 4. Assent 兑换并校验 ID Token
  │ 5. 关联本地用户，签发 Eim API key
  ▼
插件保存 API key，调用 Eim API
```

### 3.1 身份与角色边界

| 数据 | 归属 | 说明 |
|---|---|---|
| 账号、密码、邮箱确认、consent | Authx | Eim 不保存密码 |
| Authx `sub` | `user_identities.uid` | 与本地用户关联的外部身份 |
| Eim 用户 `email` | Eim `users.email` | 首次登录按已验证邮箱关联 |
| Eim `role` | Eim `users.role` | 本地角色；Authx 无业务角色 claim |
| Eim 会话 Token | Eim `tokens` | 本地 JWT，与 Authx 会话独立 |
| 插件 API key | Eim `api_keys` | 由 Eim 签发、可撤销，默认 30 天 |

### 3.2 关键设计决策

| 决策 | 选择 | 理由 |
|---|---|---|
| OIDC 客户端库 | `ash_authentication` 4.15 的 `oidc` strategy + `UserIdentity` | 与现有依赖一致，无需升级 |
| 客户端类型 | 公开客户端 `token_endpoint_auth_method=none` | 浏览器/插件无法安全保存 secret |
| 身份关联键 | `(strategy, authx sub)` | 不把 email 当主键 |
| 邮箱可信 | `trust_email_verified? true`，请求 `email` scope | Authx 仅在邮箱已确认时给出 `email_verified` |
| 用户去重 | `unique_email` upsert | 首次登录可关联已有本地用户 |
| 本地角色 | 保留 `users.role` 与现有管理页 | 角色属于 Eim 业务 |
| Web 会话 | 保留 Eim `tokens` + `load_from_session` | Authx 短暂不可用不影响已登录会话 |
| 插件凭据 | Eim 自行签发 API key | 业务授权与撤销由 Eim 控制 |

### 3.3 备选方案与否决理由

| 方案 | 结论 | 原因 |
|---|---|---|
| 长期保留本地密码 + OIDC 并存 | 否决 | 两套凭据、两套找回/确认流程，维护成本高 |
| 直接用 Assent，不经过 AshAuthentication | 否决 | 需自行实现会话、LiveView 恢复、Token 与路由，代码量更大 |
| 业务 API 直接接受 Authx access token | 否决 | `aud` 是 Authx UserInfo，无 refresh/撤销，耦合过强 |
| 仅用 email 关联用户 | 否决 | 无法区分不同 issuer/sub，存在合并风险 |
| 插件继续经 Eim 网页会话中转 | 未采用 | 可行但多一次网页登录；最终选择直连 Authx + 后端兑换 |
| 插件在客户端完成 token 交换与验签 | 否决 | 扩大凭据暴露面，且受 CORS 限制；改由 Eim 后端完成 |

---

## 4. 关键实现

### 4.1 Web 登录

- `Eim.Accounts.User` 使用 `oidc :authx` strategy：
  - `client_id` / `base_url` / `redirect_uri` 通过 `Eim.Secrets` 读取；
  - `identity_resource Eim.Accounts.UserIdentity`；
  - `client_authentication_method "none"`、`code_verifier true`、
    `nonce true`、`trust_email_verified? true`；
  - `authorization_params scope: "email"`（`openid` 由协议层加入）。
- `Eim.Accounts.UserIdentity` 使用 `AshAuthentication.UserIdentity`，
  以 `(uid, strategy)` 唯一标识 Authx 身份。
- `:register_with_authx` 使用 `upsert_identity :unique_email`，并通过
  `Eim.Accounts.Changes.SetEmailFromUserInfo` + `IdentityChange` 完成：
  - 写入/更新本地 email；
  - 建立或复用 `(authx, sub)` 身份记录；
  - 生成 Eim 会话 Token。
- `register_with_authx` 的 `oauth_tokens` 参数标记 `sensitive?: true`。
- 路由：
  - `GET /auth/user/authx`：发起授权；
  - `GET /auth/user/authx/callback`：回调；
  - `GET /sign-in`：保留为受保护页面/登录失败时的落点页；
  - 导航栏 “Sign in with Authx” 直接指向 `/auth/user/authx`；
  - 登录后导航栏为用户下拉菜单，Sign out 在菜单内。
- OIDC strategy 的 `redirect_uri` 配置填 `auth_routes` 前缀
  （开发环境 `http://localhost:4003/auth`），框架追加
  `/user/authx/callback`。

### 4.2 插件直连 Authx

**稳定扩展 ID**

Authx 对 `redirect_uri` 精确匹配，因此扩展开发版必须在 `wxt.config.ts`
的 manifest 中固定公钥 `key`。当前开发扩展 ID：

```text
mkbjhjbecifpejjljcjbadocpfiepoen
```

回调：

```text
https://mkbjhjbecifpejjljcjbadocpfiepoen.chromiumapp.org/
```

Chrome 商店版与 Firefox 需分别登记实际回调；Firefox 通过
`browser_specific_settings.gecko.id` 固定 ID。

**授权请求**

扩展生成 `verifier` / `state` / `nonce`，将三者与 `redirect_uri` 持久化到
`browser.storage.session`（MV3 service worker 可能被回收），然后直接打开：

```text
{authxIssuer}/oidc/authorize
  client_id={extension client id}
  redirect_uri=https://<extension-id>.chromiumapp.org/
  response_type=code
  scope=openid email
  state=...
  nonce=...
  code_challenge=S256(verifier)
  code_challenge_method=S256
```

回调使用 query 参数（不是 fragment），校验 `state` 后取 `code`。

**后端交换**

`POST /api/extension/authx`：

请求：

```json
{
  "code": "...",
  "state": "...",
  "nonce": "...",
  "code_verifier": "...",
  "redirect_uri": "https://<extension-id>.chromiumapp.org/"
}
```

处理：

1. 校验参数长度与 `redirect_uri` 白名单；
2. `Assent.Strategy.OIDC.callback/2` 完成 token 交换；
   - `client_authentication_method: "none"`
   - `code_verifier: true`
   - `session_params: %{state, nonce, code_verifier}`；
3. Assent 校验 ID Token 签名、`iss`、`aud`、`exp`、`state`、`nonce`；
4. 要求 `email_verified == true` 且 `sub` / `email` 存在；
5. 复用 `:register_with_authx` 关联/创建本地用户；
6. 调用现有 `create_api_key/1` 签发 Eim API key，响应结构与旧接口一致。

`GET /api/extension/me` 与 `DELETE /api/extension/session` 保持不变。

### 4.3 关键修复：Authx HTTP 适配器

`ash_authentication 4.15.1` 的默认 `:http_adapter` 指向 `Finch` 模块，
但 Assent 需要实现 `request/5` 的适配器，导致：

```text
** (UndefinedFunctionError) function Finch.request/5 is undefined or private
```

在 `config/config.exs` 显式修正：

```elixir
config :ash_authentication,
  http_adapter: {Assent.HTTPAdapter.Finch, supervisor: AshAuthentication.Finch}
```

该配置同时影响 Web OIDC 登录与插件后端交换，必须保留。

### 4.4 已移除的本地认证

- strategy / add-on：`password`、`remember_me`、`confirmation`。
- action：注册、密码登录、short-lived sign-in token、改密、找回密码、
  重置密码、密码重置请求。
- 路由：`/register`、`/reset`、确认、magic link。
- 模块：`Eim.Mailer`、两个邮件 sender、`MailboxPreview`。
- 依赖与配置：`swoosh` 及 mailer 配置。
- 插件旧链路：`GET /extension/authorize`、`POST /api/extension/token`、
  `Eim.Accounts.ExtensionAuth`、`ExtensionAuthCode`。
- 数据库列：`users.hashed_password`、`users.confirmed_at`。
- 数据库表：`extension_auth_codes`。

---

## 5. 配置与部署

### 5.1 Eim 环境变量

| 变量 | 开发默认值 | 说明 |
|---|---|---|
| `PORT` | `4003` | 生产默认 `4000` |
| `EIM_OIDC_CLIENT_ID` | `00000000-0000-7000-8000-000000000003` | Web 客户端 |
| `EIM_OIDC_ISSUER` | `http://localhost:4000` | Authx issuer |
| `EIM_OIDC_REDIRECT_URI` | `http://localhost:4003/auth` | 填 `auth_routes` 前缀 |
| `EIM_EXTENSION_OIDC_CLIENT_ID` | `00000000-0000-7000-8000-000000000004` | 插件客户端 |
| `EIM_EXTENSION_OIDC_REDIRECT_URIS` | 见下 | 逗号分隔的回调白名单 |

插件回调默认值：

```text
https://mkbjhjbecifpejjljcjbadocpfiepoen.chromiumapp.org/
```

生产必须显式设置上述变量，并保留 `TOKEN_SIGNING_SECRET`（Eim 会话签名）。

### 5.2 Authx 客户端登记

本地开发由 Authx `mix dev.seed` 自动注册：

| 客户端 | client_id | redirect_uri(s) | scope | auth method |
|---|---|---|---|---|
| Eim Web | `...0003` | `http://localhost:4003/auth/user/authx/callback` | `openid email` | `none` |
| Eim Extension | `...0004` | `https://mkbjhjbecifpejjljcjbadocpfiepoen.chromiumapp.org/` | `openid email` | `none` |

生产环境通过 `Authx.Ops.ensure_client/3` 登记，并补齐：

- Chrome 商店扩展 ID 的回调；
- Firefox 固定 ID 的回调；
- 生产 Eim 的 HTTPS 回调（`https://<eim-host>/auth/user/authx/callback`）。

### 5.3 端口

| 应用 | 端口 |
|---|---|
| Authx | 4000 |
| authx-demo | 4001 |
| authx-foo | 4002 |
| Eim | 4003 |
| Eim LiveDebugger | 4008 |

### 5.4 插件环境

`extension/src/shared/environments.ts` 为每个服务环境提供
`authxIssuer` 与 `oidcClientId`。当前仅开发环境已配置；生产与本地生产为
`null`，连接时会返回 `unavailable`，上线前必须补齐，并在
`wxt.config.ts` 中为生产 Authx issuer 增加 `host_permissions`。

---

## 6. 数据迁移与兼容

### 6.1 本项目处理

当前项目处于开发阶段，切换时直接重建开发库，不处理存量数据兼容。

- `mix dev.seed` 只创建 `dev@l.h` / `admin@l.h` 本地用户（无密码）。
- 首次 OIDC 登录时：
  - 已有同邮箱本地用户 → 关联，保留业务数据与角色；
  - 无本地用户 → 自动创建；
  - 不同 Authx `sub` 使用同一邮箱 → 框架拒绝自动合并。

### 6.2 其它项目的存量数据策略

| 场景 | 建议 |
|---|---|
| 内部/开发环境，无真实用户 | 直接重建数据库（本项目） |
| 存量用户邮箱与 Authx 一致且已验证 | 首次登录按 `email_verified` 关联；上线前核对邮箱清单 |
| 部分用户邮箱不一致 | 在 Authx 预建账号并完成确认，或经管理员受控映射；不要静默改库 |
| 需要零停机切换 | 先并存（本地密码 + OIDC），设切换窗口，再移除本地认证 |
| 无法确认邮箱归属 | 不自动合并；保留旧账号，人工核对后再关联 |

原则：**身份以 `(issuer, sub)` 为准，email 只用于首次关联且必须已验证。**

### 6.3 行为变化

- 退出 Eim 只清 Eim 会话，不退出 Authx；Authx 撤销 consent 也不会结束
  已建立的 Eim 会话。
- 已签发的 Eim 会话 Token 与插件 API key 不受切换影响。
- 本地“注册/找回密码/确认邮箱”页面由 Authx 承担。

---

## 7. 测试与验收

### 7.1 自动化

```sh
# Eim
mix precommit        # 88 passed

# Authx
cd _local/authx && mix precommit   # 97 passed

# 扩展
cd extension
bun test tests/background.test.js  # 9 passed
bun run check                       # 0 errors
bun run build
```

覆盖点：

- 同一 Authx `sub` 重复登录复用同一本地用户；
- 同邮箱关联已有用户；
- 不同 `sub` 同邮箱拒绝合并；
- 插件授权码交换、回调白名单、`email_verified`、API key 签发与撤销；
- 扩展授权 URL 的 PKCE / state / nonce / scope / client_id；
- 开发与生产 manifest。

### 7.2 可复用的测试手法

- `test/support/accounts_fixtures.ex`：通过 `:register_with_authx` 创建带
  Token 的测试用户，避免依赖密码策略。
- `test/support/stub_extension_oidc.ex`：通过
  `Application.put_env(:eim, :extension_oidc_client, ...)` 替换 OIDC 兑换，
  单元测试无需真实 Authx。
- 真实网络往返只放在手工验收，避免测试依赖外部服务。

### 7.3 手工端到端清单

发布前复验：

- [ ] Authx `mix dev.seed` 输出包含 Web 与插件两个客户端 id；
- [ ] Authx 4000、Eim 4003 启动；
- [ ] 浏览器访问 Eim → Authx 登录/consent → 回到 Eim；
- [ ] 收藏读写、管理员页面、审计事件正常；
- [ ] 插件连接账号 → 直接跳 Authx → 回调 → 获取 API key；
- [ ] 插件 `me` / 收藏 / 退出撤销正常；
- [ ] Authx 停服时已登录会话可继续访问，新登录失败有明确提示。

---

## 8. 安全红线

- 浏览器/插件不得保存 `client_secret`；使用 `none` + S256 PKCE。
- 每次授权重新生成 `state` / `nonce` / `code_verifier`，不得复用。
- `redirect_uri` 必须精确匹配白名单；扩展 ID 必须稳定。
- ID Token 必须由库完成签名、`iss`、`aud`、`exp`、`nonce` 校验；
  禁止只解析不验签。
- 展示/关联邮箱前必须确认 `email_verified == true`。
- 不得仅按 email 合并不同 `sub`。
- 不记录 code、verifier、access token、ID token 或 API key 明文。
- 插件凭据只存放在 trusted extension storage，不进入 content script、
  DOM 或同步存储。
- Eim API key 服务端哈希存储，插件退出时撤销。
- 生产必须 HTTPS；loopback HTTP 仅限本地开发。
- 业务 API 不接受 Authx access token。
- 面公网前补齐 Authx 速率限制、审计与日志脱敏。

---

## 9. 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `Finch.request/5 is undefined` | 未配置 Assent Finch 适配器 | 见 4.3 |
| `invalid_redirect_uri` | 回调不精确匹配 / 扩展 ID 变化 / base 与完整回调混淆 | 核对 Authx 登记值；固定扩展 `key` |
| `invalid_grant` | code 已用/过期、verifier 不匹配、redirect_uri 不一致 | 重新发起授权；核对 PKCE 与回调 |
| `email_verified: false` | Authx 用户邮箱未确认 | 在 Authx 完成确认流程 |
| `CannotConfirmUnconfirmedUser` | 并存期 confirmation add-on 与 OIDC 注册冲突 | 将 OIDC 注册加入 auto-confirm，或移除 confirmation |
| `hashed_password NOT NULL` | OIDC 新建用户没有密码 | 先改为可空，再迁移业务 |
| 插件回调没有 code | 直接 OIDC 回调使用 query，旧 broker 使用 fragment | 解析 `searchParams`，并校验 `state` |
| 扩展登录后提示 unavailable | 生产 `authxIssuer` / `oidcClientId` 未配置 | 补齐环境配置与 host permission |
| 本地无法同时启动 | 端口冲突 | Authx 4000、Eim 4003、LiveDebugger 4008 |
| `/register` 或密码路由 403 | 路由已移除/CSRF 拦截 | 预期行为，确认前端已改为直连 Authx |
| `mix ash.codegen` 重复生成 `vocab_entries` | 快照基线缺失 | 人工移除该段与多余 snapshot |

---

## 10. 复用到其它项目

### 10.1 需替换的参数

| 参数 | Eim 值 | 替换为 |
|---|---|---|
| 应用名/域名 | Eim / `localhost:4003` | 目标项目 |
| Web client_id | `...0003` | 目标项目注册值 |
| OIDC issuer | `http://localhost:4000` | 目标 Authx issuer |
| Web 回调 | `/auth/user/authx/callback` | 目标路由 |
| 身份 strategy 名 | `authx` | 可保持或重命名 |
| 本地用户/Token 资源 | `Eim.Accounts.User` / `Token` | 目标项目资源 |
| 角色模型 | `users.role` | 目标项目权限模型 |
| 插件 client_id | `...0004` | 目标插件注册值 |
| 插件扩展 ID/回调 | `mkbj...chromiumapp.org` | 目标开发/商店 ID |
| 环境变量前缀 | `EIM_` | 目标项目前缀 |

### 10.2 迁移步骤清单

- [ ] 决定存量数据策略（重建 / 邮箱关联 / 人工映射 / 并存切换）。
- [ ] 在 Authx 注册 Web 客户端，登记精确回调与 `openid email` scope。
- [ ] 若使用插件，注册插件客户端并固定扩展 ID 与回调。
- [ ] 确认 `ash_authentication` 版本；若为 4.15.x，必须配置
      `Assent.HTTPAdapter.Finch`。
- [ ] 新增 `oidc` strategy、`UserIdentity`、`register_with_authx` 与
      email change。
- [ ] 如与本地密码并存：先让密码列可空，并处理 confirmation add-on。
- [ ] 增加登录入口与回调路由；导航直接指向 OIDC 授权端点。
- [ ] 插件改为直连 Authx；后端新增 token 交换端点与回调白名单。
- [ ] 删除本地密码/注册/找回/确认/magic link 与邮件依赖。
- [ ] 清理密码/确认列与旧授权码表。
- [ ] 更新测试 fixture、OIDC stub、路由与手工验收清单。
- [ ] 生产补齐 env、HTTPS 回调、扩展生产配置与监控。

### 10.3 Eim 特有、复用时需重写的部分

- 本地 `role` 与管理员管理页（`Eim.Accounts.Admins`）。
- 插件 API key 的 30 天有效期与撤销逻辑。
- 插件旧 broker 流程的删除方式（若目标项目仍需要过渡期，可先保留）。
- `vocab_entries` 等业务资源与认证无关，不应复制。
- 端口号、LiveDebugger 配置、开发种子账号仅作为本地示例。

---

## 11. 限制与风险

| 限制 / 风险 | 影响 | 处理 |
|---|---|---|
| Authx 是登录单点 | 新登录不可用 | 本地会话独立；监控并提示 |
| 无 refresh token | 插件过期需重新授权 | 当前接受；生产前评估 Authx 能力 |
| 无全局注销 / `end_session` | Eim 退出不影响 Authx | 文档说明 |
| 无 token 撤销 / 内省 | Authx 撤销不即时生效 | Eim 会话与 API key 可自行撤销 |
| 角色不在 Authx | 跨应用角色不统一 | 角色明确属于 Eim 本地 |
| 邮箱关联 | 错误邮箱可能关联错误账号 | 仅信任 `email_verified`；跨 `sub` 拒绝合并 |
| 扩展 ID 稳定性 | 回调精确匹配失败 | 固定 manifest `key` / gecko id |
| 生产 Authx 未配置 | 插件登录不可用 | 上线前补齐 issuer/client/host permission |

---

## 12. 生产上线检查

- [ ] 设置 `EIM_OIDC_CLIENT_ID`、`EIM_OIDC_ISSUER`、`EIM_OIDC_REDIRECT_URI`。
- [ ] 设置 `EIM_EXTENSION_OIDC_CLIENT_ID`、`EIM_EXTENSION_OIDC_REDIRECT_URIS`。
- [ ] 设置 `TOKEN_SIGNING_SECRET`、`SECRET_KEY_BASE`、`DATABASE_URL`。
- [ ] Authx 登记生产 Web/插件客户端，回调为 HTTPS 精确值。
- [ ] 插件补齐生产 `authxIssuer` / `oidcClientId` 与 host permission。
- [ ] Chrome/Firefox 商店扩展 ID 的回调已登记。
- [ ] 监控授权失败、token 交换失败、discovery/JWKS 可达性。
- [ ] Authx 生产门禁（速率限制、审计、签名密钥轮换）已满足。
- [ ] 确定会话有效期与切换时是否清空 `tokens`。
- [ ] 回滚方案与数据库备份已确认。

### 12.1 本地生产部署准备（Eim `https://eim.s` / Authx `https://authx.s`）

本地生产使用独立数据库与 Authx 实例，客户端 id 必须重新登记，不能复用开发
固定 id。

**1. 在 Authx 本地生产登记客户端**（`bin/authx remote`）：

```elixir
Authx.Ops.ensure_client(
  "admin@authx.s",
  "Eim Web",
  ["https://eim.s/auth/user/authx/callback"]
)

Authx.Ops.ensure_client(
  "admin@authx.s",
  "Eim browser extension",
  ["https://mkbjhjbecifpejjljcjbadocpfiepoen.chromiumapp.org/"]
)
```

`ensure_client` 会生成 client id，记录后分别用于 Eim 环境和扩展构建。

**2. Eim 本地生产环境变量**：

```text
EIM_OIDC_ISSUER=https://authx.s
EIM_OIDC_CLIENT_ID=01a1eefa-5d7d-7e51-ad60-9e5ef4a0e7b6
EIM_OIDC_REDIRECT_URI=https://eim.s/auth
EIM_EXTENSION_OIDC_CLIENT_ID=01a1eefa-8367-7a43-a6e3-29d58e1ae712
EIM_EXTENSION_OIDC_REDIRECT_URIS=https://mkbjhjbecifpejjljcjbadocpfiepoen.chromiumapp.org/
```

**3. 扩展以 unpacked 文件夹导入**：

```sh
cd extension
WXT_UNPACKED=1 \
WXT_LOCAL_PRODUCTION_OIDC_CLIENT_ID=xxx \
bun run build
```

然后在 `chrome://extensions` 开启开发者模式，选择“加载已解压的扩展程序”，
指向 `extension/.output/chrome-mv3`。

- `WXT_UNPACKED=1` 让 manifest 带上固定 `key`，扩展 ID 保持
  `mkbjhjbecifpejjljcjbadocpfiepoen`，与 Authx 登记的回调一致。
- 不带 `WXT_UNPACKED=1` 的正式构建不含 `key`，用于商店发布。
- 生产 manifest 的 host permissions 自动包含 `https://eim.s/*`、
  `https://authx.s/*`、`https://eim.fly.dev/*`。
- 本地生产的 Authx 管理员、developer 与用户初始化按 Authx `docs/ops.md`
  执行。

---

## 13. 回滚

| 范围 | 方式 |
|---|---|
| Authx 客户端 | 删除对应 `*_client_app` 配置与已注册客户端 |
| Eim 代码 | 回滚发布；`20261118085404.down` 恢复 `hashed_password` / `confirmed_at` 列（数据不恢复） |
| 数据库 | `user_identities` 可保留；`tokens` / `api_keys` 不删除 |
| 插件 | 回滚扩展发布；旧 broker 代码已删除，无法在不回滚 Eim 的情况下恢复 |

---

## 14. 相关文档

- `_local/authx/docs/authx-foo-oidc-client.md`：客户端接入代码参考
- `_local/authx/docs/authx-foo-ash-libraries.md`：Ash 依赖分工
- `_local/authx/docs/oidc-scopes.md`：scope 与 claim 语义
- `_local/authx/docs/browser-extension-oidc.md`：插件接入模型
- `_local/authx/docs/oidc-client-management.md`：客户端注册与归属
- `_local/authx/docs/oidc-production.md`：生产门禁

---

## 15. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-18 | 初版实施备案：Web OIDC、插件直连 Authx、本地认证移除、HTTP 适配器修复 |
| 2026-11-18 | 补充本地生产部署准备、unpacked 扩展构建方式与后续优化建议 |

---

## 16. 后续优化建议

| 优先级 | 事项 | 说明 |
|---|---|---|
| P0 | 完成真实端到端验收 | 浏览器登录与插件连接各跑一遍，把结果和日期补进变更记录 |
| P0 | `/api/extension/authx` 限流与审计 | 按 IP/client 限流，记录失败事件，防止授权码兑换被滥用 |
| P1 | 本地生产客户端登记 | 按 12.1 注册 Web/插件客户端并回填 client id |
| P1 | 生产扩展配置 | 补齐 `authxIssuer` / `oidcClientId`、商店扩展 ID 回调与 host permission |
| P1 | 可观测性 | 为授权失败、token 交换失败、discovery/JWKS 不可达增加 Telemetry 指标 |
| P1 | 会话策略 | 明确会话有效期、切换时是否清空 `tokens`、多设备行为 |
| P2 | 抽取共享实现 | 将 `ExtensionOidc`、OIDC 测试 fixture/stub、Secrets 读取抽成共享包或项目模板 |
| P2 | 插件凭据轮换 | 评估 API key 轮换、缩短有效期与多设备策略 |
| P2 | 生产门禁复核 | 按 Authx `oidc-production.md` 复核速率限制、审计、JWKS 轮换 |
