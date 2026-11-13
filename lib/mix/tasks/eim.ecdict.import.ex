defmodule Mix.Tasks.Eim.Ecdict.Import do
  use Mix.Task

  alias Eim.Dict.Importer

  @shortdoc "Imports an ECDICT CSV into the dictionary database"

  @impl Mix.Task
  def run(args) do
    {_, sources, invalid} = OptionParser.parse(args, strict: [])

    path =
      case {sources, invalid} do
        {[path], []} -> path
        _ -> Mix.raise("usage: mix eim.ecdict.import CSV_PATH")
      end

    Mix.Task.run("app.start")
    counts = Importer.run(path)

    Mix.shell().info("Imported #{counts.row_count} ECDICT rows (#{counts.skipped_rows} skipped)")
  end
end
