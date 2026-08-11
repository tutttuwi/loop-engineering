# ループランナー（run-loop / Ralph）

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（P0-4 `--status` 実装済み。Issue ゲートも run-loop に統合） |
| 関連実装 | `engine/run-loop.sh`, `engine/lib/render-prompt.sh`, `vendor/open-ralph-wiggum` |
| ロードマップ | P0-4 |

## 現状

### できること

- `--loop` で `loops/<name>/` を選択
- `target.yaml` / `--target` / `--target-config` / `--target-name` で対象解決
- プロンプト `{{VAR}}` 展開 → OUTPUT_DIR に保存
- Ralph（`--agent opencode`）で反復、`--completion-promise` で完了検知
- `--dry-run`, `--max-iterations`, `--min-iterations`, `--model`, `--extra`
- `--status` で対象プロジェクト上の Ralph 状態表示（`--loop` 不要）
- Issue モード `--issue-post-mode` / `--issue-target` / `--issue-fallback` / `--skip-issue-gate`
- `--post-report` / `--post-report-always`（[report-video-pipeline.md](./report-video-pipeline.md)）
- `loop.yaml` の `seed_files` で進捗スタブを OUTPUT_DIR に用意（[bundled-loops.md](./bundled-loops.md)）

### 完了判定

promise 文字列に加え、`require_issue` 時はホストが `issue-url.txt` を検証する（[issue-posting.md](./issue-posting.md)）。

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
