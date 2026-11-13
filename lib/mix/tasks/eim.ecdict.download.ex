defmodule Mix.Tasks.Eim.Ecdict.Download do
  use Mix.Task

  alias Eim.Dict.Downloader

  @shortdoc "Downloads an ECDICT CSV to a temporary file"

  @impl Mix.Task
  def run(args) do
    url =
      case args do
        [] -> Downloader.default_url()
        ["--mini"] -> Downloader.mini_url()
        ["--" <> _] -> Mix.raise("usage: mix eim.ecdict.download [--mini | URL]")
        [url] -> url
        _ -> Mix.raise("usage: mix eim.ecdict.download [--mini | URL]")
      end

    Mix.Task.run("app.start")
    Mix.shell().info(Downloader.download(url))
  end
end
