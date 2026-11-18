defmodule EimWeb.AuthController do
  use EimWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, "You are now signed in")
    |> redirect(to: return_to)
  end

  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "We could not sign you in with Authx. Please try again.")
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    if user = conn.assigns[:current_user] do
      :ok =
        Phoenix.PubSub.broadcast(
          Eim.PubSub,
          Eim.Accounts.Admins.access_topic(user.id),
          :admin_access_revoked
        )
    end

    conn
    |> clear_session(:eim)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end
end
