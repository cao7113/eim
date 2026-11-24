# Ops

## Deploy to prod (local)

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

# import ecdict(真实生产，需要上传文件，并 import 导入)
lp xbin import-ecdict _local/ecdict/ecdict.csv
```

Current Mix-based ECDICT import is not a production release task and does not
provide an atomic dictionary update. See the [ECDICT import design](./ECDICT词典.md#统一导入与持续更新设计待实现)
for the proposed production initialization and update workflow; it is not yet
implemented.

## Administrator bootstrap

Administrator access is stored per user in the `admins` table
(`Eim.Admins.Admin`). There is no way to withdraw it yet.

After running database migrations, register the first user normally, then open a
trusted remote IEx session on a running release and run:

```elixir
Eim.Ops.bootstrap_admin_user("admin@eim.s")
```

The email is the account to promote; it must already exist locally. Production
must set `MASTER_EMAIL` to the same address, which `Eim.Admins.master_email/0`
and `Eim.Admins.master/0` report.

`Eim.Ops` is the only supported operational entry point, and grants
administrator access without an actor: it bypasses Ash policies, so the only
protection is the trust placed in shell access. Never call it from the web
application, and keep remote IEx access restricted.

Granting is idempotent — booting an account that is already an administrator
returns the existing record and writes no further audit event. Every other grant
goes through `Eim.Admins.grant_admin/2`, which requires a current administrator
as the actor. `mix dev.seed` performs the same bootstrap for `admin@l.h` using
`:master_email`.
