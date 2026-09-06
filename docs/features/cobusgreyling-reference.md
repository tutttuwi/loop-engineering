# cobusgreyling/loop-engineering 参考 submodule

| 項目 | 値 |
| --- | --- |
| ステータス | `done` |
| パス | `vendor/cobusgreyling-loop-engineering` |
| upstream | https://github.com/cobusgreyling/loop-engineering |

## 何のためか

このリポジトリ（tutttuwi/loop-engineering）は Ralph + OpenCode の**実行基盤**。
cobusgreyling 側はパターンライブラリ（スケジュール、STATE、L1–L3、安全装置）。
実装の参考として submodule 化し、直接編集しない。

## まず読むファイル

| パス | 内容 |
| --- | --- |
| `LOOP.md` | 参考リポジトリ自身のループ運用 |
| `docs/primitives.md` | Scheduling / worktree / skills / MCP / maker-checker / state |
| `docs/loop-design-checklist.md` | 本番前チェックリスト |
| `docs/safety.md` / `docs/anti-patterns.md` | denylist・自己検証禁止・kill switch |
| `patterns/` | daily-triage, PR babysitter, CI sweeper 等 |
| `templates/` | STATE / budget / constraints / gate.yaml のひな形 |

## この基盤への写し方

| 参考コンセプト | このリポジトリ |
| --- | --- |
| L1–L3 | `loop.yaml` の `autonomy_level` + `engine/lib/gate.sh` |
| Kill switch | `LOOP_PAUSE_ALL` / `.loop-pause` |
| STATE.md | リポジトリルート（基盤自身）と各 RUN の `state.md` / `plan.md` |
| loop-constraints / gate.yaml | ルートの同名ファイル → プロンプト挿入 |
| loop-run-log | `<target>/.loop-engineering/loop-run-log.md` |
| 新しい仕事のパターン | `loops/_template` から同梱ループ化（需要ベース） |

更新:

```bash
./setup/bootstrap-submodules.sh
```
