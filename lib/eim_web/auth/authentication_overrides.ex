defmodule EimWeb.Auth.AuthenticationOverrides do
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.{Components, SignInLive}

  override SignInLive do
    set :root_class, "flex min-h-[65vh] items-center justify-center py-12"
  end

  override Components.SignIn do
    set :root_class,
        "w-full max-w-md rounded-3xl border border-slate-200 bg-white p-6 shadow-xl shadow-slate-950/5 sm:p-8"

    set :strategy_class, "w-full"
  end

  override Components.Banner do
    set :image_url, nil
    set :dark_image_url, nil
    set :text, "Make every word count."
    set :text_class, "text-center text-2xl font-semibold tracking-tight text-lime-800"
  end

  override Components.OAuth2 do
    set :root_class, "w-full"

    set :link_class,
        "mt-4 inline-flex w-full items-center justify-center gap-2 rounded-xl bg-lime-300 px-4 py-3 text-sm font-semibold text-slate-950 shadow-lg shadow-lime-300/40 transition hover:-translate-y-0.5 hover:bg-lime-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lime-700"

    # The built-in OIDC icon has a malformed viewBox and renders as a clipped
    # glyph; the text-only button is cleaner and on-brand.
    set :icon_class, "hidden"
  end

  override Components.Password.Input do
    set :field_class, "mt-4"
    set :label_class, "mb-1 block text-sm font-medium text-slate-700"

    set :input_class,
        "block w-full rounded-lg border border-slate-300 bg-white px-3 py-2 text-sm text-slate-950 shadow-sm placeholder:text-slate-400 focus:border-lime-500 focus:outline-none focus:ring-4 focus:ring-lime-100"

    set :input_class_with_error,
        "block w-full rounded-lg border border-red-300 bg-white px-3 py-2 text-sm text-slate-950 shadow-sm focus:border-red-400 focus:outline-none focus:ring-4 focus:ring-red-100"

    set :submit_class,
        "mt-4 inline-flex w-full justify-center rounded-lg bg-slate-950 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-lime-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lime-700"

    set :checkbox_class, "mr-2 accent-lime-700"
    set :checkbox_label_class, "text-sm font-medium text-slate-700"
  end
end
