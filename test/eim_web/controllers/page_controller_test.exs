defmodule EimWeb.PageControllerTest do
  use EimWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)

    assert response =~ "Make every word"
    assert response =~ "YOUR WORDS, WORKING FOR YOU"
    assert response =~ "how-it-works"
    refute response =~ "Phoenix Framework"
    refute response =~ ~s(id="dev-tools")
  end

  test "GET / displays the signed-in user's email", %{conn: conn} do
    password = "password123456"
    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash(password)

    Ash.Seed.seed!(Eim.Accounts.User, %{
      email: "reader@example.com",
      hashed_password: hashed_password,
      confirmed_at: DateTime.utc_now()
    })

    strategy = AshAuthentication.Info.strategy!(Eim.Accounts.User, :password)

    {:ok, user} =
      AshAuthentication.Strategy.action(strategy, :sign_in, %{
        email: "reader@example.com",
        password: password
      })

    conn =
      conn
      |> init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)
      |> get(~p"/")

    response = html_response(conn, 200)

    assert response =~ ~s(id="current-user-email")
    assert response =~ "reader@example.com"
    assert response =~ ~s(id="sign-out-link")
    assert response =~ ~s(id="vocabulary-link")
    assert response =~ ~s(href="/learn/vocab")
    assert response =~ "Open Vocabulary"
    refute response =~ ~s(href="/sign-in")
  end
end
