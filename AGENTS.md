# AGENTS.md — loop-engineering（tutttuwi）

人間とエージェントがこの基盤を直すときの約束。
ループ設計の用語は `vendor/cobusgreyling-loop-engineering/` を正の参考にする。

## ビルドと検証

```bash
./tests/smoke.sh
./setup/doctor.sh
./engine/run-loop.sh --loop yabaiyo --dry-run
```

実 Marp / 動画は CI に載せない。手元だけ:

```bash
./tests/e2e-report-video.sh
```

## 触ってよい場所

| 場所 | 役割 |
| --- | --- |
| `loops/` | ループアイデア（新規は `./setup/new-loop.sh`） |
| `project-config/` | 対象PJ固有の agents/skills/rules |
| `engine/` / `setup/` | 共通枠。回帰は `./tests/smoke.sh` |

`vendor/` は submodule。直接編集しない。upstream は `./setup/bootstrap-submodules.sh`。

## レビュー規範

- 同梱ループの既定は **L1（レポート専用）**。L3 を既定にしない
- 自動マージ経路を足さない。ホストは PR を merge しない
- `docs/primitives*.md` 相当の設計文書と `engine/lib/gate.sh` の変更は人間レビューを前提にする
- 失敗も [STATE.md](STATE.md) に残す（トークン浪費・誤完了・kill switch 発動）

## テスト

このリポジトリにアプリのテストスイートはない。品質ゲートは:

```bash
./tests/smoke.sh
```

`loop.yaml` を足したら `validate_loop_dir`（smoke 内の P5-5）が通ること。
