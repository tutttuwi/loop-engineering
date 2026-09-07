# セットアップ手順

この手順は **初めてこのリポジトリを使うとき** に一度だけ実行します。  
各ステップは前のステップが完了している前提です。同じ作業を二度やらないよう、チェックリスト形式にしています。

## 全体フロー（この順番で）

```
[1] 前提ツール導入（Bun + 使うエージェント CLI）
[2] ./setup/install.sh          … submodule + 診断
[3] エージェント準備
      OpenCode: LM Studio 起動 + モデルロード
      Claude Code: `claude` ログイン / ANTHROPIC_API_KEY
      Cursor Agent: `agent` 導入 + CURSOR_API_KEY
[4] ./setup/configure-opencode.sh   … ★任意（OpenCode グローバル設定）
[5] project-config/target.yaml 作成（agent: を選ぶ）
[6] ./setup/sync-ecc-assets.sh --loop <name>
[7] ./setup/init-target-project.sh [--agent <name>] [--agents all]
[8] ./engine/run-loop.sh --loop <name> --dry-run
[9] ./engine/run-loop.sh --loop <name> [--agent <name>]
```

### 設定の置き場所（必須 / 任意）

| 設定 | 場所 | ループ実行に必須か |
| --- | --- | --- |
| 対象プロジェクトの OpenCode 設定 | `<target>/.opencode/opencode.json` | **OpenCode のとき必須** |
| Claude Code 設定 | `<target>/.claude/` + `.mcp.json` | **claude-code のとき必須** |
| Cursor Agent 設定 | `<target>/.cursor/rules/loop-engineering.mdc` | **cursor-agent のとき必須** |
| グローバル OpenCode 設定 | `~/.config/opencode/opencode.json` | 任意 |

エージェント切替の詳細は [features/multi-agent.md](./features/multi-agent.md)。

ループは対象プロジェクトを cwd にして動くため、[7] まで完了していれば [4] はスキップして構いません。  
[4] は「ホームディレクトリでも OpenCode + LM Studio / MCP を使いたい」場合の任意ステップです。

---

## [1] 前提ツールの導入

macOS (Homebrew) の例:

```bash
# Bun
curl -fsSL https://bun.sh/install | bash

# OpenCode
curl -fsSL https://opencode.ai/install | bash
# または: npm install -g opencode

# Claude Code（使う場合）
npm install -g @anthropic-ai/claude-code

# Cursor Agent CLI（使う場合）
curl https://cursor.com/install -fsS | bash

# ffmpeg / jq（Node.js は nvm 等で導入済み想定）
brew install ffmpeg jq
```

確認:

```bash
bun --version
opencode --version   # OpenCode を使う場合
claude --version     # Claude Code を使う場合
agent --version || cursor-agent --version   # Cursor Agent を使う場合
ffmpeg -version | head -1
npx --version
python3 --version
```

---

## [2] リポジトリ初期化

```bash
cd /path/to/loop-engineering
./setup/install.sh
```

`install.sh` が内部で行うこと:

1. `vendor/open-ralph-wiggum` と `vendor/ecc` の submodule 初期化（実行に必須）
   あわせて `vendor/cobusgreyling-loop-engineering`（パターン参考。未初期化でもループは回せる）
2. opencode CLI の有無確認
3. `project-config/target.yaml` 未作成時の案内
4. `./setup/doctor.sh` による環境診断

`ERROR` が残っている場合は表示されたヒントに従って解消し、再度 `./setup/doctor.sh` を実行してください。

---

## [3] エージェント準備

使うバックエンドを1つ（または init `--agents all` で複数レイアウト）決める。

### OpenCode + ローカルLLM

1. [LM Studio](https://lmstudio.ai/) を起動
2. コーディング向けモデルをダウンロードしてロード（例: Qwen3 Coder 等）
3. **Local Server** を起動（既定: `http://127.0.0.1:1234`）

疎通確認:

```bash
curl -s http://127.0.0.1:1234/v1/models | head
```

Ollama など他の OpenAI 互換サーバーでも可。その場合は init で `--lmstudio-base-url` を合わせます。

### Claude Code

```bash
claude          # 初回はブラウザまたは ANTHROPIC_API_KEY でログイン
export ANTHROPIC_API_KEY=sk-ant-...   # ヘッドレス時
```

### Cursor Agent CLI

```bash
curl https://cursor.com/install -fsS | bash
export CURSOR_API_KEY=...             # ヘッドレス / CI 時
agent --version                       # または cursor-agent
```

PATH に `agent` しか無い場合、run-loop が `RALPH_CURSOR_AGENT_BINARY` を自動設定します。

---

## [4] OpenCode グローバル設定（任意）

> **任意ステップです。** ループだけ回す場合はスキップし、[5] 以降 → [7] `init-target-project.sh` で十分です。  
> `init-target-project.sh` が `<target>/.opencode/opencode.json` に LM Studio・MCP を書き込むため、グローバル設定はループ実行には不要です。

次のようなときにだけ実行してください。

- 対象プロジェクト外でも、普段から OpenCode + LM Studio を使いたい
- 複数プロジェクトで共通の MCP / モデル既定を先にマシン全体へ置いておきたい

```bash
./setup/configure-opencode.sh
# 非対話例(確認プロンプトをスキップ。既存ファイルがあればバックアップは作成する):
# ./setup/configure-opencode.sh \
#   --base-url http://127.0.0.1:1234/v1 \
#   --model qwen3-coder-30b \
#   --model-name "Qwen3 Coder 30B" \
#   --mcp both \
#   --with-playwright \
#   --yes
```

既定では `~/.config/opencode/opencode.json` を安全にマージ更新します。  
既存のクラウドプロバイダー設定は維持し、次を追加／更新します。

| 項目 | 内容 |
| --- | --- |
| `provider.lmstudio` | ローカルLLM接続 |
| `model` | `lmstudio/<model-id>` |
| `mcp.github` / `mcp.gitlab` | Issue / PR・MR 操作用（対話または `--mcp` で選択、既定: both） |
| `mcp.playwright` | モンキーテスト用（既定オン） |
| `mcp.serena` | セマンティックコード操作（既定オン・要 `uvx`） |
| `lsp` | `true`（OpenCode 組み込み LSP、既定オン） |

書き込み前に更新内容の要約を表示し、`[y/N]` で確認します。  
既存ファイルがある場合は `opencode.json.bak.YYYYMMDD-HHMMSS` 形式でバックアップしてから更新します。  
復元例: `cp ~/.config/opencode/opencode.json.bak.20260811-153000 ~/.config/opencode/opencode.json`

トークン（Issue投稿前に設定。グローバル／プロジェクトどちらを使う場合も必要）:

```bash
export GITHUB_TOKEN=ghp_...          # GitHub MCP
export GITLAB_TOKEN=glpat-...        # GitLab MCP
export GITLAB_API_URL=https://gitlab.example.com/api/v4  # セルフホスト時
```

Serena 用:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh   # uvx を導入
```

Serena は起動時にブラウザでダッシュボードを開かないよう `--open-web-dashboard false` 付きで登録します。  
ダッシュボード自体は有効なままなので、必要なら `http://127.0.0.1:24282/dashboard/` を手動で開けます。  
既存の `opencode.json` に古い Serena 設定がある場合は `./setup/init-target-project.sh`（または `configure-opencode.sh`）を再実行して反映してください。

確認: `opencode` を起動し `/model` で `LM Studio (local)` が選べること。MCP 一覧に github / gitlab / playwright / serena が出ること。

---

## [5] 対象プロジェクト設定

```bash
cp project-config/target.yaml.example project-config/target.yaml
```

最低限編集する項目:

| キー | 意味 |
| --- | --- |
| `target_path` | 対象リポジトリのローカルパス |
| `target_name` | レポート表示名 |
| `repo_provider` | `github` または `gitlab` |
| `repo_url` | Issue 投稿先 |
| `monkey_test_target_url` | モンキーテスト時のアプリURL |
| `monkey_test_accounts` | 任意。テスト用アカウントDSL（`role` または `role|login|secret` のカンマ区切り） |
| `pr_review_target` | PR/MR レビュー対象（番号またはURL） |
| `issue_post_mode` | Issue投稿: `create`(毎回新規・既定) / `update`(既存へ追記) |
| `issue_target` | `update` 時の既存Issue番号またはURL |

`target.yaml` はローカルパスを含むため `.gitignore` 対象です。

---

## [6] ECC 資材の取り込み

ループごとに必要な agents / skills / rules だけを `project-config/` にコピーします。
**複数ループを併用する場合は、使うループを一度のコマンドで全部指定**してください（和集合で 1 マニフェストに揃えます）。ループごとに別々に sync すると、後から指定したループ以外の ECC 由来が削除されます。

```bash
# 併用するループを一度に指定（推奨）
./setup/sync-ecc-assets.sh --loop monkey-test --loop yabaiyo --loop pr-review --loop security-audit --loop deps-audit

# バンドル全ループを和集合
./setup/sync-ecc-assets.sh --all-loops

# 単一ループのみ使う場合
./setup/sync-ecc-assets.sh --loop monkey-test

# 利用可能な一覧を見る
./setup/sync-ecc-assets.sh --list
```

取り込む一覧は各 `loops/<name>/loop.yaml` の `ecc_agents` / `ecc_skills` / `ecc_rules` で定義されています。  
プロジェクト固有ルールは `project-config/rules/` に直接追加・編集してください（`vendor/ecc` は編集しない）。マニフェスト（`.ecc-sync-manifest`）に無いファイルはユーザー資産として保持されます。詳細は [features/ecc-sync.md](./features/ecc-sync.md)。

---

## [7] 対象プロジェクトへの接続（ループ用の必須設定）

対象パスの優先順位: `--target` 引数 > `project-config/target.yaml` の `target_path`

```bash
# target.yaml の target_path を使う場合(推奨)。agent は yaml の値（既定 opencode）
./setup/init-target-project.sh

# Claude Code / Cursor レイアウト
./setup/init-target-project.sh --agent claude-code
./setup/init-target-project.sh --agent cursor-agent

# 3レイアウトまとめて書き、実行時に --agent で切替
./setup/init-target-project.sh --agents all

# パスを明示する場合(CLIが優先され、target.yaml も更新される)
./setup/init-target-project.sh --target /path/to/your-project \
  --lmstudio-base-url http://127.0.0.1:1234/v1 \
  --lmstudio-model qwen3-coder-30b
```

これが行うこと:

- `init_agents` に **opencode** が含まれるとき:
  - `project-config/{agents,skills,rules}` → `<target>/.opencode/loop-engineering/`
  - `<target>/.opencode/opencode.json`（LM Studio / MCP / lsp）
- **claude-code**: `.claude/` と `.mcp.json`
- **cursor-agent**: `.cursor/rules/loop-engineering.mdc` / skills / mcp.json
- `project-config/target.yaml` の `target_path` / `agent` 等を更新

既存の `opencode.json` がある場合は `.bak.<timestamp>` にバックアップします。  
個別にオフにする場合: `--without-github` / `--without-gitlab` / `--without-playwright` / `--without-serena` / `--without-lsp`  
無人ループ向け: `--mcp-permission allow`（既定は `ask`。詳細は [features/permissions-unattended.md](./features/permissions-unattended.md)）  
サーバ別上書き例: `--mcp-permission-overrides github=allow,playwright=deny`（`permission.<server>_*`）

### Issue 投稿用トークン

| プロバイダー | 環境変数 |
| --- | --- |
| GitHub | `GITHUB_TOKEN` |
| GitLab | `GITLAB_TOKEN`（必要なら `GITLAB_API_URL`） |

---

## [8] dry-run でプロンプト確認

```bash
./engine/run-loop.sh --loop monkey-test --dry-run
```

`<target>/.loop-engineering/output/<loop>/<RUN_ID>/prompt.md` が生成され、標準出力にも表示されます。
パス・URL・完了 promise が意図どおりか確認してください。

---

## [9] 本番実行

```bash
./engine/run-loop.sh --loop monkey-test --target /path/to/your-project

# よく使うオプション
./engine/run-loop.sh --loop yabaiyo --max-iterations 20
./engine/run-loop.sh --loop yabaiyo --agent cursor-agent
./engine/run-loop.sh --loop yabaiyo --agent claude-code
./engine/run-loop.sh --loop pr-review --model lmstudio/qwen3-coder-30b
./engine/run-loop.sh --loop security-audit --max-iterations 20
./engine/run-loop.sh --loop deps-audit --max-iterations 15
./engine/run-loop.sh --loop monkey-test --extra "--tasks --no-commit"
./engine/run-loop.sh --loop yabaiyo --post-report   # Marp/動画のホスト側保険
```

無人実行では init 時に MCP permission を allow にしてください（詳細は [features/permissions-unattended.md](./features/permissions-unattended.md)）:

```bash
./setup/init-target-project.sh --mcp-permission allow
# 例: 一括 ask のまま github だけ allow
# ./setup/init-target-project.sh --mcp-permission ask \
#   --mcp-permission-overrides github=allow,playwright=deny
```

実行中は対象プロジェクトのカレントで Ralph がループします。別ターミナルから:

```bash
cd /path/to/your-project
bun /path/to/loop-engineering/vendor/open-ralph-wiggum/ralph.ts --status
# ヒント注入
bun .../ralph.ts --add-context "まずはログイン画面の二重送信から検証して"
```

---

## 運用ショートカット（セットアップ後）

初回セットアップ完了後の定番操作。詳細は [features/](./features/README.md) を参照。

| やりたいこと | コマンド | 詳細 |
| --- | --- | --- |
| 一発更新（sync→init→doctor） | `./setup/update.sh --loop <name> [--loop ...]` / `--all-loops` | [porting-and-update.md](./features/porting-and-update.md) / [ecc-sync.md](./features/ecc-sync.md) |
| 無人 MCP permission | `init` / `update.sh` に `--mcp-permission allow` | [permissions-unattended.md](./features/permissions-unattended.md) |
| レポート/動画の保険 | `run-loop.sh --post-report` | [report-video-pipeline.md](./features/report-video-pipeline.md) |
| 成果物の一覧・掃除 | `./engine/list-runs.sh` / `./engine/clean-runs.sh` | [artifact-lifecycle.md](./features/artifact-lifecycle.md) |
| エンジン smoke | `./tests/smoke.sh` | yaml_get / render-prompt / dry-run / post-report·Marp 等 |

```bash
./setup/update.sh --loop yabaiyo --mcp-permission allow --dry-run-loop yabaiyo
./engine/list-runs.sh --loop yabaiyo
./engine/clean-runs.sh --loop yabaiyo --keep 5 --dry-run
./tests/smoke.sh
```

### レポート / TTS の環境変数

| 変数 | 既定 | メモ |
| --- | --- | --- |
| `LOOP_MARP_VERSION` | `@marp-team/marp-cli@latest` | 再現性のためピン推奨: `@marp-team/marp-cli@4.5.0`（major 固定なら `@marp-team/marp-cli@4`） |
| `LOOP_TTS_ENGINE` | 自動（`say` → VOICEVOX 起動中 → `none`） | 明示: `say` / `voicevox` / `openai` / `none` |

```bash
export LOOP_MARP_VERSION=@marp-team/marp-cli@4.5.0
export LOOP_TTS_ENGINE=none   # Linux で無音にする場合など
```

レポート経路の詳細（手動再変換・欠落時スキップ・TTS/動画が partial な理由）は
[features/report-video-pipeline.md](./features/report-video-pipeline.md) を参照。
経路の回帰は `./tests/smoke.sh` の「post-report / Marp」節（実 Chromium / TTS なし）。

---

## トラブルシュート

| 症状 | 対処 |
| --- | --- |
| `ralph.ts が見つかりません` | `./setup/bootstrap-submodules.sh` |
| `ProviderModelNotFoundError` | OpenCode: 対象の `.opencode/opencode.json` に `lmstudio` があるか確認。なければ `init-target-project.sh` を再実行 |
| エージェント CLI が無い | doctor のヒントに従う。Cursor は `agent` と `cursor-agent` の両方を探す |
| Claude/Cursor で Issue が作れない | MCP 未設定なら `--issue-fallback cli`。`gh` / `GITHUB_TOKEN` を確認 |
| LM Studio に繋がらない | モデルロードと Local Server 起動を確認。`curl .../v1/models` |
| Playwright が動かない | `init-target-project.sh` 実行済みか、対象の `opencode.json` に `mcp.playwright` があるか確認 |
| 動画生成失敗 | `brew install ffmpeg`。TTSは `LOOP_TTS_ENGINE=none` で無音動画にもできる。Linux で `say` が無い場合、未設定なら既定は `none`（VOICEVOX 起動中なら `voicevox`） |
| Marp が毎回違う / オフライン失敗 | `export LOOP_MARP_VERSION=@marp-team/marp-cli@4.5.0` でピン留め |
| Issue が作れない | `GITHUB_TOKEN` / `GITLAB_TOKEN` と MCP 設定を確認 |

診断の再実行:

```bash
./setup/doctor.sh
```

---

## セットアップスクリプト一覧（役割分担）

| スクリプト | 役割 | いつ使う |
| --- | --- | --- |
| `setup/install.sh` | 初回の一括入口 | 最初の1回 |
| `setup/bootstrap-submodules.sh` | submodule のみ | clone直後・更新時 |
| `setup/update.sh` | pull→sync→init→doctor のワンショット | 基盤更新・資材再同期時 |
| `setup/doctor.sh` | 依存診断 | いつでも |
| `setup/configure-opencode.sh` | **任意:** グローバル `~/.config/opencode/opencode.json` | マシン全体で OpenCode を使うとき |
| `setup/sync-ecc-assets.sh` | ECC → project-config | ループ追加・資材更新時 |
| `setup/init-target-project.sh` | **ループ必須:** 対象PJへエージェント設定 | `--agent` / `--agents all`。OpenCode 時は `--mcp-permission allow` で無人向け |
| `setup/new-loop.sh` | `_template` から新ループ作成 | アイデア追加時 |
| `engine/list-runs.sh` / `clean-runs.sh` | 成果物の一覧・掃除 | 運用中 |
