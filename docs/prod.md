# Deploy to prod (local)

Generate a separate token signing secret with `mix eim.gen.signing.secret` and
provide it as `TOKEN_SIGNING_SECRET` through your deployment's secret management.
Do not commit it or put it in a shared configuration file. Keep it stable across
restarts: changing it invalidates existing signed tokens.

```
mix release.init
mix phx.gen.release --docker

# deploy to local-pro at https://eim.s
lp gen > _local/app.yaml
gate c add _local/app.yaml

# import ecdict
lp xbin import-ecdict _local/ecdict/ecdict.csv
# 真实生产，需要上传文件，并 import 导入
```

Current Mix-based ECDICT import is not a production release task and does not
provide an atomic dictionary update. See the [ECDICT import design](./ECDICT词典.md#统一导入与持续更新设计待实现)
for the proposed production initialization and update workflow; it is not yet
implemented.

## Administrator bootstrap

After running database migrations, register the first user normally, then open a
trusted remote IEx session on a running release and run:

```elixir
Eim.Accounts.Admins.bootstrap("admin@eim.s")
```
