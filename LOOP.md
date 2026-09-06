# LOOP.md — このリポジトリのループ運用

このファイルは **本基盤自身** をどう回すかの正です。
対象プロジェクト向けのループカタログは [docs/LOOPS.md](docs/LOOPS.md) を見てください。

パターンと用語は submodule [`vendor/cobusgreyling-loop-engineering`](https://github.com/cobusgreyling/loop-engineering) に合わせています（L1 レポート → L2 支援修正 → L3 無人、kill switch、STATE、予算）。

## 同梱ループの自律度

同梱ループはすべて **L1（レポート専用）** です。対象アプリのソースは変更せず、OUTPUT_DIR と Issue に残します。

| ループ | レベル | 完了の検証 | 備考 |
| --- | --- | --- | --- |
| `monkey-test` | L1 | findings + Issue (`require_issue`) | Playwright で探索。アプリコードは触らない |
| `yabaiyo` | L1 | findings + Issue | 設計・実装の不備収集 |
| `pr-review` | L1 | review-notes + Issue | レビュー投稿。マージしない |
| `security-audit` | L1 | findings + Issue | 認証・秘密情報は報告のみ |
| `deps-audit` | L1 | findings + Issue | lockfile を自動 bump しない |

L2（最小修正 + 別検証）や L3（無人）にする場合は `loop.yaml` の `autonomy_level` を上げ、L3 は `--allow-l3` が必要です。L1 を1週間も観測せず L3 にしないこと（参考: `vendor/cobusgreyling-loop-engineering/docs/loop-design-checklist.md`）。

## ホストが強制すること

`engine/run-loop.sh` が毎回:

1. **Kill switch** — `LOOP_PAUSE_ALL=1` / 基盤ルートの `.loop-pause` / 対象の `.loop-engineering/.loop-pause` があれば起動しない
2. **自律度** — `loop.yaml` の `autonomy_level`（省略時 L1）。L3 は明示許可が必要
3. **ガードレール挿入** — プロンプト先頭に denylist・Maker/Checker・制約（`loop-constraints.md`）
4. **実行ログ** — 対象の `.loop-engineering/loop-run-log.md` に1行追記
5. **Issue 完了ゲート** — `require_issue` 時は promise だけでは完了にしない

## Kill switch

```bash
export LOOP_PAUSE_ALL=1          # すべての run-loop を拒否
touch .loop-pause                # この基盤リポジトリ側
touch <target>/.loop-engineering/.loop-pause
```

解除はフラグ削除と `unset LOOP_PAUSE_ALL`。再開前に [STATE.md](STATE.md) を見て原因を残す。

## 予算と観測

- 上限の目安: [loop-budget.md](loop-budget.md)
- 機械的制約: [loop-constraints.md](loop-constraints.md) / [gate.yaml](gate.yaml)
- 実行履歴: 対象PJの `.loop-engineering/loop-run-log.md` と各 RUN の `run-meta.json`

## 人間ゲート（常に）

- 自動マージしない（`gate.yaml` の allowlist があってもホストはマージしない）
- denylist（秘密情報・認証・課金・本番インフラ）は自動編集しない
- 同一項目の自動修正は3回まで（L2 以上）。超えたら STATE.md の High Priority へ
- セキュリティ・依存関係の major・10ファイル超は人間

## 参考 submodule

```bash
./setup/bootstrap-submodules.sh
ls vendor/cobusgreyling-loop-engineering/{LOOP.md,docs/safety.md,docs/anti-patterns.md,patterns}
```

実装を足すときはまずそこのパターン（daily-triage / PR babysitter 等）と [docs/primitives.md](vendor/cobusgreyling-loop-engineering/docs/primitives.md) を見て、この基盤の `loops/_template` に落とす。
