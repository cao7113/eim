defmodule EimWeb.AuditAdminTest do
  use EimWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Eim.Accounts.{Admins, User}
  alias Eim.Audit.Event

  test "the standalone audit route is not registered" do
    assert :error = Phoenix.Router.route_info(EimWeb.Router, "GET", "/manage/audit", "localhost")
  end

  test "audit events are available in Ash Admin for reading, not creating", %{conn: conn} do
    user =
      Ash.Seed.seed!(User, %{
        email: "audit-admin@example.com",
        hashed_password: "test",
        confirmed_at: DateTime.utc_now()
      })

    target =
      Ash.Seed.seed!(User, %{
        email: "audit-target@example.com",
        hashed_password: "test",
        confirmed_at: DateTime.utc_now()
      })

    assert {:ok, _} = Admins.bootstrap(to_string(user.email))
    assert {:ok, _} = Admins.set_role(user.id, target.id, :admin)
    assert {:ok, _} = Admins.set_role(user.id, target.id, :user)
    assert Eim.Audit in Application.fetch_env!(:eim, :ash_domains)
    assert AshAdmin.Domain.show?(Eim.Audit)
    assert Event in AshAdmin.Domain.show_resources(Eim.Audit)
    assert AshAdmin.Resource.read_actions(Event) == [:read]
    assert AshAdmin.Resource.create_actions(Event) == []
    assert AshAdmin.Resource.update_actions(Event) == []
    assert AshAdmin.Resource.destroy_actions(Event) == []

    conn =
      conn
      |> init_test_session(%{})
      |> fetch_cookies()
      |> put_private(:phoenix_endpoint, EimWeb.Endpoint)
      |> Phoenix.ConnTest.dispatch(
        EimWeb.AshAdminTestRouter,
        :get,
        "/admin?domain=Audit&resource=Event&action_type=read"
      )

    assert {:ok, view, _} = live(conn)
    assert has_element?(view, "main", "admin.granted")
    assert has_element?(view, "main", user.id)
    assert has_element?(view, "main", "Filters")
    view |> element("button", "Filters") |> render_click()

    view
    |> form("#cinder-collection-filter-form", filters: %{event_type: "admin.revoked"})
    |> render_change()

    assert has_element?(view, "main", "admin.revoked")
    refute has_element?(view, "main tbody", "admin.granted")

    view
    |> form("#cinder-collection-filter-form", filters: %{event_type: "", subject_id: target.id})
    |> render_change()

    assert has_element?(view, "main tbody", "admin.revoked")
    refute has_element?(view, "main tbody tr", "bootstrap")
  end
end
