defmodule Eim.Dict.Entry do
  defstruct [
    :text,
    :kind,
    :match,
    :lemma,
    :phonetic,
    :collins,
    :frq_rank,
    senses: [],
    tags: [],
    in_context: nil,
    sources: []
  ]
end
