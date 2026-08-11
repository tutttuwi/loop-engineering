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
| [roadmap.md](./roadmap.md) | — | P0–P2 ロードマップと依存関係 |
| [workspace-boundary.md](./workspace-boundary.md) | `done` | 対象PJ cwd・`.loop-engineering` ステージング |
| [loop-runner.md](./loop-runner.md) | `done` | `run-loop`・Ralph・promise・dry-run・`--status` |
| [target-config.md](./target-config.md) | `done` | `target.yaml`・`--target-name` レジストリ（P1-2 / P2-4） |
| [opencode-init.md](./opencode-init.md) | `done` | init / configure・生成される設定（tmpl は参考のみ） |
| [ecc-sync.md](./ecc-sync.md) | `done` | ECC抽出・カスタム保護（マニフェスト） |
| [issue-posting.md](./issue-posting.md) | `done` | Issue create/update・完了ゲート・CLI代替 |
| [permissions-unattended.md](./permissions-unattended.md) | `done` | ヘッドレス向け permission プロファイル |
| [report-video-pipeline.md](./report-video-pipeline.md) | `partial` | Marp / ffmpeg / TTS（P1-3 / P2-2 / P2-3 done） |
| [doctor-and-setup.md](./doctor-and-setup.md) | `done` | doctor 強化・接続完了診断・TTS/Marp 案内 |
| [porting-and-update.md](./porting-and-update.md) | `done` | 移植・`update.sh` ワンショット更新 |
| [artifact-lifecycle.md](./artifact-lifecycle.md) | `done` | list-runs / clean-runs / latest |
| [bundled-loops.md](./bundled-loops.md) | `done` | monkey-test / yabaiyo / pr-review / security-audit |

## 読者別の読み方

- **これから実装する**: [roadmap.md](./roadmap.md) → 各 `planned` / `partial` 文書の「要件定義」「設計」
- **現状の動きを知る**: `done` / `partial` の「現状」節と [../ARCHITECTURE.md](../ARCHITECTURE.md)
- **移植・運用**: [porting-and-update.md](./porting-and-update.md) + [../PORTING.md](../PORTING.md)
