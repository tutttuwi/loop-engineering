# 機能カタログ（要件定義・設計）

このディレクトリは、loop-engineering で **実装済み／部分実装／これから実装すべき** 機能の要件定義と設計書をまとめたものです。  
セットアップ手順そのものは [../SETUP.md](../SETUP.md)、移植手順は [../PORTING.md](../PORTING.md)、全体構造は [../ARCHITECTURE.md](../ARCHITECTURE.md) を参照してください。

## ステータス凡例

| 記号 | 意味 |
| --- | --- |
| `done` | 本番利用可能な実装あり |
| `partial` | 動くがギャップ・脆さあり（本書で改善要件を定義） |
| `planned` | 未実装。要件・設計のみ |

優先度の追跡は [roadmap.md](./roadmap.md) を正とします。

## 索引

| 文書 | ステータス | 概要 |
| --- | --- | --- |
| [roadmap.md](./roadmap.md) | — | P0–P5 完了。据え置きは roadmap の「据え置き」参照 |
| [workspace-boundary.md](./workspace-boundary.md) | `done` | 対象PJ cwd・`.loop-engineering` ステージング・健全性（P5-8） |
| [loop-runner.md](./loop-runner.md) | `done` | `run-loop`・Ralph・promise・dry-run・`--status`・`run-meta.json`・`--resume` |
| [target-config.md](./target-config.md) | `done` | `target.yaml`・`--target-name` / `--list-targets`（P2-4 / P5-2） |
| [opencode-init.md](./opencode-init.md) | `done` | init / configure・生成される設定（tmpl は参考のみ） |
| [ecc-sync.md](./ecc-sync.md) | `done` | ECC抽出・カスタム保護・マルチループ和集合 |
| [issue-posting.md](./issue-posting.md) | `done` | Issue create/update・完了ゲート・CLI代替（P5-3 smoke） |
| [permissions-unattended.md](./permissions-unattended.md) | `done` | ヘッドレス向け permission（一括 + サーバ別） |
| [report-video-pipeline.md](./report-video-pipeline.md) | `done` | Marp / `--post-report` smoke + opt-in 実 e2e（P5-1） |
| [doctor-and-setup.md](./doctor-and-setup.md) | `done` | doctor・PORTING 整合（P5-7）・ステージ健全性（P5-8） |
| [porting-and-update.md](./porting-and-update.md) | `done` | 移植・`update.sh`（P5-4 smoke） |
| [artifact-lifecycle.md](./artifact-lifecycle.md) | `done` | list-runs / clean-runs / latest（P4-2 smoke） |
| [bundled-loops.md](./bundled-loops.md) | `done` | 同梱ループ + `validate_loop_dir` / new-loop（P5-5） |

## 読者別の読み方

- **拡張の種を探す**: [roadmap.md](./roadmap.md)（P0–P5 完了 / 据え置きメモ）と各文書の残ギャップ・需要メモ
- **現状の動きを知る**: `done` / `partial` の「現状」節と [../ARCHITECTURE.md](../ARCHITECTURE.md)
- **移植・運用**: [porting-and-update.md](./porting-and-update.md) + [../PORTING.md](../PORTING.md)
