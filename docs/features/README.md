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
| [loop-runner.md](./loop-runner.md) | `partial` | `run-loop.sh` / Ralph / promise / `--status` |
| [target-config.md](./target-config.md) | `partial` | `target.yaml`・マルチターゲット一貫性 |
| [opencode-init.md](./opencode-init.md) | `done` | init / configure・生成される設定 |
| [ecc-sync.md](./ecc-sync.md) | `partial` | ECC抽出・カスタム保護 |
| [issue-posting.md](./issue-posting.md) | `partial` | Issue create/update・完了ゲート・CLI代替 |
| [permissions-unattended.md](./permissions-unattended.md) | `planned` | ヘッドレス向け permission プロファイル |
| [report-video-pipeline.md](./report-video-pipeline.md) | `partial` | Marp / ffmpeg / TTS・ポスト処理 |
| [doctor-and-setup.md](./doctor-and-setup.md) | `partial` | doctor 強化・接続完了診断 |
| [porting-and-update.md](./porting-and-update.md) | `partial` | 移植・`update.sh` ワンショット更新 |
| [artifact-lifecycle.md](./artifact-lifecycle.md) | `planned` | 実行成果物の一覧・掃除・最新リンク |
| [bundled-loops.md](./bundled-loops.md) | `done` | monkey-test / yabaiyo / pr-review |

## 読者別の読み方

- **これから実装する**: [roadmap.md](./roadmap.md) → 各 `planned` / `partial` 文書の「要件定義」「設計」
- **現状の動きを知る**: `done` / `partial` の「現状」節と [../ARCHITECTURE.md](../ARCHITECTURE.md)
- **移植・運用**: [porting-and-update.md](./porting-and-update.md) + [../PORTING.md](../PORTING.md)
