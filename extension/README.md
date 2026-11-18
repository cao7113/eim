# Eim 浏览器扩展

## 开发和环境

在此目录执行 `bun run dev`，在插件弹窗的「服务环境」中切换：

- 本地开发：`http://localhost:4003`（默认；Authx `http://localhost:4000`）
- 本地生产：`https://eim.s`（Authx `https://authx.s`）
- 正式环境：`https://eim.fly.dev`（Authx 未配置）

选择保存在浏览器本地，无需重新构建；本地生产环境需要浏览器信任其 HTTPS
证书。每个环境的网页登录和插件凭据相互独立，首次连接时需分别授权，切回时
会使用该环境已有的凭据。切换环境会关闭划词浮层；若有未提交的笔记，浮层会
保留笔记供复制。

插件登录直接使用 Authx OIDC（Authorization Code + S256 PKCE）；插件不保存
密码或 client secret。`code`、`state`、`nonce`、`code_verifier` 由 Eim 后端
兑换并校验 ID Token。

## 本地生产（unpacked 导入）

先按 Eim 文档登记 Authx 本地生产客户端，再构建：

```sh
WXT_UNPACKED=1 \
WXT_LOCAL_PRODUCTION_OIDC_CLIENT_ID=<extension client id> \
bun run build
```

在 `chrome://extensions` 开启开发者模式，选择“加载已解压的扩展程序”，指向
`.output/chrome-mv3`。`WXT_UNPACKED=1` 会带上固定 manifest `key`，保证扩展 ID
与 Authx 登记的回调一致。

正式商店构建不要带 `WXT_UNPACKED=1`。

## 检查

执行 `bun run check`、`bun test` 和 `bun run build`。发布前还需按照
[扩展发布检查清单](../docs/extension/发布准备与检查清单.md) 进行真实浏览器和
服务端验收。
