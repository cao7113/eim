defmodule Eim.Dict.Lexeme do
  use Ash.Resource,
    otp_app: :eim,
    domain: Eim.Dict,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "lexemes"
    repo Eim.Repo

    custom_indexes do
      index [:word_lc]
      index [:sw]
    end
  end

  json_api do
    type "lexeme"
  end

  actions do
    defaults [:read]

    action :lookup, :map do
      description "Look up a word or phrase in the ECDICT dictionary."

      argument :text, :string do
        allow_nil? false
        constraints max_length: 500
        description "The word or phrase to look up."
      end

      constraints fields: [
                    text: [type: :string, allow_nil?: false],
                    kind: [type: :string, allow_nil?: false],
                    match: [type: :string, allow_nil?: false],
                    lemma: [type: :string],
                    phonetic: [type: :string],
                    collins: [type: :integer],
                    frq_rank: [type: :integer],
                    senses: [
                      type: {:array, :map},
                      constraints: [
                        items: [
                          fields: [
                            pos: [type: :string],
                            domain: [type: :string],
                            zh: [type: :string, allow_nil?: false]
                          ]
                        ]
                      ]
                    ],
                    tags: [type: {:array, :string}],
                    in_context: [type: :string],
                    sources: [
                      type: {:array, :map},
                      constraints: [
                        items: [
                          fields: [
                            name: [type: :string, allow_nil?: false],
                            version: [type: :string]
                          ]
                        ]
                      ]
                    ]
                  ]

      run fn input, _context ->
        case Eim.Dict.Lookup.run(input.arguments.text) do
          {:ok, entry} ->
            {:ok, entry_to_map(entry)}

          {:miss, normalized} ->
            {:ok, empty_result(normalized.text, Atom.to_string(normalized.kind), "miss")}

          {:error, reason} ->
            {:error,
             Ash.Error.Query.InvalidArgument.exception(
               field: :text,
               message: "is invalid: #{reason}"
             )}
        end
      end
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :word, :string, allow_nil?: false, public?: true
    attribute :word_lc, :string, allow_nil?: false
    attribute :sw, :string, allow_nil?: false
    attribute :phonetic, :string, public?: true
    attribute :translation, :string, public?: true
    attribute :definition, :string, public?: true
    attribute :pos, :string, public?: true
    attribute :tags, {:array, :string}, default: [], public?: true
    attribute :collins, :integer, public?: true
    attribute :oxford, :boolean, default: false, public?: true
    attribute :bnc_rank, :integer, public?: true
    attribute :frq_rank, :integer, public?: true
    attribute :exchange, :string
    attribute :lemma, :string, public?: true
    attribute :source, :string, default: "ecdict", allow_nil?: false
    attribute :source_version, :string
    timestamps()
  end

  relationships do
    has_many :forms, Eim.Dict.LexemeForm
  end

  identities do
    identity :unique_word, [:word]
  end

  defp entry_to_map(entry) do
    %{
      text: entry.text,
      kind: Atom.to_string(entry.kind),
      match: Atom.to_string(entry.match),
      lemma: entry.lemma,
      phonetic: entry.phonetic,
      collins: entry.collins,
      frq_rank: entry.frq_rank,
      senses: entry.senses,
      tags: entry.tags,
      in_context: entry.in_context,
      sources: entry.sources
    }
  end

  defp empty_result(text, kind, match) do
    %{
      text: text,
      kind: kind,
      match: match,
      lemma: nil,
      phonetic: nil,
      collins: nil,
      frq_rank: nil,
      senses: [],
      tags: [],
      in_context: nil,
      sources: []
    }
  end
end
