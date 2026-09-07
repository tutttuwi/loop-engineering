# Loop Budget — loop-engineering

同梱ループはローカル LLM 前提の L1 です。数字は目安。超えたら止めるか間隔を空ける。

## 1実行あたりの目安

| ループ | 既定 max iterations | 目安トークン/実行 | サブエージェント |
| --- | --- | --- | --- |
| monkey-test | 25 | 高（ブラウザ操作） | 0–2 |
| yabaiyo | 25 | 中〜高（コード精査） | 0–3 |
| pr-review | 8 | 中 | 0–2 |
| security-audit | 20 | 中 | 0–2 |
| deps-audit | 15 | 低〜中 | 0–1 |

## 上限

- 同一対象・同一ループ: 1日あたり本番実行は 2 回まで（dry-run は除外）
- サブエージェント spawn: 1実行あたり 3 まで
- 予算の 80% を超えたら L1 のまま止める。エージェントが `loop-budget.md` の数字を自分で上げてはならない

## 超過時

1. Kill switch（`LOOP_PAUSE_ALL=1` または `.loop-pause`）
2. 対象の `.loop-engineering/loop-run-log.md` に追記されていることを確認
3. [STATE.md](STATE.md) の High Priority に理由を残す

## Kill switch

- 環境変数: `LOOP_PAUSE_ALL=1`
- ファイル: 基盤ルート `.loop-pause`、または `<target>/.loop-engineering/.loop-pause`
- 解除は人間だけ。STATE.md に再開条件を書いてから消す
