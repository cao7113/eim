# eim 技术方案 01：ECDICT 词典层（含 LLM 预留）

*草案 · 2026-11-10 · 对应阶段 1；阶段 2（LLM）只做接口预留*

## 0. 目标与范围

**目标**：插件划词后，后端返回可靠的词典结果：中文释义、音标、词性、考试标签、词频，并把 `gave`、`running` 这类变形还原到原型。

**本阶段做**：数据获取与校验、Ash 资源与迁移、幂等导入任务、`lookup` 解析链路、API 暴露、测试。

**本阶段不做**：LLM 调用、缓存与调用日志表、登录与限流、Wiktionary / Tatoeba 等其他数据源、插件 UI。

**前提**：Phoenix 1.8+、Ash 3.x、AshPostgres、AshJsonApi、AshAdmin 已就绪，应用名 `eim`。文中 Ash 代码是骨架，DSL 细节以项目锁定版本的文档为准。

## 1. 总体设计

```text
text ─► Normalize ─► Lookup ─► Entry（统一结果）
         kind/hash     ① 精确 word_lc
                       ② 变形 lexeme_forms → 原型
                       ③ 模糊 sw
                       └ 未命中 → {:miss, normalized}（阶段 2 交给 LLM）
```

三条原则：

1. **数据与逻辑分层**：`Lexeme*` 只存数据，`Lookup` 是纯逻辑，对外只暴露统一的 `Entry`。
2. **导入可重复**：同一份 CSV 导入多次结果相同，并记录来源版本。
3. **先定死对外契约**：`Entry` 结构固定，以后 LLM、Wiktionary 都往同一个结构里填。

## 2. 步骤 1：获取并校验数据

```bash
# 本地已有仓库；首次准备时可 clone 到该路径
git clone --depth 1 https://github.com/skywind3000/ECDICT.git _local/ecdict
head -n 3 _local/ecdict/ecdict.csv
shasum -a 256 _local/ecdict/ecdict.csv
git -C _local/ecdict rev-parse HEAD
```

- 预期表头：`word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio`，以实际文件为准。
- UTF-8 编码，释义字段含引号内换行。**不要用 Excel 打开或保存**。
- 数据文件保留在 `_local/ecdict/`，不提交进项目仓库。
- **需实测确认**：多行释义是真实换行还是字面 `\n`；`bnc`、`frq`、`oxford` 的空值写法；是否有仅大小写不同的重复词条。

**验收**：表头核对无误，sha256 与 commit 已记录。

**本地校验结果（2026-11-10）**：已检查 `_local/ecdict/ecdict.csv`，表头 13 列与预期一致，UTF-8、770,611 行，大小写不敏感的重复词条为 0。仓库 commit 为 `39cfb9672c0906b63569e0453c2e6abfb9ab182a`，文件 SHA-256 为 `d1ecbdf9ee2b920afb6f430ca6b6bb9f559588cf0dff86e04bd255f9390843cc`。`collins`、`oxford` 以空值为主，`bnc`、`frq` 的 `0` 占多数；导入将空值和非正数统一存为 NULL。数据保留在 `_local/`，不会提交进项目。

## 3. 步骤 2：数据模型

`mix.exs` 增加 `{:nimble_csv, "~> 1.2"}`，运行 `mix deps.get`。

**lexemes（词条，ECDICT 一行一条）**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | uuid | 主键 |
| word | text | 原词，**唯一** |
| word\_lc | text | 小写，精确查询，btree 索引 |
| sw | text | 去掉非字母数字并小写，模糊匹配，索引（不唯一） |
| phonetic / translation / definition / pos | text | 音标、中文释义原文、英文释义原文、词性占比原文 |
| tags | text\[\] | `tag` 按空格拆分，如 cet4、ielts |
| collins / bnc\_rank / frq\_rank | integer | 星级与两套词频排名，空或 0 存 NULL（先抽样核对 0 的含义） |
| oxford | boolean | 是否牛津核心词 |
| exchange | text | 原始变形字符串，保留以便重新解析 |
| lemma | text | 原型，取 exchange 中的 `0:` 项，非变形词为 NULL |
| source / source\_version | text | 默认 `ecdict` / 导入时的 commit |

**lexeme\_forms（变形反查表）**：`lexeme_id`（外键，随词条级联删除）、`form`、`form_lc`、`form_type`（past、past\_participle、present\_participle、third\_person、comparative、superlative、plural）。唯一约束 `(lexeme_id, form_lc, form_type)`，`form_lc` 建索引。

**dictionary\_imports（导入记录）**：`source`、`source_version`、`file_sha256`、`row_count`、`notes`、导入时间。

设计取舍：

- 不用 citext，显式存 `word_lc`，少一个扩展，查询行为明确。
- 变形单独成表，`gave` 一次索引即可还原，不必运行时解析字符串。
- 保留 `translation`、`exchange` 原文，解析规则改了不用重新导入。

## 4. 步骤 3：实现资源并迁移

```elixir
# lib/eim/dictionary.ex
defmodule Eim.Dict do
  use Ash.Domain, otp_app: :eim

  resources do
    resource Eim.Dict.Lexeme
    resource Eim.Dict.LexemeForm
    resource Eim.Dict.Import
  end
end
```

```elixir
# lib/eim/dictionary/lexeme.ex
defmodule Eim.Dict.Lexeme do
  use Ash.Resource, otp_app: :eim, domain: Eim.Dict, data_layer: AshPostgres.DataLayer

  postgres do
    table "lexemes"
    repo Eim.Repo

    custom_indexes do
      index [:word_lc]
      index [:sw]
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

  identities do
    identity :unique_word, [:word]
  end

  relationships do
    has_many :forms, Eim.Dict.LexemeForm
  end

  actions do
    defaults [:read]
    # lookup 动作见步骤 6
  end
end
```

`LexemeForm`、`Import` 同理：表名 `lexeme_forms`、`dictionary_imports`。`LexemeForm` 用 `belongs_to :lexeme, Eim.Dict.Lexeme, allow_nil?: false`，在 `postgres do references do reference :lexeme, on_delete: :delete end end` 中声明级联删除，并按第 3 节声明 identity 与 `form_lc` 索引；`Import` 提供 `create :record`，accept `source, source_version, file_sha256, row_count, notes`。

```bash
mix ash.codegen create_dictionary
mix ash.migrate
```

**验收**：`\d lexemes` 能看到上述字段和索引；`lexeme_forms` 有外键与唯一索引。

## 5. 步骤 4：导入任务

要点：

- NimbleCSV 流式读取，每 1000 行一批，用 `Repo.insert_all` 直接写表。批量导入属于受信任的数据加载，绕过 Ash 动作以换取速度。
- 按 `word` 冲突时更新，所以**可重复执行**；同批内先按 `word` 去重，否则 PostgreSQL 会报“同一行被影响两次”。
- 每批写入词条后，用返回的 id 写 `lexeme_forms`，冲突忽略。
- 先校验表头，不符就中止。时间戳列用数据库默认值，不在导入里写。

```elixir
# lib/eim/dictionary/importer.ex
defmodule Eim.Dict.Importer do
  alias Eim.Repo
  alias Eim.Dict.Normalize
  alias NimbleCSV.RFC4180, as: CSV

  @header ~w(word phonetic definition translation pos collins oxford tag bnc frq exchange)
  @form_types %{"p" => "past", "d" => "past_participle", "i" => "present_participle",
                "3" => "third_person", "r" => "comparative", "t" => "superlative", "s" => "plural"}

  def run(path, version) do
    [header] = path |> File.stream!() |> CSV.parse_stream(skip_headers: false) |> Enum.take(1)
    if Enum.take(header, 11) != @header, do: raise("unexpected header: #{inspect(header)}")

    path
    |> File.stream!()
    |> CSV.parse_stream(skip_headers: true)
    |> Stream.map(&to_row(&1, version))
    |> Stream.reject(&is_nil/1)
    |> Stream.chunk_every(1000)
    |> Enum.reduce(0, fn chunk, n ->
      insert_chunk(chunk)
      n + length(chunk)
    end)
  end

  defp insert_chunk(pairs) do
    # 同批内重复的词条保留最后一条
    pairs = pairs |> Enum.reverse() |> Enum.uniq_by(fn {row, _} -> row.word end)
    rows = Enum.map(pairs, fn {row, _} -> row end)
    replace = Map.keys(hd(rows)) -- [:word]

    {_, returned} =
      Repo.insert_all("lexemes", rows,
        on_conflict: {:replace, replace},
        conflict_target: [:word],
        returning: [:id, :word]
      )

    ids = Map.new(returned, &{&1.word, &1.id})

    forms =
      for {row, fs} <- pairs, {type, form} <- fs, id = ids[row.word] do
        %{lexeme_id: id, form: form, form_lc: String.downcase(form), form_type: type}
      end

    Repo.insert_all("lexeme_forms", forms, on_conflict: :nothing)
  end

  defp to_row([word, phonetic, definition, translation, pos, collins, oxford, tag, bnc, frq, exchange | _], version) do
    word = String.trim(word)
    {lemma, forms} = parse_exchange(exchange)

    if word != "" do
      row = %{
        word: word, word_lc: String.downcase(word), sw: Normalize.strip_word(word),
        phonetic: blank(phonetic), translation: blank(translation), definition: blank(definition),
        pos: blank(pos), tags: String.split(tag, " ", trim: true),
        collins: to_int(collins), oxford: oxford == "1",
        bnc_rank: to_int(bnc), frq_rank: to_int(frq),
        exchange: blank(exchange), lemma: lemma,
        source: "ecdict", source_version: version
      }

      {row, forms}
    end
  end

  defp to_row(_, _), do: nil

  @doc "p:gave/d:given/0:give -> {lemma, [{form_type, form}]}"
  def parse_exchange(str) when str in [nil, ""], do: {nil, []}

  def parse_exchange(str) do
    items =
      for item <- String.split(str, "/", trim: true),
          [k, v] <- [String.split(item, ":", parts: 2)],
          v != "",
          do: {k, v}

    {Enum.find_value(items, fn {k, v} -> k == "0" && v end),
     for({k, v} <- items, type = @form_types[k], do: {type, v})}
  end

  defp blank(s) do
    case String.trim(s) do
      "" -> nil
      v -> v
    end
  end

  defp to_int(s) do
    case Integer.parse(String.trim(s)) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end
end
```

```elixir
# lib/mix/tasks/eim.import_ecdict.ex
defmodule Mix.Tasks.Eim.ImportEcdict do
  use Mix.Task
  @shortdoc "导入 ECDICT CSV：mix eim.import_ecdict PATH --version COMMIT"

  def run(args) do
    {opts, [path], _} = OptionParser.parse(args, strict: [version: :string])
    Mix.Task.run("app.start")
    sha = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
    count = Eim.Dict.Importer.run(path, opts[:version] || "unknown")

    Eim.Dict.Import
    |> Ash.Changeset.for_create(:record, %{source: "ecdict", source_version: opts[:version], file_sha256: sha, row_count: count})
    |> Ash.create!()

    Mix.shell().info("imported #{count} rows")
  end
end
```

**验收**：

```sql
SELECT count(*) FROM lexemes;
SELECT l.word FROM lexeme_forms f JOIN lexemes l ON l.id = f.lexeme_id WHERE f.form_lc = 'gave';  -- give
```

再执行一次导入，`lexemes` 行数不变；`dictionary_imports` 有对应记录。

## 6. 步骤 5：解析链路

**统一结果 `Entry`**（对外契约，阶段 2 也沿用）：

```elixir
defmodule Eim.Dict.Entry do
  @moduledoc "词典查询的统一结果。阶段 2 的 LLM、其他词典都往这个结构里填。"
  defstruct [:text, :kind, :match, :lemma, :phonetic, :collins, :frq_rank,
             senses: [], tags: [], in_context: nil, sources: []]
end
```

**输入规范化**（也是阶段 2 缓存 key 的基础）：

```elixir
defmodule Eim.Dict.Normalize do
  @max_len 500

  def run(text) when is_binary(text) do
    t0 = text |> String.replace(~r/\s+/u, " ") |> String.trim()
    kind = kind(t0)
    t = if kind == :sentence, do: t0, else: trim_edge(t0)

    cond do
      t == "" -> {:error, :empty}
      String.length(t) > @max_len -> {:error, :too_long}
      true -> {:ok, %{text: t, lc: String.downcase(t), kind: kind, hash: hash(t)}}
    end
  end

  def strip_word(s), do: s |> String.replace(~r/[^\p{L}\p{N}]/u, "") |> String.downcase()

  # 只去掉首尾的常见标点和括号，保留 C++、node.js 这类技术词
  defp trim_edge(t), do: String.replace(t, ~r/^[\s"'(\[]+|[\s.,;:!?"')\]]+$/u, "")

  defp kind(t) do
    case t |> String.split(" ") |> length() do
      1 -> :word
      n when n <= 4 -> :phrase
      _ -> :sentence
    end
  end

  defp hash(t), do: :crypto.hash(:sha256, String.downcase(t)) |> Base.encode16(case: :lower)
end
```

**查询**：精确 → 变形 → 模糊，句子直接 miss。

```elixir
defmodule Eim.Dict.Lookup do
  require Ash.Query
  alias Eim.Dict.{Lexeme, LexemeForm, Entry, Normalize, Senses}

  def run(text) do
    with {:ok, n} <- Normalize.run(text) do
      if n.kind == :sentence, do: {:miss, n}, else: resolve(n)
    end
  end

  defp resolve(n) do
    cond do
      lex = exact(n.lc) -> {:ok, build(n, lex, :exact)}
      lex = via_form(n.lc) -> {:ok, build(n, lex, :form)}
      lex = fuzzy(n.lc) -> {:ok, build(n, lex, :fuzzy)}
      true -> {:miss, n}
    end
  end

  defp exact(lc) do
    rows = Lexeme |> Ash.Query.filter(word_lc == ^lc) |> Ash.Query.limit(5) |> Ash.read!()
    Enum.find(rows, &(&1.word == lc)) || best(rows)
  end

  defp via_form(lc) do
    LexemeForm
    |> Ash.Query.filter(form_lc == ^lc)
    |> Ash.Query.load(:lexeme)
    |> Ash.read!()
    |> Enum.map(& &1.lexeme)
    |> best()
  end

  defp fuzzy(lc) do
    sw = Normalize.strip_word(lc)
    Lexeme |> Ash.Query.filter(sw == ^sw) |> Ash.Query.limit(10) |> Ash.read!() |> best()
  end

  # 同形多条时取词频排名最靠前的
  defp best([]), do: nil
  defp best(rows), do: Enum.min_by(rows, &rank/1)
  defp rank(%{frq_rank: r}) when is_integer(r) and r > 0, do: r
  defp rank(_), do: 1_000_000_000

  # 命中的是变形词时，改用原型词条作为主结果
  defp build(n, lex, match) do
    primary = (lex.lemma && exact(String.downcase(lex.lemma))) || lex

    %Entry{
      text: n.text, kind: n.kind, match: match, lemma: primary.word,
      phonetic: primary.phonetic, collins: primary.collins, frq_rank: primary.frq_rank,
      senses: Senses.parse(primary.translation), tags: primary.tags,
      sources: [%{name: primary.source, version: primary.source_version}]
    }
  end
end
```

**义项解析**（纯函数；展示要用，阶段 2 也作为 LLM 的候选义项）：

```elixir
defmodule Eim.Dict.Senses do
  def parse(nil), do: []

  def parse(text) do
    text
    |> String.split(["\n", "\\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_line/1)
  end

  # 形如 "[计] 缓存"、"n. 苹果"；解析不出的复合写法整行放进 zh，保证不丢内容
  defp parse_line(line) do
    m = Regex.named_captures(~r/^(?:\[(?<domain>[^\]]+)\]\s*)?(?:(?<pos>[a-z]+)\.\s*)?(?<zh>.+)$/u, line)
    %{pos: nilify(m["pos"]), domain: nilify(m["domain"]), zh: m["zh"]}
  end

  defp nilify(""), do: nil
  defp nilify(v), do: v
end
```

**验收**：`gave`→give（`match: :form`）、`long-time`→`longtime`（`:fuzzy`）、`idempotent,` 去标点后可查、句子返回 miss。

## 7. 步骤 6：对外 API

在 `Lexeme` 的 `actions` 里加一个 generic action，并在领域里声明 code interface：

```elixir
action :lookup, :map do
  argument :text, :string, allow_nil?: false

  run fn input, _ctx ->
    case Eim.Dict.Lookup.run(input.arguments.text) do
      {:ok, entry} -> {:ok, Map.from_struct(entry)}
      {:miss, n} -> {:ok, %{match: :miss, text: n.text, kind: n.kind}}
      {:error, reason} -> {:error, "invalid text: #{inspect(reason)}"}
    end
  end
end
```

```elixir
# eim/dictionary.ex 的 resources 中
resource Eim.Dict.Lexeme do
  define :lookup, args: [:text]
end
```

- **路由**：用 AshJsonApi generic action 暴露 `GET /api/dict/lookup?text=`，并由统一 OpenAPI/Swagger UI 发布接口契约。
- **AshAdmin**：给 `Lexeme` 加 `AshAdmin.Resource` 扩展，在 `/admin` 抽查数据。
- **认证**：本阶段可仅在开发环境开放；**接 LLM 之前必须先有认证与限流**。
- **插件**：把 background 里的 `mockTranslate` 换成对该接口的 `fetch`，浮窗展示 `lemma / phonetic / senses / tags`。
- 插件端到端划词查词 MVP 的目标、消息链路、错误状态与验收标准见 [插件划词查词 MVP 技术方案](./插件划词查词MVP技术方案.md)。

**验收**：`curl` 查询 `gave` 返回 `lemma: give`；浮窗能显示真实释义。

当前接口通过 AshJsonApi 实现为 `GET /api/dict/lookup?text=...`。请求需带 `Accept: application/vnd.api+json`，成功响应为包含 `text`、`kind`、`match`、`lemma`、`phonetic`、`senses`、`tags` 和 `sources` 的 JSON 对象；未命中返回相同结构且 `match: "miss"`。无效输入使用 JSON:API error 格式。OpenAPI 规范位于 `/api/open_api`，Swagger UI 位于 `/api/swaggerui`。迁移与数据导入命令：

```bash
mix ash.migrate
mix eim.import_ecdict
curl -H 'Accept: application/vnd.api+json' 'http://localhost:4000/api/dict/lookup?text=gave'
```

导入任务默认读取 `_local/ecdict/ecdict.csv`，也可传入其他 CSV 路径和 `--version`。导入按 1,000 行分批事务处理，可安全重复执行；每次执行会记录数据版本、SHA-256、导入行数和跳过行数。

## 8. 步骤 7：测试

- **纯函数单元测试**：`parse_exchange`、`Senses.parse`（含字面 `\n` 与真实换行两种输入）、`Normalize.run`（空白、首尾标点、`C++` 不被破坏、超长、kind 判定）、`strip_word`。
- **导入集成测试**：用 `test/support/fixtures/ecdict_sample.csv` 覆盖字面量与真实换行释义、变形词、同批重复词条、缺列行。断言行数、**重复导入幂等**、`gave` 经原型字段命中 give。
- **索引检查**：对三条查询跑 `EXPLAIN`，确认走 `word_lc`、`form_lc`、`sw` 索引；对一批随机词压测，记录本机耗时，不写死阈值。
- **黄金样本**：整理 100 个真实技术词（如 idempotent、debounce、mutex），跑 `lookup`，人工标注“命中 / 释义可用 / 缺失”。它既是本阶段的覆盖率报告，也是阶段 2 对比各 LLM 供应商的评测集种子。

## 9. LLM 预留清单

| 预留点 | 本阶段做什么 | 阶段 2 怎么用 |
| --- | --- | --- |
| `Entry` 契约，含 `in_context`、`sources` | 定义 struct，字段留空 | LLM 填 `in_context`，来源标记为 AI，与词典数据区分 |
| 未命中返回 `{:miss, normalized}` | 带上 `kind`、`hash` | 翻译动作据此查缓存、调用 LLM，缓存 key 含 `hash` |
| `Senses.parse` 结构化义项 | 纯函数 + 测试 | 作为候选义项放进提示词，让模型选择并解释，而不是自由翻译 |
| `source` / `source_version` / `dictionary_imports` | 如实记录 | 缓存 key 带词典版本，词典更新后可批量失效 |
| `Normalize` 的长度上限与 `kind` | 实现 | 决定哪些走词典、哪些才调用 LLM，是成本控制入口 |
| 黄金样本 | 整理 100 词 | 固定评测集，对比供应商与提示词版本 |
| 域边界 | 只建 `Eim.Dict` | 新增 `Eim.Translation`（编排：lookup → 缓存 → LLM）与 `Eim.AI`（供应商抽象，封装 ReqLLM）；`TranslationCache`、`LlmCall` 资源也在阶段 2 建 |

**依赖方向**：`Translation → Dictionary`、`Translation → AI`，反向禁止。`Dictionary` 不知道 LLM 的存在，没有 LLM 时也能独立工作。

**刻意不预建**：缓存表、调用日志表、供应商配置。没有真实调用数据前先建表，大概率要返工。

## 10. 里程碑与验收清单

- [x] M1 数据：`ecdict.csv` 已获取，表头核对，sha256 与 commit 已记录
- [x] M2 模型：三个资源与迁移完成，`mix ash.migrate` 成功
- [x] M3 导入：`mix eim.import_ecdict` 成功，`dictionary_imports` 有记录
- [x] M4 解析：`Normalize`、`Senses`、`Lookup` 完成，单元与集成测试通过
- [x] M5 API：AshJsonApi `GET /api/dict/lookup` 可用并纳入 OpenAPI
- [ ] M5 插件联调：插件已用真实数据替换 mock
- [ ] M6 抽查：100 词黄金样本跑完，覆盖率记录在案

每个里程碑独立可验收，建议各自提交一次 Git。

## 11. 风险与待决事项

- **授权**：MIT 是仓库声明，上游来源授权在商业化前需再确认。
- **数据偏旧**：更新主要停留在 2017 年前后，技术新词覆盖以 M6 抽查结果为准，据此决定是否优先接入 Wiktionary。
- **数据细节已实测**：释义使用字面量 `\n`；`bnc`、`frq` 中 `0` 是常见空值写法；数据中没有大小写不敏感的重复词条。
- **API 契约**：当前由普通控制器提供稳定 JSON 响应，尚未纳入 AshJsonApi / OpenAPI；契约稳定后再评估强类型 API schema。
- **版本差异**：Ash、AshPostgres、AshJsonApi 的 DSL 以锁定版本文档为准，本文代码需要编译验证。
- **待决**：`detail`、`audio` 字段基本为空，本阶段忽略。
