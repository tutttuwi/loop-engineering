# ループランナー（run-loop / Ralph）

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（P0-4 `--status` + P5-6 `run-meta.json` / 終了コード契約） |
| 関連実装 | `engine/run-loop.sh`, `engine/lib/render-prompt.sh`, `engine/lib/common.sh` (`write_run_meta_json` / `validate_loop_dir`), `vendor/open-ralph-wiggum` |
| ロードマップ | P0-4, P5-5, P5-6 |

## 現状

### できること

- `--loop` で `loops/<name>/` を選択
- `target.yaml` / `--target` / `--target-config` / `--target-name` で対象解決
- プロンプト `{{VAR}}` 展開 → OUTPUT_DIR に保存
- Ralph（`--agent opencode`）で反復、`--completion-promise` で完了検知
- `--dry-run`, `--max-iterations`, `--min-iterations`, `--model`, `--extra`
- `--status` で対象プロジェクト上の Ralph 状態表示（`--loop` 不要）
- `--list-targets` でレジストリ一覧
- Issue モード `--issue-post-mode` / `--issue-target` / `--issue-fallback` / `--skip-issue-gate`
- `--post-report` / `--post-report-always`（[report-video-pipeline.md](./report-video-pipeline.md)）
- `loop.yaml` の `seed_files` で進捗スタブを OUTPUT_DIR に用意（[bundled-loops.md](./bundled-loops.md)）
- `OUTPUT_DIR/run-meta.json`（loop / started_at / exit_code 等）
- 実行前に `validate_loop_dir`（必須キー・参照ファイル）

### 完了判定

promise 文字列に加え、`require_issue` 時はホストが `issue-url.txt` を検証する（[issue-posting.md](./issue-posting.md)）。

### 終了コード契約（ホスト）

| コード | 意味 |
| --- | --- |
| 0 | 成功（dry-run 含む。Issue ゲート通過 / skip / `require_issue=false`） |
| 1 | 引数・設定・ゲート・ポスト処理などのホスト側失敗 |
| その他 | Ralph（bun）の終了コードを伝播 |

## 要件定義（P0-4）— 実装済み

### FR-STATUS-1

`./engine/run-loop.sh --status` が、対象プロジェクト上の Ralph 実行状態を表示できること。

### FR-STATUS-2

対象パスの解決規則は通常実行と同じ（`--target` / `--target-config` / `--target-name` > `target.yaml`）。

### NFR

- bash 3.2 互換を維持
- submodule 未初期化時は既存と同様にエラーで案内

## 設計（実装メモ）

```bash
# run-loop.sh --status
# 1. target_path を解決
# 2. cd "$target_path"
# 3. bun "$RALPH_ENTRY" --status
```

promise 検知後のホスト検証（Issue / post-report）は `run-loop.sh` 末尾。

## 受け入れ条件

- [x] `--status` が動く
- [x] `usage()` とヘッダコメントが一致している
- [x] dry-run / 通常実行の回帰がない（smoke）
- [x] `run-meta.json` が OUTPUT_DIR に書かれ exit_code を記録する（P5-6 / smoke）
- [x] `--status` を smoke で固定（P5-6）
- [x] 終了コード契約が usage / 本書に記載される（P5-6）
