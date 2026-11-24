# Admins 重构方案（参考 `_local/authx`）

> 状态：**方案 v2，已按第 12 节的建议实施**（代码已写入工作区）。
> 参考实现：`_local/authx/lib/authx/admins/*`、`lib/authx/accounts.ex`、`lib/authx/ops.ex`、`lib/authx/accounts/user.ex`、`lib/mix/tasks/dev.admin.ex`、`config/dev.exs`。
> v2 相对 v1 的调整：**去掉撤销（revoke）**，连带去掉 `last_admin`、advisory lock、PubSub 撤权广播；`Ops`、`master_email`、`AdminCheck` 位置、facade 函数名**全部按 authx 对齐**。

## 1. 结论摘要

1. **存储模型**：管理员身份从 `users.role` 迁移到独立 `admins` 表（新增 `Eim.Admins.Admin` 资源），删除 `users.role` 列与约束。
2. **只做授予，不做撤销**：`Admin` 资源只有 `:read` 和 `:grant` 两个 action。没有 `:destroy`、没有 `:update`，因此没有第二条写入路径。
3. **严格照搬 authx 的规范**：
   - 目录/命名：`Eim.Admins`（facade）、`Eim.Admins.Domain`、`Eim.Admins.Admin`、`Eim.Admins.Checks.AdminCheck`、`Eim.Admins.Changes.SetGrantedBy`
   - 函数名：`list/1`、`fetch_admin_by_user_ref/2`、`get_admin_by_user_ref/2`、`admin?/2`、`grant_admin/2`、`bootstrap_admin/1`、`fetch_admin_user_by_ref/2`、`get_admin_user/2`、`master_email/0`、`master/0`
   - `Eim.Accounts.fetch_user_by_ref/2`（`:uuid | String.t() | User.t()`）
   - `Eim.Ops`（IEx / mix task 专用入口，`@moduledoc` 声明信任边界）
   - `config :eim, :master_email`（dev 默认 `"admin@l.h"`，prod 读 `MASTER_EMAIL`）
4. **保留 eim 的审计能力**：`Eim.Audit.Event` 与 `admins` 写入同事务，失败回滚；`event_type` 只有 `admin.granted`。
5. **删掉的能力**（v1 有、v2 无）：撤销管理员、`last_admin` 保护、`already_bootstrapped` 守卫、advisory lock + 锁内重读、`access_topic` / PubSub 管理页面关闭频道。理由见第 6 节。

---

## 2. 现状（eim）

| 文件 | 作用 |
| --- | --- |
| [lib/eim/accounts/admins.ex](../lib/eim/accounts/admins.ex) | facade：`admin?/1`（出错即 raise）、`admin_status/1`、`bootstrap/1`、`set_role/3`、`find_by_email/2` |
| [lib/eim/accounts/user.ex](../lib/eim/accounts/user.ex) | `role` 属性、`:set_admin_role` / `:bootstrap_admin` action、policies、`admin do table_columns [:email, :role]` |
| [lib/eim/accounts/changes/change_admin_role.ex](../lib/eim/accounts/changes/change_admin_role.ex) | advisory lock + 锁内重读 + `last_admin`/`already_bootstrapped`/`forbidden` + 写审计 + 广播撤销 |
| [lib/eim/accounts/checks/admin_check.ex](../lib/eim/accounts/checks/admin_check.ex) | policy check，返回 `{:ok, boolean}` |
| [lib/mix/tasks/dev.seed.ex](../lib/mix/tasks/dev.seed.ex) | 硬编码 `@admin_email "admin@l.h"`，自写「找现有管理员 → set_role」分支 |

调用点：`lib/eim_web/plugs/require_admin.ex`、`lib/eim_web/live_user_auth.ex`、`lib/eim_web/admin_auth.ex`、`lib/eim_web/live/admin_users_live.ex`（本次删除）、`lib/eim_web/components/layouts.ex`、`lib/eim_web/oban_resolver.ex`、`lib/mix/tasks/dev.seed.ex`。

**重构后必须仍然成立的行为**：

1. 未登录 / 非管理员访问 `/manage/users`、`/admin`、`/oban` → 重定向 `/`。
2. 非管理员调用授权接口 → `:forbidden`；不带 actor 的显式授权调用（`authorize?: true`）同样 Forbidden。
3. OIDC 注册（`register_with_authx`，含 `user_info["role"] == "admin"`）无法获得管理员。
4. 授予管理员时同事务写一条 `admin.granted` 审计；写审计失败则授予回滚；重复授予不写第二条。
5. `Admins.admin?/1` 对 `nil` / 非法 UUID / 不存在的用户返回 `false`，**不抛异常**（当前 `admin_status/1` 的 `{:ok, boolean}` 被 Ash 当成 policy 结果解释，DB 异常会在 [layouts.ex:45](../lib/eim_web/components/layouts.ex#L45) 直接 500）。

---

## 3. 参考实现（authx）结构

| authx | 说明 |
| --- | --- |
| `Authx.Admins` | facade：`list/1`、`fetch_admin_by_user_ref/2`、`get_admin_by_user_ref/2`、`master_email/0`、`master/0`、`fetch_admin_user_by_ref/2`、`get_admin_user/2`、`admin?/2`、`grant_admin/2`、`bootstrap_admin/1` |
| `Authx.Admins.Admin` | 资源：`defaults [:read]` + `create :grant`（`accept [:user_id]` + `SetGrantedBy`）、`identity :unique_user, [:user_id]`、`granted_at`、`belongs_to :user` / `:granted_by`、`user_email`/`granted_by_email` 计算 |
| `Authx.Admins.Domain` | `Ash.Domain`，单独注册到 `ash_domains` |
| `Authx.Admins.Checks.AdminCheck` | `match?(%User{} = actor, ...)` → `Admins.admin?(actor)` |
| `Authx.Admins.Changes.SetGrantedBy` | 从 actor 强制写 `granted_by_user_id`，**不接受客户端传入**，防伪造 |
| `Authx.Accounts.fetch_user_by_ref/2` | UUID 走 id、其余当邮箱；内部 `authorize?: false` |
| `Authx.Ops` | IEx / mix task 专用；`bootstrap_admin_user/1`、`ensure_new_admin_user/2`；`@moduledoc` 明确「Never call this module from the web application」 |
| `Mix.Tasks.Dev.Admin` | 仅 dev；`Admins.master_email() \|> Ops.ensure_new_admin_user(dev_password)` |
| `config/dev.exs` | `master_email: "admin@l.h"`、`dev_password: ...` |

**两个必须照搬的实现细节**：

1. `fetch_admin_by_user_ref/2` 读 `Admin` 时显式 `authorize?: false` —— 否则 `AdminCheck → admin? → 读 Admin → AdminCheck` 递归（authx 源码里有注释）。
2. `grant_record/3`：先 `admin?(user)`，已是管理员就直接返回，否则 `Ash.Changeset.for_create(:grant, %{user_id: user_id})`。幂等性由「先查后建 + `unique_user` 唯一约束」共同保证。

**authx 刻意没有的东西**：撤销、`last_admin`、bootstrap 一次性守卫、PubSub、业务审计事件。v2 方案与之保持一致，除审计外全部放弃（见第 6 节）。

---

## 4. 目标设计

### 4.1 数据模型

```
admins
  id                 uuid pk
  user_id            uuid not null → users(id) on delete cascade  (unique index)
  granted_by_user_id uuid null     → users(id) on delete set null
  granted_at         timestamptz not null default now()
  inserted_at / updated_at
```

为什么用独立表而不是继续用 `users.role`：

- 授权事实自带留痕：`granted_by_user_id` + `granted_at` 表达「谁在何时授权」。
- **结构上杜绝注册路径授权**：`register_with_authx` 是 `upsert_identity :unique_email`，把角色放在同一行意味着任何 upsert 路径都有机会触碰它（现在靠 `force_change_attribute` + policy 防御）。角色独立成表后，注册 action 根本写不到 `admins`。
- 与 authx 的 `users` 表结构对齐，身份镜像更干净；将来出现第二种角色（authx 的 `Developers`）时不需要扩展枚举。

### 4.2 模块结构

```
lib/eim/admins.ex                              # facade（替代 Eim.Accounts.Admins）
lib/eim/admins/domain.ex                       # Eim.Admins.Domain
lib/eim/admins/admin.ex                        # Eim.Admins.Admin
lib/eim/admins/checks/admin_check.ex           # 从 Eim.Accounts.Checks 迁入
lib/eim/admins/changes/set_granted_by.ex       # 照搬 authx
lib/eim/admins/changes/record_admin_event.ex   # eim 独有：事务内审计
lib/eim/ops.ex                                 # 照搬 Authx.Ops 的定位
```

`Eim.Admins`（facade）与 `Eim.Admins.Domain` / `Eim.Admins.Admin` 共存没有问题（authx 已验证）。

### 4.3 公开 API（与 authx 同名同序）

```elixir
# Eim.Admins
@type user_ref :: Eim.Accounts.User.t() | String.t()

list(filters \\ %{})                        # {:ok, [Admin.t()]} | {:error, term}
fetch_admin_by_user_ref(user_ref, opts \\ []) # {:ok, Admin.t()} | {:error, :not_admin | :not_found_user | term}
get_admin_by_user_ref(user_ref, opts \\ [])   # Admin.t() | nil
fetch_admin_user_by_ref(user_ref, opts \\ []) # {:ok, User.t()} | {:error, ...}
get_admin_user(user_ref, opts \\ [])          # User.t() | nil
admin?(user_ref, opts \\ [])                  # boolean（不抛异常）
master_email()                                # String.t() | nil
master()                                      # User.t() | nil
grant_admin(%User{} = user, %User{} = actor)  # {:ok, Admin.t()} | {:error, %Ash.Error.Forbidden{}} | ...
bootstrap_admin(%User{} = user)               # {:ok, Admin.t()} | {:error, ...}（无 actor，authorize?: false）

# Eim.Accounts（新增，照搬 Authx.Accounts）
fetch_user_by_ref(user_ref, opts \\ [])       # 内部 authorize?: false

# Eim.Ops
bootstrap_admin_user(user_ref)                # 解析用户 → bootstrap_admin → {:ok, User.t()}
```

约定（照 authx）：查询接受 `user_ref`；**写操作接受 `%User{}`（目标）与 `%User{}`（actor）**，actor 由调用方从 session / IEx 解析。`find_by_email/2` 与 `/manage/users` 页面一并删除：管理员管理统一走 Ash Admin 的 `/admin`（`Eim.Admins.Admin` 资源），`Eim.Accounts.User` 的 `:get_by_email_as_admin` action 与 policy 随之移除。

### 4.4 授权模型

`Eim.Admins.Admin`：

```elixir
actions do
  defaults [:read]
  create :grant do
    accept [:user_id]
    change Eim.Admins.Changes.SetGrantedBy
    change Eim.Admins.Changes.RecordAdminEvent
  end
end

policies do
  policy action(:read),  do: authorize_if(Eim.Admins.Checks.AdminCheck)
  policy action(:grant), do: authorize_if(Eim.Admins.Checks.AdminCheck)
end
```

- 没有 `:update`、没有 `:destroy`、不用 `defaults [:destroy]` → AshAdmin 的删除/修改入口不存在，无法绕过 `RecordAdminEvent`。
- `bootstrap_admin/1` 是唯一 `authorize?: false` 的写入路径，与 authx 一致（**不再**额外定义 `:bootstrap` action）：安全边界是「能执行 `authorize?: false` 的代码 = 受控 IEx / mix task」，这一点由 `Eim.Ops` 的 `@moduledoc` 和 [docs/ops.md](../docs/ops.md) 声明。
- `AdminCheck` 迁到 `Eim.Admins.Checks`（authx 位置），同步更新 `Eim.Audit.Event` 的 `:read` policy；`match?/3` 返回纯布尔。

### 4.5 写入流程（`:grant`）

1. Ash 授权：`AdminCheck` → `Admins.admin?(actor)`（读 `admins`，`authorize?: false`）。
2. `SetGrantedBy`：有 actor 时 `force_change_attribute(:granted_by_user_id, actor.id)`；无 actor（bootstrap）时保持 `nil`。
3. `RecordAdminEvent`（`after_action`）：同事务写 `Eim.Audit.Event`，`event_type: "admin.granted"`，`details: %{old_role: :user, new_role: :admin, method: method}`，`method` 由 actor 是否存在推导（有 actor → `:admin`，无 actor → `:bootstrap`），与现有 `actor_id = nil` 的语义完全一致；写失败 → 整个授予回滚。
4. facade 的 `grant_record/3`：先 `admin?(user)`，已存在则直接返回（不写事件）；否则 `Ash.create`。

**并发**：不做 advisory lock（无撤销即无「零管理员」不变量）。同一用户并发双授予由 `unique_user` 唯一约束兜底：后到者收到唯一约束错误，重试即可（facade 不解析该错误，保持与参考实现一致）。不同用户并发授予互不影响。

### 4.6 审计

- `Eim.Audit.Event` 资源、domain、policy（`AdminCheck`）、AshAdmin 展示不变。
- `details` 沿用 `old_role` / `new_role` / `method` 三个键，值与现在一致（`user` / `admin`；`bootstrap` / `admin`）。授予场景下 `old_role`/`new_role` 恒定，保留是为了文档格式稳定与撤销功能回归时不需要改事件结构。
- 撤销回归时（未来）：新增 `:revoke` action + `admin.revoked` 事件 + `last_admin` 守卫 + PubSub 广播，全部加在 `Eim.Admins` 内部，不影响本方案的公开 API。

---

## 5. 与 authx 的对齐 / 刻意偏离

| authx | 本方案 | 说明 |
| --- | --- | --- |
| 独立 `admins` 表、`Admin` 资源、`Domain`、`AdminCheck`、`SetGrantedBy` | ✅ 照搬 | |
| `grant_admin/2` + `bootstrap_admin/1`，无撤销 | ✅ 照搬 | 本次明确不要撤销 |
| `Ops` + `master_email/0` + `master/0` | ✅ 照搬 | 见 4.3 / 6.2 |
| `Authx.Accounts.fetch_user_by_ref/2` | ✅ 照搬 | |
| 只读 + `:grant` 两个 action | ✅ 照搬 | 安全收益：无第二条写入路径 |
| `grant_record` 对已存在的管理员返回 `{:ok, user}`、首次返回 `{:ok, admin}`（返回类型不一致） | ❌ 偏离：统一返回 `{:ok, %Admin{}}` | 调用方 pattern match 更稳定；`Ops.bootstrap_admin_user` 再统一转成 `{:ok, %User{}}` |
| `fetch_admin_by_user_ref/2` 把「没有管理员记录」（`Ash.read_one` 的 `{:ok, nil}`）当作 `{:ok, admin}` 返回 | ❌ 偏离：只匹配 `%Admin{}`，否则 `{:error, :not_admin}` | 参考实现里 `fetch_admin_user_by_ref/2` 因此会对**非管理员**也返回用户，`Admins.master/0` 会报出一个并非管理员的账号。测试里已加回归断言（`master/0` 在账号存在但未授权时为 `nil`） |
| `Authx.Ops.ensure_new_admin_user/2`（本地密码注册） | ❌ 不引入 | eim 没有本地密码注册，用户来自 authx OIDC；`dev.seed` 用 `Ash.Seed.upsert!` 造本地镜像 |
| `mix dev.admin` | ❌ 不新增 | eim 的 `mix dev.seed` 已覆盖（创建 `dev@l.h` + `master_email` 用户），避免两个重叠 task；`dev.seed` 内部改为 `Ops.bootstrap_admin_user(Admins.master_email())` |
| `list/1` 用 `authorize?: false` | ✅ 照搬 | 运维/调试用途，注释说明 |

---

## 6. 行为变化（相对现状）

### 6.1 删除的能力

| 能力 | 处理 | 原因 |
| --- | --- | --- |
| 撤销管理员 `set_role(actor, user, :user)` | 删除 | 本次不需要；撤销回归时按 4.6 末尾的方式加回 |
| `:last_admin` 保护 | 删除 | 没有撤销，就没有「零管理员」状态 |
| `:already_bootstrapped` 守卫 | 删除，`bootstrap_admin/1` 改为幂等 | authx 语义：对已是管理员者返回现有记录；对非管理员者授予。**注意这是有意的能力变化**：IEx 里对任意用户调用 `bootstrap_admin` 会授予其管理员，信任边界完全落在 IEx 访问控制上 |
| advisory lock + 锁内重读 | 删除 | 只为「并发互撤」而存在；grant-only 下由 `unique_user` 约束兜底 |
| `Admins.access_topic/1`、`AdminAuth` 的订阅与 `handle_info`、`AuthController.sign_out/2` 的广播、`:admin_access_revoked` 消息 | 全部删除 | 不再用 PubSub 关闭已打开的管理页面；页面在挂载、每次事件与每次跳转时重新校验 `admin?/1`。**代价**：登出后已打开的 `/admin`、`/oban` 页面不会被立即关闭（下次事件仍能通过校验，因为管理员记录本身未变），需要刷新或关闭标签页 |
| `Eim.Accounts.Admins.admin_status/1` | 合并进 `admin?/1` | 后者返回布尔且不抛异常，policy check 直接用 |
| `Admins.find_by_email/2`、`/manage/users` 页面与 `EimWeb.AdminUsersLive` | 全部删除 | 管理员管理统一走 Ash Admin 的 `/admin`（`Eim.Admins.Admin` 资源：列表 + `:grant` 表单）；`Eim.Accounts.User` 的 `:get_by_email_as_admin` action 与 policy、`LiveUserAuth.live_admin_required` 随之移除 |
| `Eim.Admins.grant_admin/2` 的 Web 调用方 | 不再存在 | 仍保留为 facade API，供运维脚本与测试使用；界面路径是 Ash Admin 的 `:grant` |

### 6.2 新增的运维入口

```elixir
# 受控 IEx（发布环境）
Eim.Ops.bootstrap_admin_user("admin@eim.s")

# 或直接
Eim.Admins.master_email()   # => "admin@eim.s"（来自 config）
Eim.Admins.master()         # => 该邮箱对应的管理员 User，或 nil
```

`config :eim, :master_email`：`config/dev.exs` 与 `config/test.exs` 设为 `"admin@l.h"`（测试里 `dev.seed` 依赖它），`config/runtime.exs` 生产读 `MASTER_EMAIL`（缺失时 raise，见 D4）。

---

## 7. 迁移方案

`mix ash.codegen add_admins` 生成后手工补回填：

1. `create table(:admins, primary_key: false)`、`unique_index(:admins, [:user_id])`；`user_id` → `references(:users, type: :uuid, on_delete: :delete_all)`，`granted_by_user_id` → `on_delete: :nilify_all`。
2. 回填（兼容已部署库）：
   ```sql
   INSERT INTO admins (id, user_id, granted_at, inserted_at, updated_at)
   SELECT gen_random_uuid(), id, now(), now(), now()
   FROM users WHERE role = 'admin';
   ```
   历史授权时间不可知，`granted_at` 取迁移时刻并在文档注明；`granted_by_user_id` 为 `NULL`（与 bootstrap 的 `actor_id = NULL` 一致）。
3. `drop constraint(:users, :users_role_valid)` + `remove :role`。
4. `down/0`：重建 `role` 列与约束 → `UPDATE users SET role = 'admin' WHERE id IN (SELECT user_id FROM admins)` → `drop table(:admins)`。`down` 无法恢复已撤销的历史（本方案下没有撤销，影响面仅限未来）。

配套：`config/config.exs` 的 `ash_domains` 增加 `Eim.Admins.Domain`；`priv/resource_snapshots` 由 `ash.codegen` 生成 `admins/*.json` 与新的 `users/*.json`；[test/eim/audit_migration_test.exs](../test/eim/audit_migration_test.exs) 引用的是已应用的旧迁移，保持不动，另写 admins 迁移测试。

---

## 8. 代码改动清单

**新增**

- `lib/eim/admins.ex`、`lib/eim/admins/domain.ex`、`lib/eim/admins/admin.ex`
- `lib/eim/admins/checks/admin_check.ex`（由 `lib/eim/accounts/checks/admin_check.ex` 迁移）
- `lib/eim/admins/changes/set_granted_by.ex`、`lib/eim/admins/changes/record_admin_event.ex`
- `lib/eim/ops.ex`
- `priv/repo/migrations/<ts>_add_admins.exs`、`priv/resource_snapshots/repo/admins/<ts>.json`
- `test/eim/admins_test.exs`（替代 `test/eim/accounts/admin_roles_test.exs`，对齐 authx 的测试命名）、`test/eim/admins_migration_test.exs`

**修改**

- `lib/eim/accounts.ex`：+`fetch_user_by_ref/2`
- `lib/eim/accounts/user.ex`：删 `role` 属性、`:set_admin_role`/`:bootstrap_admin`、`:get_by_email_as_admin` 三个 action 与对应 policy；`admin do table_columns [:email] end`
- `lib/eim_web/plugs/require_admin.ex`、`lib/eim_web/live_user_auth.ex`、`lib/eim_web/components/layouts.ex`、`lib/eim_web/oban_resolver.ex`：仅改模块名 `Eim.Accounts.Admins` → `Eim.Admins`
- `lib/eim_web/admin_auth.ex`：改模块名；删除 `access_topic` 订阅与 `handle_info` 钩子，只保留 `handle_event` / `handle_params` 的 `admin?/1` 复核
- `lib/eim_web/controllers/auth_controller.ex`：删除登出时的 PubSub 广播
- `lib/mix/tasks/dev.seed.ex`：`@admin_email` → `Admins.master_email()`，删除「找现有管理员」分支，改为 `Ops.bootstrap_admin_user(Admins.master_email())`
- `lib/eim_web/router.ex`：删除 `/manage/users` 的 `ash_authentication_live_session :admin_user_routes` 整块
- `config/dev.exs`、`config/test.exs`：`master_email: "admin@l.h"`；`config/runtime.exs`：prod `MASTER_EMAIL`
- `config/config.exs`：`ash_domains` 增加 `Eim.Admins.Domain`

**删除**

- `lib/eim/accounts/admins.ex`、`lib/eim/accounts/changes/change_admin_role.ex`、`lib/eim/accounts/checks/admin_check.ex`
- `lib/eim_web/live/admin_users_live.ex`（管理员管理改由 Ash Admin 的 `/admin` 承担）
- `test/eim/accounts/admin_roles_concurrency_test.exs`（并发互撤场景已不存在）
- `test/eim/accounts/admin_roles_test.exs`（内容并入 `test/eim/admins_test.exs`）
- `test/eim_web/admin_users_live_test.exs`（页面已删除）

---

## 9. 测试计划

| 文件 | 内容 |
| --- | --- |
| `test/eim/admins_test.exs` | ① bootstrap 授予并写一条 `admin.granted`（`actor_id` 为 nil、`method: "bootstrap"`）；② 重复 bootstrap 幂等、不写第二条；③ 非管理员 `grant_admin` → `:forbidden`；④ 非管理员直接 `Ash.create(Admin, :grant, actor: 自己)` → `%Ash.Error.Forbidden{}`；⑤ 无 actor 的 `Ash.create(..., authorize?: true)` → Forbidden；⑥ OIDC 注册（含 `role: "admin"`）后 `admin?` 为 false；⑦ 审计写入失败 → 授予回滚（`CHECK (event_type <> 'admin.granted') NOT VALID`）；⑧ `admin?(nil / "not-a-uuid" / 不存在的 id)` → `false`；⑨ `master_email/0`、`master/0`；⑩ `list/1` |
| `test/eim/admins_migration_test.exs` | 新库建表；有 `role = 'admin'` 的数据回填为 `admins` 行；`down` 恢复 `role` 并删表 |
| `test/eim_web/admin_dashboard_test.exs` | 保留路由与导航拦截；**删除**「revocation closes…」与「signing out closes…」两个用例（对应的 PubSub 频道已移除） |
| `test/eim_web/audit_admin_test.exs` | 只保留 `admin.granted`（去掉 `set_role(..., :user)` 与 `admin.revoked` 断言） |
| `test/mix/tasks/dev_seed_test.exs` | 改为「重复执行幂等、审计计数为 1」；删除「已有其他管理员时走 set_role」用例 |
| `test/eim/audit_migration_test.exs` | 不动 |

断言优先用 `Admins.admin?/1` 与 `Admins.fetch_admin_by_user_ref/2`，避免把 `%Admin{}` 结构写死。

---

## 10. 文档更新

- [docs/ops.md](../docs/ops.md)：`Eim.Accounts.Admins.bootstrap("admin@eim.s")` → `Eim.Ops.bootstrap_admin_user("admin@eim.s")`；补一句 `master_email` 配置与「bootstrap 幂等、仅可信 IEx」。
- [docs/admin-audit.md](../docs/admin-audit.md)：范围改为「当前只记录 `admin.granted`」，`admin.revoked` 标注为撤销功能回归时启用；`users.role` 相关表述改为 `admins` 表 + `audit_events` 的分工（当前状态 / 历史）；迁移章节补充 admins 迁移与 `down` 说明。

---

## 11. 验收标准

1. `mix precommit`（`compile --warnings-as-errors`、`deps.unlock --unused`、`format`、`test`）全绿。
2. 第 2 节 5 条行为逐条有测试覆盖。
3. 全仓库不再出现 `users.role`、`:set_admin_role`、`Admins.set_role`、`Admins.bootstrap(`、`Eim.Accounts.Admins`、`access_topic`、`/manage/users`、`AdminUsersLive`、`:get_by_email_as_admin` 的引用。
4. `Eim.Admins.Admin` 只有 `:read` / `:grant` 两个 action；AshAdmin 中无删除、无编辑入口。
5. 新库迁移与已部署库回填两条路径都验证过（含 `down`）。

---

## 12. 待确认的决策点

| # | 决策 | 结论 |
| --- | --- | --- |
| D1 | `bootstrap_admin/1` 改为幂等（去掉 `:already_bootstrapped`） | 已确认：幂等（authx 语义） |
| D2 | 撤销相关代码（`access_topic`、`AdminAuth` 订阅、撤权测试）直接删除，还是留作未来撤销的接口 | 已确认：**全部删除**，包括 `access_topic/1`、订阅、登出广播与「登出关闭 dashboard」测试 |
| D3 | `dev.seed` 改用 `Admins.master_email()`（并在 dev/test 配置 `master_email`） | 已确认：采用 |
| D4 | 生产 `MASTER_EMAIL` 未配置时 raise 还是用默认值 | 已确认：raise |
| D5 | `Eim.Ops` 是否现在就建 | 已确认：建 |

---

## 13. 建议实施顺序（3 次提交）

1. **迁移与资源**：`admins` 表迁移（含回填）+ `Eim.Admins.Admin`/`Domain`/`Checks`/`Changes` + `config` 注册 + `Eim.Accounts.fetch_user_by_ref/2`。
2. **facade 切换**：新增 `Eim.Admins` 与 `Eim.Ops`，更新 6 个调用点与 `dev.seed`，删除 `Eim.Accounts.Admins`、`change_admin_role.ex`、`Eim.Accounts.Checks.AdminCheck`、`users.role` 相关代码；同步改/删测试。
3. **清理与文档**：`ash.codegen` 收尾快照、AshAdmin 展示配置、`docs/ops.md` 与 `docs/admin-audit.md`、`mix precommit`。

## 14. 实施状态与待执行命令

代码已全部写入工作区。**本次改动的代码尚未编译或运行过**：会话中 Bash、子 agent、WebFetch 均被权限模式拦截，因此无法执行 `mix`。

仍需在有 `mix` 的环境执行：

1. `mix ash.codegen add_admins` —— 生成 `admins` 的资源快照与新的 `users` 快照。若它同时生成了一个只做「建表 + 删列」的迁移，请丢弃该文件，保留手写的 `priv/repo/migrations/20261124120000_add_admins.exs`（它额外包含回填和可逆的 `down`）。
2. 删除被取代的文件（当前内容已替换为说明性注释，避免编译到已删除的 API）：
   - `rm lib/eim/accounts/admins.ex`
   - `rm lib/eim/accounts/changes/change_admin_role.ex`
   - `rm lib/eim/accounts/checks/admin_check.ex`
   - `rm lib/eim_web/live/admin_users_live.ex`
   - `rm test/eim/accounts/admin_roles_test.exs`
   - `rm test/eim/accounts/admin_roles_concurrency_test.exs`
   - `rm test/eim_web/admin_users_live_test.exs`
3. `mix ecto.reset`（或 `mix ecto.migrate`）验证建表、回填与 `down`。
4. `mix precommit`。

需要复核的一点：`priv/repo/migrations/20261124120000_add_admins.exs` 的回填 SQL 需要给表名加迁移 prefix。`Ecto.Migration.prefix/0` 在没有 prefix 时的返回值无法在本地查证（`deps/` 未安装），因此做了 `nil` / `""` / 异常三重兜底；`test/eim/admins_migration_test.exs` 另外设置了 `search_path` 以降低不确定性。
