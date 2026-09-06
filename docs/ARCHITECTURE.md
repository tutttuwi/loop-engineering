# アーキテクチャ

## 目的

「ループの枠組みは共通・アイデアは差し替え可能」な状態を保ちつつ、  
OpenCode（ローカルLLM）または Claude Code / Cursor Agent CLI を Ralph ループで反復させ、  
検証可能な成果物（findings / スライド / 動画 / Issue）まで到達させる。

## コンポーネント関係

```
┌─────────────────────────────────────────────────────────────┐
│  loop-engineering                                           │
│                                                             │
│  loops/<name>/     アイデア定義 (prompt, loop.yaml, report) │
│        │                                                    │
│        ▼                                                    │
│  engine/run-loop.sh ──► prompt展開 ──► ralph (vendor/)      │
│                              │              │               │
│                              │              ▼               │
│                              │         OpenCode / Claude Code /        │
│                              │         Cursor Agent CLI                │
│                              │         (--agent で切替)                │
│                              │              │                          │
│  project-config/ ────────────┼──► 対象PJ/.opencode/  .claude/  .cursor/│
│   agents/skills/rules        │         loop-engineering/    │
│                              │         opencode.json        │
│                              ▼              │               │
│                     (ステージ)              │               │
│                     対象PJ/.loop-engineering/               │
│                       engine/lib/  output/<loop>/<id>/      │
│                       findings, report, slides, mp4         │
└─────────────────────────────────────────────┼───────────────┘
                                              │
                    ┌─────────────────────────┼──────────────┐
                    ▼                         ▼              ▼
         LM Studio / Claude / Cursor   Playwright MCP    GitHub/GitLab MCP
           (選択したエージェント)         (ブラウザ操作)      (Issue/レビュー)
```

## 実行時の流れ（1ループ）

1. `run-loop.sh` が `loops/<name>/loop.yaml` と `project-config/target.yaml` を読む
2. 対象PJの `.loop-engineering/` に engine/lib を同期し、`output/<loop>/<RUN_ID>/` を作成（`--resume` 時は前回 RUN の進捗をコピーしてからシード）
3. `prompt.md` の `{{VAR}}` を展開し、同ディレクトリの `prompt.md` に保存（`report-template.md` もコピー）
4. 対象プロジェクトを cwd にして `bun vendor/open-ralph-wiggum/ralph.ts --agent <resolved>` を起動
5. Ralph が同じプロンプトを OpenCode に繰り返し渡し、`<promise>...</promise>` を待つ
6. エージェントはファイル（`state.md` / `findings.md` 等）に進捗を残すため、次イテレーションで自己修正できる
7. 十分集まったら Marp → スライド/PDF、ffmpeg → 動画、MCP → Issue

## ディレクトリ責務

| ディレクトリ | 責務 | 変更頻度 |
| --- | --- | --- |
| `vendor/` | upstream（Ralph / ECC） | submodule update 時のみ |
| `engine/` | 実行・レポート・動画の共通枠 | 基盤改善時 |
| `engine/opencode/` | **未使用の参考テンプレ**（実生成は `setup/lib/build_target_opencode_config.py`） | 参照のみ |
| `loops/` | ループアイデア（引数で切替） | アイデア追加時 |
| `project-config/` | 対象PJ固有の接続情報とルール | **プロジェクトごと** |
| `setup/` | セットアップ自動化 | 基盤改善時 |
| `<target>/.loop-engineering/` | 実行時ランタイム＋成果物（対象PJの gitignore） | 毎実行 |

## ワークスペース境界（重要）

OpenCode / Claude Code / Cursor Agent / Ralph は **対象プロジェクトを cwd** にして動きます。エージェントの Read/Write/Bash は、既定でプロジェクト外パスを拒否します。

そのため次はすべて **対象PJ内** に置きます:

| パス | 内容 |
| --- | --- |
| `{{OUTPUT_DIR}}` | `<target>/.loop-engineering/output/<loop>/<RUN_ID>/` |
| `{{ENGINE_ROOT}}` | `<target>/.loop-engineering`（`engine/lib` を同期済み） |
| `{{REPORT_TEMPLATE_PATH}}` | `{{OUTPUT_DIR}}/report-template.md`（実行開始時にコピー） |

基盤リポジトリ直下の `output/` は互換用の空ディレクトリです（実成果物は使いません）。

## マルチエージェントの使い方

ECC 由来の subagent（`architect`, `e2e-runner`, `code-reviewer`, `security-reviewer` 等）を  
`init-target-project.sh` が対象の `opencode.json` に登録します。

各ループの `prompt.md` は「必要なら subagent に委譲してよい」と指示しています。  
OpenCode 側で複数エージェントを並列に使える場合は、計画フェーズと検証フェーズで役割分担してください。

Ralph の `--rotation` でモデルを切り替えることも可能です（`run-loop.sh --extra` 経由）。

```bash
./engine/run-loop.sh --loop yabaiyo \
  --extra '--rotation "opencode:lmstudio/model-a,opencode:lmstudio/model-b"'
```

## レポート / 動画パイプライン

| スクリプト | 入力 | 出力 |
| --- | --- | --- |
| `engine/lib/report.sh` | Marp Markdown | `slides/*.png`, `report.pdf` |
| `engine/lib/video.sh` | スライド画像 + `narration.txt` | `report.mp4` |
| `engine/lib/tts.sh` | テキスト | 音声（say / VOICEVOX / OpenAI / none） |

TTS 切替: `LOOP_TTS_ENGINE=say|voicevox|openai|none`

## 設定の優先順位

**対象パス**

1. `run-loop.sh --target`
2. `project-config/target.yaml` の `target_path`

**target.yaml ファイル自体**

1. `--target-config`
2. 環境変数 `LOOP_TARGET_CONFIG`
3. `project-config/target.yaml`

**モデル / エージェント**

1. `run-loop.sh --agent` / `--model`
2. `target.yaml` の `agent`
3. `loop.yaml` の `agent`（既定 `opencode`）
4. OpenCode のとき: 対象の `.opencode/opencode.json` の `model`（`init-target-project.sh`）
5. （任意）グローバル `~/.config/opencode/opencode.json`

詳細は [features/multi-agent.md](./features/multi-agent.md)。

## 設計上の制約（意図的）

- `loop.yaml` / `target.yaml` は **フラットな key: value のみ**（bash3.2 でも動く簡易パーサ）
- リストはカンマ区切り1行（`ecc_agents: a,b,c`）
- `vendor/` は直接編集しない（カスタムは `project-config/` へ）
