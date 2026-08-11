# loop-engineering

ローカルLLM（LM Studio 等）と [OpenCode](https://opencode.ai/ja)、[Open Ralph Wiggum](https://github.com/Th0rgal/open-ralph-wiggum)、[ECC (Everything Claude Code)](https://github.com/affaan-m/ECC) を組み合わせて、**同じタスクを反復しながら品質の高い成果物を得る**ループエンジニアリング基盤です。

このリポジトリを他プロジェクトの隣に置く（または submodule 化する）だけで、同じ枠組みでモンキーテスト・設計監査・PR/MR レビューなどを回せます。

## できること

| ループ | 概要 | 成果物 |
| --- | --- | --- |
| `monkey-test` | Playwright で例外操作を繰り返し、仕様/設計の逸脱を検出 | findings / スライド / 動画 / Issue |
| `yabaiyo` | 計画→コード精査で設計・実装の「ヤバい」箇所を収集 | findings / スライド / 動画 / Issue |
| `pr-review` | 特定の MR/PR を読み解き、インライン＋総括レビューを投稿 | review-notes / コメント / Issue |

新しいアイデアは `loops/_template/` をコピーするだけで追加できます（枠組みは共通、中身だけ差し替え）。

## 構成（移植しやすさ重視）

```
loop-engineering/
├── vendor/                 # 外部依存 (git submodule)
│   ├── open-ralph-wiggum/  # Ralph ループランナー
│   └── ecc/                # OpenCode向けエージェント/スキル/ルール
├── engine/                 # 共通実行エンジン（ループ切替・レポート・動画）
├── loops/                  # ループ定義（アイデア単位。引数で切替）
│   ├── _template/          # 新規ループのひな形
│   ├── monkey-test/
│   ├── yabaiyo/
│   └── pr-review/
├── project-config/         # ★プロジェクト固有の差し替えポイント
│   ├── target.yaml         # 対象パス・Issue先など（gitignore）
│   ├── agents/ skills/ rules/
├── setup/                  # セットアップスクリプト群
├── output/                 # 実行成果物（gitignore）
└── docs/                   # 詳細ドキュメント
```

- **差し替える場所**: ほぼ `project-config/` と `loops/<name>/` だけ
- **触らなくてよい場所**: `engine/`（共通枠組み）、`vendor/`（upstream）

## 5分クイックスタート

```bash
# 1. 依存確認 + submodule初期化
./setup/install.sh

# 2. LM Studio でモデルをロードし、ローカルサーバーを起動したうえで
./setup/configure-opencode.sh

# 3. 対象プロジェクトを指定
cp project-config/target.yaml.example project-config/target.yaml
# → target_path / repo_url / monkey_test_target_url などを編集

# 4. ECC資材の取り込み + 対象プロジェクトへ接続
./setup/sync-ecc-assets.sh --loop monkey-test
./setup/init-target-project.sh --target /path/to/your-project

# 5. プロンプト確認 → 実行
./engine/run-loop.sh --loop monkey-test --dry-run
./engine/run-loop.sh --loop monkey-test --target /path/to/your-project
```

別ターミナルで進捗確認:

```bash
cd /path/to/your-project && bun ../loop-engineering/vendor/open-ralph-wiggum/ralph.ts --status
# または対象プロジェクトで ralph がPATHにあれば: ralph --status
```

## ドキュメント

| ドキュメント | 内容 |
| --- | --- |
| [docs/SETUP.md](docs/SETUP.md) | セットアップ手順（もれなく・ダブりなく） |
| [docs/PORTING.md](docs/PORTING.md) | 他プロジェクトへの移植手順 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | ディレクトリ構成とデータの流れ |
| [docs/LOOPS.md](docs/LOOPS.md) | 同梱ループの説明と新規追加方法 |

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

## ライセンス

MIT（`LICENSE` を参照）。`vendor/` 配下は各 upstream のライセンスに従います。
