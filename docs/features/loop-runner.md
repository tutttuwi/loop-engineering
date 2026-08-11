# ループランナー（run-loop / Ralph）

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（P0-4 `--status` 実装済み。Issue ゲートも run-loop に統合） |
| 関連実装 | `engine/run-loop.sh`, `engine/lib/render-prompt.sh`, `vendor/open-ralph-wiggum` |
| ロードマップ | P0-4 |

## 現状

### できること

- `--loop` で `loops/<name>/` を選択
- `target.yaml` / `--target` / `--target-config` で対象解決
- プロンプト `{{VAR}}` 展開 → OUTPUT_DIR に保存
- Ralph（`--agent opencode`）で反復、`--completion-promise` で完了検知
- `--dry-run`, `--max-iterations`, `--min-iterations`, `--model`, `--extra`
- Issue モード `--issue-post-mode` / `--issue-target`

### ギャップ

| 約束 | 実態 |
| --- | --- |
| ヘッダコメントの `run-loop.sh --status` | **未実装**（引数パースに無し） |
| README の status 案内 | Ralph を直接叩く手順のみ実質有効 |
| 完了判定 | promise 文字列のみ。成果物チェックなし（→ Issue 文書） |

## 要件定義（P0-4）

### FR-STATUS-1

`./engine/run-loop.sh --status` が、対象プロジェクト上の Ralph 実行状態を表示できること。

### FR-STATUS-2

対象パスの解決規則は通常実行と同じ（`--target` > `target.yaml` の `target_path`）。

### FR-STATUS-3（代替許容）

実装コストが高い場合、ヘッダ・README・SETUP から `--status` 約束を削除し、Ralph 直接呼び出しに統一してもよい。ただし「どちらか一方」に揃えること。

### NFR

- bash 3.2 互換を維持
- submodule 未初期化時は既存と同様にエラーで案内

## 設計

### 推奨案 A: 薄いラッパー（推奨）

```bash
# run-loop.sh に --status 分岐を追加
# 1. target_path を解決
# 2. cd "$target_path"
# 3. bun "$RALPH_ENTRY" --status
```

- 追加依存なし
- ユーザは常に `run-loop.sh` 経由で操作できる

### 案 B: 文書削除

- `run-loop.sh` ヘッダ、README、SETUP の `--status` 記述を削除
- 進捗確認は `cd <target> && bun <ralph.ts> --status` のみ

### 完了ゲートとの関係（将来）

promise 検知後にホスト側で次を検証する拡張ポイントを `run-loop.sh` 末尾に置く（実装は [issue-posting.md](./issue-posting.md)）:

1. `issue-url.txt` 存在（ループが要求する場合）
2. 任意で `--post-report`（[report-video-pipeline.md](./report-video-pipeline.md)）

## 受け入れ条件

- [ ] `--status` が動く **または** 全ドキュメントから約束が消えている
- [ ] `usage()` とヘッダコメントが一致している
- [ ] dry-run / 通常実行の回帰がない
