defmodule EimWeb.AuditAdminTest do
  use EimWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Eim.Admins
  alias Eim.Audit.Event

  test "audit events are available in Ash Admin for reading, not creating", %{conn: conn} do
    user = Eim.AccountsFixtures.user_fixture("audit-admin@example.com")
    target = Eim.AccountsFixtures.user_fixture("audit-target@example.com")

    assert {:ok, _} = Admins.bootstrap_admin(user)
    assert {:ok, _} = Admins.grant_admin(target, user)
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
    |> form("#cinder-collection-filter-form", filters: %{event_type: "admin.granted"})
    |> render_change()

    assert has_element?(view, "main", "admin.granted")

    view
    |> form("#cinder-collection-filter-form", filters: %{event_type: "", subject_id: target.id})
    |> render_change()

    assert has_element?(view, "main tbody", "admin.granted")
    refute has_element?(view, "main tbody tr", "bootstrap")
  end
end
