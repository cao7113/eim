defmodule EimWeb.AdminDashboardTest do
  use EimWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Eim.Accounts.{Admins, User}

  setup do
    conf = %{Oban.config() | testing: :disabled}
    start_supervised!({Oban.Sonar, conf: conf, name: Oban.Registry.via(Oban, Oban.Sonar)})
    start_supervised!({Oban.Met, conf: Oban.config()})
    :ok
  end

  test "dashboard routes and navigation require a current administrator", %{conn: conn} do
    admin = create_user("dashboard-admin@example.com")
    member = create_user("dashboard-member@example.com")
    assert {:ok, _} = Admins.bootstrap(to_string(admin.email))

    for path <- ["/admin", "/oban"] do
      assert redirected_to(get(conn, path)) == "/"
      assert redirected_to(get(signed_in_conn(member), path)) == "/"
      assert {:ok, _view, _html} = live(signed_in_conn(admin), path)
    end

    guest_html = html_response(get(conn, "/"), 200)
    member_html = html_response(get(signed_in_conn(member), "/"), 200)
    refute guest_html =~ ~s(id="admin-tools")
    refute member_html =~ ~s(id="admin-tools")

    assert [] =
             guest_html
             |> LazyHTML.from_document()
             |> LazyHTML.query("#current-user-admin")
             |> LazyHTML.attribute("id")

    assert [] =
             member_html
             |> LazyHTML.from_document()
             |> LazyHTML.query("#current-user-admin")
             |> LazyHTML.attribute("id")

    html = html_response(get(signed_in_conn(admin), "/"), 200)
    assert html =~ ~s(id="admin-tools")

    assert "(admin)" =
             html
             |> LazyHTML.from_document()
             |> LazyHTML.query("#current-user-email + #current-user-admin")
             |> LazyHTML.text()
             |> String.trim()

    assert ["false"] =
             html
             |> LazyHTML.from_document()
             |> LazyHTML.query(
               "#admin-tools.nav-tools > button#admin-tools-toggle[aria-controls=admin-tools-menu]"
             )
             |> LazyHTML.attribute("aria-expanded")

    assert [_] =
             html
             |> LazyHTML.from_document()
             |> LazyHTML.query("#admin-tools .nav-tools-menu#admin-tools-menu")
             |> LazyHTML.attribute("id")

    assert html =~ ~s(id="admin-dashboard-link")
    assert html =~ ~s(id="oban-dashboard-link")
  end

  test "revocation closes connected administrator dashboards" do
    admin = create_user("dashboard-revoker@example.com")
    target = create_user("dashboard-revoked@example.com")
    assert {:ok, _} = Admins.bootstrap(to_string(admin.email))
    assert {:ok, _} = Admins.set_role(admin.id, target.id, :admin)
    {:ok, ash_view, _} = live(signed_in_conn(target), "/admin")
    {:ok, oban_view, _} = live(signed_in_conn(target), "/oban")

    assert {:ok, _} = Admins.set_role(admin.id, target.id, :user)
    assert_redirect(ash_view, "/")
    assert_redirect(oban_view, "/")
    assert redirected_to(get(signed_in_conn(target), "/admin")) == "/"
    assert redirected_to(get(signed_in_conn(target), "/oban")) == "/"
    html = html_response(get(signed_in_conn(target), "/"), 200)
    refute html =~ ~s(id="admin-tools")

    assert [] =
             html
             |> LazyHTML.from_document()
             |> LazyHTML.query("#current-user-admin")
             |> LazyHTML.attribute("id")
  end

  test "signing out closes open management dashboards" do
    admin = create_user("dashboard-signout@example.com")
    assert {:ok, _} = Admins.bootstrap(to_string(admin.email))
    conn = signed_in_conn(admin)
    {:ok, ash_view, _} = live(conn, "/admin")
    {:ok, oban_view, _} = live(conn, "/oban")

    assert redirected_to(delete(conn, "/sign-out")) == "/"
    assert_redirect(ash_view, "/")
    assert_redirect(oban_view, "/")
  end

  defp create_user(email) do
    {:ok, password} = AshAuthentication.BcryptProvider.hash("password123456")

    Ash.Seed.seed!(User, %{
      email: email,
      hashed_password: password,
      confirmed_at: DateTime.utc_now()
    })
  end

  defp signed_in_conn(user) do
    strategy = AshAuthentication.Info.strategy!(User, :password)

    {:ok, authenticated} =
      AshAuthentication.Strategy.action(strategy, :sign_in, %{
        email: user.email,
        password: "password123456"
      })

    build_conn()
    |> init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(authenticated)
  end
end
