# Loop State — loop-engineering（tutttuwi）

Last run: 2026-09-06 — 日次 `max_runs_per_day` をホスト強制。参考パターンの L1 取り込みはここまで。

このファイルは基盤リポジトリ自身の inbox です。対象PJの進捗は
`<target>/.loop-engineering/output/<loop>/<RUN_ID>/` 側に置きます。

スキーマは `vendor/cobusgreyling-loop-engineering/templates/STATE.md.template` に合わせています。

## High Priority (loop is acting or waiting on human)

- （なし。ホスト側の cobusgreyling 安全装置は L1 契約まで取り込み済み。需要ベースの据え置きは Watch List 以下。）

## Watch List

- `vendor/cobusgreyling-loop-engineering` の更新（`./setup/bootstrap-submodules.sh`）
- 同梱ループの L1 品質（誤完了・Issue ゲートすり抜け・ソース改変）

## Parked (demand-based; timer `loop-cobusgreyling-best-practices` stopped)

ホストの機械的ゲート・プロンプト・L1 契約・観測性は一通り入った。残りは需要か L2 製品化が前提。

- cobusgreyling の `loop-audit` / `loop-gate` **CLI 再実装**（Python / `gate.sh` / `worktree_gate.py` で代替済み）
- daily-triage / PR babysitter / CI sweeper 等の **新製品ループ**（需要が出てから `_template`）
- L2 の **git worktree 分離**と **別プロセス verifier**（同梱は L1、Ralph は単一エージェント）
- 試行回数 ledger（L2 向け。L1 は日次 `max_runs_per_day` が相当）
- トークン実測 / `loop-cost` CLI（ローカル LLM では取得できないことが多い）
- サブエージェント spawn 上限のホスト強制（Ralph / OpenCode 側のフックが必要）

## Recent Noise (ignored this run)

- （まだ運用ループを回していない）

---
Run log: 対象PJ側は `<target>/.loop-engineering/loop-run-log.md`。本リポジトリの実行メタは各 `run-meta.json`。
