# アーキテクチャ

## 目的

「ループの枠組みは共通・アイデアは差し替え可能」な状態を保ちつつ、  
ローカルLLM上の OpenCode エージェントを Ralph ループで反復させ、  
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
│                              │         OpenCode CLI         │
│                              │         (agent=opencode)     │
│                              │              │               │
│  project-config/ ────────────┼──► 対象PJ/.opencode/         │
│   agents/skills/rules        │         loop-engineering/    │
│                              │         opencode.json        │
│                              ▼              │               │
│                         output/<loop>/<id>/ │               │
│                         findings, report,   │               │
│                         slides, mp4         │               │
└─────────────────────────────────────────────┼───────────────┘
                                              │
                    ┌─────────────────────────┼──────────────┐
                    ▼                         ▼              ▼
              LM Studio              Playwright MCP    GitHub/GitLab MCP
           (local OpenAI API)         (ブラウザ操作)      (Issue/レビュー)
```

## 実行時の流れ（1ループ）

1. `run-loop.sh` が `loops/<name>/loop.yaml` と `project-config/target.yaml` を読む
2. `prompt.md` の `{{VAR}}` を展開し `output/<loop>/<RUN_ID>/prompt.md` に保存
3. 対象プロジェクトを cwd にして `bun vendor/open-ralph-wiggum/ralph.ts` を起動
4. Ralph が同じプロンプトを OpenCode に繰り返し渡し、`<promise>...</promise>` を待つ
5. エージェントはファイル（`state.md` / `findings.md` 等）に進捗を残すため、次イテレーションで自己修正できる
6. 十分集まったら Marp → スライド/PDF、ffmpeg → 動画、MCP → Issue

## ディレクトリ責務

| ディレクトリ | 責務 | 変更頻度 |
| --- | --- | --- |
| `vendor/` | upstream（Ralph / ECC） | submodule update 時のみ |
| `engine/` | 実行・レポート・動画の共通枠 | 基盤改善時 |
| `loops/` | ループアイデア（引数で切替） | アイデア追加時 |
| `project-config/` | 対象PJ固有の接続情報とルール | **プロジェクトごと** |
| `setup/` | セットアップ自動化 | 基盤改善時 |
| `output/` | 実行成果物（gitignore） | 毎実行 |

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

**モデル**

1. `run-loop.sh --model`
2. 対象 / グローバルの `opencode.json` の `model`

## 設計上の制約（意図的）

- `loop.yaml` / `target.yaml` は **フラットな key: value のみ**（bash3.2 でも動く簡易パーサ）
- リストはカンマ区切り1行（`ecc_agents: a,b,c`）
- `vendor/` は直接編集しない（カスタムは `project-config/` へ）
