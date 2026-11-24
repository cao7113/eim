defmodule EimWeb.AdminDashboardTest do
  use EimWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Eim.Admins

  setup do
    conf = %{Oban.config() | testing: :disabled}
    start_supervised!({Oban.Sonar, conf: conf, name: Oban.Registry.via(Oban, Oban.Sonar)})
    start_supervised!({Oban.Met, conf: Oban.config()})
    :ok
  end

  test "administrator access is managed through Ash Admin, not a dedicated page" do
    assert :error =
             Phoenix.Router.route_info(EimWeb.Router, "GET", "/manage/users", "localhost")
  end

  test "dashboard routes and navigation require a current administrator", %{conn: conn} do
    admin = create_user("dashboard-admin@example.com")
    member = create_user("dashboard-member@example.com")
    assert {:ok, _} = Admins.bootstrap_admin(admin)

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

  defp create_user(email), do: Eim.AccountsFixtures.user_fixture(email)

  defp signed_in_conn(user), do: Eim.AccountsFixtures.signed_in_conn(user)
end
