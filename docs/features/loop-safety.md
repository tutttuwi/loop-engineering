# ループ安全装置（L1–L3 / kill switch / denylist）

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（ホスト強制。参考は cobusgreyling パターン） |
| 関連実装 | `engine/lib/gate.sh`, `engine/lib/worktree_gate.py`, `engine/run-loop.sh`, `gate.yaml`, `loop-constraints.md`, `loop-budget.md`, `LOOP.md` |
| 参考 | `vendor/cobusgreyling-loop-engineering/`（`docs/safety.md`, `docs/anti-patterns.md`, `docs/loop-design-checklist.md`） |

## 現状

同梱ループは監査・レビューが主で、対象ソースを書き換える製品ループは無い。
それでもホストが次を強制する。

| 装置 | 動き |
| --- | --- |
| Kill switch | `LOOP_PAUSE_ALL` / `.loop-pause` で `run-loop` を起動前に拒否 |
| `autonomy_level` | `loop.yaml`。省略時 `L1`。`L3` は `--allow-l3` または `LOOP_ALLOW_L3=1` |
| ガードレール挿入 | レンダリング済み `prompt.md` 先頭に denylist・Maker/Checker・`loop-constraints.md` |
| 実行ログ | `<target>/.loop-engineering/loop-run-log.md` に1行追記（dry-run 含む） |
| Issue ゲート | 既存。promise だけでは完了にしない |
| worktree ゲート | Ralph 後にスナップショット比較。L0/L1 ソース改変と denylist はホスト失敗（`engine/lib/worktree_gate.py`） |
| 日次予算 | `loop-run-log.md` の本日本番回数 vs `max_runs_per_day`（既定 2） |

## 自律度

| レベル | 意味 | ホスト |
| --- | --- | --- |
| L0 | 文書のみ | 実行は可能だがプロンプトが「何も変えるな」と指示 |
| L1 | レポート専用（既定） | 対象ソース変更禁止を挿入 |
| L2 | 最小修正 + 人間/別検証 | 自己承認禁止・3回キャップを挿入 |
| L3 | 無人 | 明示フラグなしでは起動しない |

ロールアウトは L1 を観測してから上げる。チェックリストは参考 submodule の `docs/loop-design-checklist.md`。

## 要件

### FR-SAFE-1 Kill switch

`run-loop.sh`（`--status` / `--list-targets` 以外）は次のいずれかで終了コード 1。

- `LOOP_PAUSE_ALL` が true 系
- 基盤ルート `.loop-pause`
- 対象 `<target>/.loop-engineering/.loop-pause`

### FR-SAFE-2 自律度

- `autonomy_level` が不正なら `validate_loop_dir` / 起動が失敗
- L3 は許可フラグ必須
- `run-meta.json` に `autonomy_level` を書く

### FR-SAFE-3 ガードレール

dry-run でも `prompt.md` 先頭に Loop Guardrails があること（denylist・Maker/Checker・日次予算・`loop-constraints.md`）。

### FR-SAFE-4 実行ログ

対象ランタイムに append-only の markdown 表。失敗時も trap 経由の meta とは別に、起動できた RUN は1行残す。

### FR-SAFE-5 worktree ゲート

Ralph 実行の直前に対象ツリーの内容ハッシュを保存し、直後に比較する（`.loop-engineering/` / `.ralph/` / `node_modules/` / `.opencode/local/` / `.git/` は除外）。

| 条件 | 結果 |
| --- | --- |
| denylist ヒット（全レベル） | 終了コード 1、`worktree-violations.txt` |
| L0/L1 で除外以外のパスが変化 | 同上（`trigger: l1-source`） |
| L2/L3 で変化ファイル数が `gate.yaml` の `maxFiles` 超 | 同上（`trigger: max-files`） |

`--skip-worktree-gate` または `LOOP_SKIP_WORKTREE_GATE=1` でスキップ。dry-run では走らない（エージェント未実行）。

参考の判定順は `vendor/cobusgreyling-loop-engineering/tools/loop-gate`（denylist → maxFiles）。auto-merge allowlist はホストがマージしないため未実装。

### FR-SAFE-6 日次実行予算

本番実行（dry-run 以外）の直前に、対象 `<target>/.loop-engineering/loop-run-log.md` から **本日 UTC・同一ループ名・dry_run=false** の行数を数える。

| `max_runs_per_day` | 動き |
| --- | --- |
| 省略 | 2（`loop-budget.md` と同じ） |
| `0` | 無制限 |
| `N>=1` | 既存回数が N 以上なら終了コード 1（次の実行を拒否） |

`--skip-budget-gate` / `LOOP_SKIP_BUDGET_GATE=1` でスキップ。Ralph を起動した失敗（トークン消費済み）は回数に含める。日次予算・kill switch など起動前の拒否は `loop-run-log.md` に書かない。

## 非目標

- cobusgreyling の `loop-gate` / `loop-audit` CLI の再実装
- ホストによる git auto-merge
- トークン実測（ローカル LLM では取得できないことが多い）
