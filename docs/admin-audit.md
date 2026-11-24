# 管理事件留痕

> 状态：已实现管理员授权事件和管理查询；撤销事件待撤销功能实现后启用。

## 目标与范围

为管理员授权等重要操作留下可查询的记录。事件集中存储，管理员可以统一查询，也可以在具体业务场景中按类型和目标筛选。

这是一份轻量的业务事件记录，而非通用版本管理、事件溯源或合规审计系统。当前只覆盖管理员授权的实际变更（`admin.granted`）；撤销管理员尚未实现，`admin.revoked` 在实现后启用。登录失败、被拒绝的操作、词典导入及其他管理操作不在本次实现范围内，后续按需求显式接入。

## 方案选择

使用一个普通的 Ash Resource 表示管理事件，调用方显式记录必要信息：

- `AshEvents` 支持集中事件表，但偏向自动记录 action 输入和执行时的属性；还需处理敏感数据与额外的事件追踪机制，对当前需求偏重。
- `AshPaperTrail` 更适合 Resource 版本和字段变更历史，通常为不同 Resource 创建各自的版本表；并非当前集中记录特定业务事件的首选。
- 通用 Ash Resource 已能提供本次需要的持久化、授权与查询能力，事件内容和接入范围由应用控制。

参考：[AshEvents](https://github.com/ash-project/ash_events/tree/v0.8.2)、[AshPaperTrail](https://github.com/ash-project/ash_paper_trail)。

## 事件模型

`Eim.Audit` domain 中的 `Eim.Audit.Event` Resource 以 `audit_events` 为存储表。每条记录表示一次已成功的业务事件：

| 字段 | 用途 |
| --- | --- |
| `id` | 事件 UUID |
| `event_type` | 稳定的事件类型；当前只有 `admin.granted`（`admin.revoked` 待撤销功能实现） |
| `actor_id` | 操作者用户 UUID；bootstrap 时为空 |
| `subject_type` | 目标类型，首批为 `user` |
| `subject_id` | 目标 UUID，首批为用户 ID |
| `details` | 事件详情 map；授权事件包含 `old_role`、`new_role`、`method` |
| `inserted_at` | 事件记录时间 |

`method` 为 `bootstrap` 或 `admin`，由是否存在 actor 推导。bootstrap 是一次 `admin.granted`，不应将空 `actor_id` 描述为已知的运维操作者；应继续依赖受控 IEx 的访问记录。撤销功能实现前，`old_role` 恒为 `user`、`new_role` 恒为 `admin`，保留这两个字段是为了格式稳定。详情采用各事件类型明确的字段白名单，不写入密码、token 或完整用户数据。

首批目标均为 UUID；未来如有非 UUID 目标，应单独设计扩展，不预先引入泛化机制。统一查询需要按时间、事件类型及目标筛选；针对时间排序、类型和目标查询建立适当索引。

## 写入与权限

- 在授予管理员（`Eim.Admins.Admin` 的 `:grant` action）的同一事务中写入事件；写入失败时授权也必须回滚，不能静默降级。
- 授权未实际发生时（例如重复 bootstrap 已是管理员的用户）不写事件；失败、拒绝及被回滚的操作不产生成功事件。
- 管理员记录只提供 `:read` 和 `:grant` 两个 action，不提供 update 或 destroy，因此没有绕过事件写入的第二条写入路径。审计事件只提供受控的创建 action 和管理员读取 action；业务代码内部以明确的可信边界创建事件，不能允许用户伪造事件。
- 显式启用 Ash 授权的应用查询根据数据库中当前的 `admins` 记录授权，包括持有旧 actor 的情况。非管理员和未登录用户不可读取。
- 这是应用层追加与只读约束：直接数据库操作和可信代码中的授权绕过仍可修改或绕过记录，不宣称防篡改。保留 [生产部署文档](./prod.md) 中对远程 IEx 的限制。

## 查询体验

事件统一通过 Ash Admin 的 `/admin` 中 `Audit` → `Event` 查询，可按事件类型、操作者、目标类型和目标 ID 筛选，并查看事件详情；不再提供独立的审计页面或用户页入口。其他业务场景如需定制查询，可使用同一 Resource 并显式启用授权。

`/admin` 与 `/oban` 在生产环境仅对当前管理员开放：`on_mount` 与每次事件、每次页面跳转都会重新查询数据库中的 `admins` 记录。管理员是可信运维人员：Ash Admin 允许绕过授权和切换 actor，也可进行不经过授权 action 的操作，因此不保证所有管理操作都被记录或受业务规则约束。应限制管理员数量，保护账号和传输，并监控管理访问。

## 迁移

管理员记录放在独立的 `admins` 表（`Eim.Admins.Admin`），`users` 表不再有角色字段。`add_admins` 迁移创建该表、把原先 `role = 'admin'` 的用户回填为管理员记录（`granted_at` 取迁移时刻、`granted_by_user_id` 留空），然后删除 `users.role` 及其约束。

回滚会把仍存在的管理员记录写回 `role = 'admin'` 并删除 `admins` 表。由于撤销功能尚未实现，这个回滚不会丢失任何历史；将来实现撤销后，`down` 无法恢复已经被撤销的授权，回滚前应备份并确认数据恢复方案。

标准迁移回滚会删除事件表，从而丢失所有事件；回滚前应备份。

Ash Resource 注册、数据库快照、管理员相关测试和 [生产部署文档](./prod.md) 与此方案同步。

## 验收

1. bootstrap 与管理员授权各生成一条内容正确的事件；对已是管理员的用户再次 bootstrap 不生成事件。
2. 事件写入失败时授权回滚；非管理员、未登录者和 OIDC 注册路径都无法获得管理员。
3. Ash Admin 中可统一查看和筛选事件；显式授权的 Resource 查询拒绝非管理员、未登录者和持有旧 actor 的调用。
4. 新数据库迁移直接创建管理员和事件表并回填既有管理员；事件表不包含密码、token 或完整用户记录。
5. 普通调用无法创建、修改或删除事件；Ash Admin 的事件 Resource 不展示创建、修改或删除操作。
6. 按项目规范执行相关测试及 `mix precommit`，并记录任何与本次变更无关的既有阻塞。
