# loop-engineering

ローカルLLM（LM Studio 等）と [OpenCode](https://opencode.ai/ja)、[Open Ralph Wiggum](https://github.com/Th0rgal/open-ralph-wiggum)、[ECC (Everything Claude Code)](https://github.com/affaan-m/ECC) を組み合わせて、**同じタスクを反復しながら品質の高い成果物を得る**ループエンジニアリング基盤です。

このリポジトリを他プロジェクトの隣に置く（または submodule 化する）だけで、同じ枠組みでモンキーテスト・設計監査・セキュリティ監査・依存関係監査・PR/MR レビューなどを回せます。

## できること

| ループ | 概要 | 成果物 |
| --- | --- | --- |
| `monkey-test` | Playwright で例外操作を繰り返し、仕様/設計の逸脱を検出 | findings / スライド / 動画 / Issue |
| `yabaiyo` | 計画→コード精査で設計・実装の「ヤバい」箇所を収集 | findings / スライド / 動画 / Issue |
| `pr-review` | 特定の MR/PR を読み解き、インライン＋総括レビューを投稿 | review-notes / コメント / Issue |
| `security-audit` | セキュリティ監査（OWASP・秘密情報・認証認可・依存関係） | findings / スライド / 動画 / Issue |
| `deps-audit` | 依存関係・サプライチェーン監査（outdated・脆弱性ツール・lockfile） | findings / スライド / 動画 / Issue |

新しいアイデアは `loops/_template/` をコピーするだけで追加できます（枠組みは共通、中身だけ差し替え）。

## ディレクトリ構成（全体像）

典型的な配置（隣に置くパターン）:

```
~/dev/
├── loop-engineering/          ← このリポジトリ（共通基盤・ここからコマンドを実行）
└── my-app/                    ← 対象プロジェクト（エージェントの cwd）
```

### 1. このリポジトリ（loop-engineering）

```
loop-engineering/
├── vendor/                          # git submodule（直接編集しない）
│   ├── open-ralph-wiggum/           # Ralph ループランナー
│   └── ecc/                         # ECC 本体（agents/skills/rules の供給元）
├── engine/                          # 共通実行枠（触らない）
│   ├── run-loop.sh                  # ループ起動エントリ
│   └── lib/                         # report.sh / video.sh / common.sh 等
├── loops/                           # ループ定義（アイデア単位。引数で切替）
│   ├── _template/                   # 新規ループのひな形
│   ├── monkey-test/
│   ├── yabaiyo/
│   ├── pr-review/
│   ├── security-audit/
│   └── deps-audit/
├── project-config/                  # ★プロジェクト固有の差し替えポイント
│   ├── target.yaml.example
│   ├── target.yaml                  # 初期設定で作成（gitignore）。対象パス等
│   ├── targets/                     # 複数PJ用レジストリ（--target-name）
│   ├── agents/                      # sync-ecc で抽出 → init で対象へコピー
│   ├── skills/
│   └── rules/
├── setup/                           # install / sync / init / doctor
├── output/                          # 互換用の空置き場（実成果物は対象PJ側）
└── docs/
```

- **差し替える場所**: ほぼ `project-config/` と（必要なら）`loops/<name>/`
- **触らなくてよい場所**: `engine/`、`vendor/`、`setup/`

### 2. 初期設定で「何がどこにできるか」

| 手順 | コマンド | できるもの |
| --- | --- | --- |
| 依存初期化 | `./setup/install.sh` | `vendor/*` submodule 取得、診断 |
| 対象指定 | `cp …/target.yaml.example` → 編集 | `project-config/target.yaml` |
| ECC抽出 | `./setup/sync-ecc-assets.sh --loop <name> [--loop ...]` / `--all-loops` | `project-config/{agents,skills,rules}/` に必要な分だけコピー（複数指定は和集合） |
| 対象へ接続 | `./setup/init-target-project.sh` | 対象PJ側に `.opencode/` と `.loop-engineering/` を作成 |
| （任意）グローバル | `./setup/configure-opencode.sh` | `~/.config/opencode/opencode.json` |
| ループ実行 | `./engine/run-loop.sh --loop <name>` | 対象PJの `.loop-engineering/output/...` に成果物 |

初期化後の **対象プロジェクト** 側:

```
my-app/                                 # = target.yaml の target_path
├── .gitignore                          # `.loop-engineering/` が自動追記される
├── .opencode/                          # OpenCode が読む設定（init で生成）
│   ├── opencode.json                   # LM Studio / MCP / skills / agents / lsp
│   └── loop-engineering/               # project-config からコピーされた資材
│       ├── agents/                     # ← project-config/agents
│       ├── skills/                     # ← project-config/skills
│       └── rules/                      # ← project-config/rules
├── .loop-engineering/                  # ランタイム＋成果物（gitignore）
│   ├── engine/lib/                     # report/video/tts（実行時に基盤から同期）
│   └── output/
│       └── <loop>/<RUN_ID>/
│           ├── prompt.md               # 展開済みプロンプト
│           ├── report-template.md      # ループ定義からコピー
│           ├── plan.md / findings.md   # エージェントが書く進捗
│           ├── report.md / slides/ …
│           └── report.pdf / report.mp4
└── (既存のアプリソース …)             # コピー対象外。そのまま
```

OpenCode / Ralph は対象PJを cwd にするため、成果物や report スクリプトは基盤リポジトリ側ではなく **対象PJ内** に置きます（`external_directory` 拒否を避けるため）。

### 3. コピーするもの / しないもの

データの流れ（矢印はコピーまたは同期）:

```
vendor/ecc
   │  sync-ecc-assets.sh（使う分だけ抽出）
   ▼
project-config/{agents,skills,rules}
   │  init-target-project.sh
   ▼
my-app/.opencode/loop-engineering/{agents,skills,rules}

engine/lib/{report,video,tts,...}.sh
   │  init / run-loop 時に同期
   ▼
my-app/.loop-engineering/engine/lib/

loops/<name>/prompt.md, report-template.md
   │  run-loop が展開・コピー（ソースは動かさない）
   ▼
my-app/.loop-engineering/output/<loop>/<RUN_ID>/
```

| もの | コピーする？ | 行き先 |
| --- | --- | --- |
| ECC の全資材 | **しない**（巨大） | — |
| ループで指定した agents/skills/rules | **する** | `project-config/` → 対象の `.opencode/loop-engineering/` |
| `engine/` 本体・`vendor/`・`loops/` 定義 | **しない**（基盤に残す） | 実行は常に loop-engineering 側から |
| `report.sh` / `video.sh` 等 | **する**（同期） | 対象の `.loop-engineering/engine/lib/` |
| プロンプト／report-template | 展開・コピー | 対象の `output/<loop>/<RUN_ID>/` |
| 対象アプリのソースコード | **しない** | エージェントが Read するだけ |
| `target.yaml` | 基盤側のみ（gitignore） | 対象PJへはコピーしない |

### 4. このプロジェクト更新時のアップデート

```bash
cd ~/dev/loop-engineering

# 推奨: ワンショット更新（併用ループはすべて --loop で渡す → 和集合 sync）
./setup/update.sh --loop yabaiyo --dry-run-loop yabaiyo
# 複数ループ + 無人 permission + git pull もする場合:
# ./setup/update.sh --pull --loop yabaiyo --loop monkey-test \
#   --mcp-permission allow --dry-run-loop yabaiyo
# 全バンドル: ./setup/update.sh --all-loops
```

手動で段階実行する場合:

```bash
git pull                                 # 任意
./setup/bootstrap-submodules.sh
# 併用するループを一度に指定（単一だと他ループ分の ECC 由来が落ちうる）
./setup/sync-ecc-assets.sh --loop yabaiyo --loop monkey-test
./setup/init-target-project.sh
./setup/doctor.sh
./engine/run-loop.sh --loop yabaiyo --dry-run
```

| 更新したいもの | やること |
| --- | --- |
| `engine/` / `setup/` / `loops/` の修正 | `git pull` だけで次の `run-loop` から有効（対象へコピー不要） |
| Ralph / ECC upstream | `bootstrap-submodules.sh`（または `update.sh`） |
| 対象の agents/skills/rules / opencode.json | `sync-ecc-assets` → `init-target-project`（`update.sh` が実行） |
| 対象の report/video スクリプト | `run-loop` のたびに自動同期（または init でも同期） |
| 自分で編集した `project-config/rules` 等 | **マニフェスト外は sync で消えない**（`.ecc-sync-manifest` 管理） |

成果物の確認・掃除:

```bash
./engine/list-runs.sh --loop yabaiyo
./engine/clean-runs.sh --loop yabaiyo --keep 5 --dry-run
```

複数プロジェクトは `project-config/targets/<name>.yaml` + `--target-name <name>` で切り替え（詳細は [docs/PORTING.md](docs/PORTING.md)）。

詳細は [docs/PORTING.md](docs/PORTING.md) / [docs/features/](docs/features/README.md) を参照。

## 5分クイックスタート

```bash
# 1. 依存確認 + submodule初期化
./setup/install.sh

# 2. LM Studio でモデルをロードし、ローカルサーバーを起動する

# 3. 対象プロジェクトを指定
cp project-config/target.yaml.example project-config/target.yaml
# → target_path / repo_url / monkey_test_target_url などを編集

# 4. ECC資材の取り込み + 対象プロジェクトへ接続
#    ※ ここで <target>/.opencode/opencode.json に LM Studio / MCP が入る
#    併用するループは一度に指定（和集合 sync）。別々に sync すると他ループ分が落ちる
./setup/sync-ecc-assets.sh --loop monkey-test --loop yabaiyo --loop pr-review --loop security-audit --loop deps-audit
# または全バンドル: ./setup/sync-ecc-assets.sh --all-loops
# target.yaml の target_path を使う( --target で上書きも可 )
./setup/init-target-project.sh

# 5. プロンプト確認 → 実行（使いたいループを選ぶ）
#    target.yaml の target_path があれば --target は省略可
# --- monkey-test ---
./engine/run-loop.sh --loop monkey-test --dry-run
./engine/run-loop.sh --loop monkey-test

# --- yabaiyo ---
./engine/run-loop.sh --loop yabaiyo --dry-run
./engine/run-loop.sh --loop yabaiyo

# --- pr-review ---
# target.yaml の pr_review_target / issue_post_mode も設定すること
./engine/run-loop.sh --loop pr-review --dry-run
./engine/run-loop.sh --loop pr-review
# 既存Issueへ追記する場合の例:
# ./engine/run-loop.sh --loop pr-review --issue-post-mode update --issue-target 42

# --- security-audit ---
./engine/run-loop.sh --loop security-audit --dry-run
./engine/run-loop.sh --loop security-audit

# --- deps-audit ---
./engine/run-loop.sh --loop deps-audit --dry-run
./engine/run-loop.sh --loop deps-audit
```

`./setup/configure-opencode.sh`（`~/.config/opencode/opencode.json` の更新）は **任意ステップ**です。  
ループ実行は対象プロジェクトの `.opencode/opencode.json` を使うため、`init-target-project.sh` まで完了していればグローバル設定は不要です。  
マシン全体で OpenCode + LM Studio を使いたいときだけ実行してください。

別ターミナルで進捗確認:

```bash
./engine/run-loop.sh --status
# または --target /path/to/your-project
```

無人ループ（MCP 確認なし）で回す場合:

```bash
./setup/init-target-project.sh --mcp-permission allow
./engine/run-loop.sh --loop yabaiyo
# Issue 未投稿時は非ゼロ終了。CLI で救済する例:
# ./engine/run-loop.sh --loop yabaiyo --issue-fallback cli
```

## ドキュメント

| ドキュメント | 内容 |
| --- | --- |
| [docs/SETUP.md](docs/SETUP.md) | セットアップ手順（もれなく・ダブりなく） |
| [docs/PORTING.md](docs/PORTING.md) | 他プロジェクトへの移植手順 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | ディレクトリ構成とデータの流れ |
| [docs/LOOPS.md](docs/LOOPS.md) | 同梱ループの説明と新規追加方法 |
| [docs/features/](docs/features/README.md) | **機能カタログ（要件定義・設計・ロードマップ）** |

## 前提ツール

| ツール | 必須 | 用途 |
| --- | --- | --- |
| [Bun](https://bun.sh/) | ○ | open-ralph-wiggum 実行 |
| [OpenCode](https://opencode.ai/ja) | ○ | エージェント本体 |
| Node.js / npx | ○ | Marp CLI / Playwright MCP |
| ffmpeg | ○ | 報告動画生成 |
| python3, jq, git | ○ | 設定生成・テンプレート展開 |
| LM Studio 等 | ○ | ローカル LLM（OpenAI互換API） |
| gh / glab | 任意 | Issue投稿のCLI代替 |

環境診断は `./setup/doctor.sh` でいつでも実行できます。  
エンジンの最小回帰は `./tests/smoke.sh`（GitHub Actions: `.github/workflows/smoke.yml`）。

Marp の再現性が必要な場合は `export LOOP_MARP_VERSION=@marp-team/marp-cli@4.5.0` を推奨します。  
レポート/動画のホスト保険と手動再変換は [docs/features/report-video-pipeline.md](docs/features/report-video-pipeline.md) を参照。

## ライセンス

MIT（`LICENSE` を参照）。`vendor/` 配下は各 upstream のライセンスに従います。
