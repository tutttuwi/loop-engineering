# ロードマップ

調査日: 2026-08-11  
対象: loop-engineering（OpenCode + Ralph + ECC、ローカル LLM）

## 現状サマリ

ポータブルな「隣置き基盤」の骨格と、P0–P5 の運用ギャップはおおむね埋まっている。

- setup → sync-ecc（マルチループ和集合）→ init → run-loop → 対象内成果物 → Marp/動画
- ワークスペース境界（`.loop-engineering/`）、`--status`、`update.sh`、Issue 完了ゲート、permission プロファイル、doctor（同梱ループ一覧 / PORTING 整合 / ステージ健全性）、smoke CI、成果物 list/clean、`security-audit` / `deps-audit` ループ
- P5: `--list-targets`、Issue CLI smoke、`update.sh` 受け入れ、loop 検証、`run-meta.json`、opt-in 実 Marp e2e

P0–P5 は完了。残る大きな発明は意図的に据え置き（下の「据え置き」参照）。

## 優先度定義

| 優先度 | 基準 |
| --- | --- |
| P0 | 移植して無人ループを回すときに止まる／嘘の完了になる |
| P1 | 運用摩擦が大きいが回避可能 |
| P2 | 品質・拡張・DX |
| P3 | 任意・後回し（動くがまだ薄い／需要待ち） |
| P4 | P3 後の薄い運用ギャップ（smoke / doctor 発見性など） |
| P5 | P4 後の受け入れ厚み・運用 DX・観測性（需要ベース・具体ギャップのみ） |

## P0（完了）

| ID | 機能 | 文書 | 状態 |
| --- | --- | --- | --- |
| P0-1 | 無人実行向け permission プロファイル | [permissions-unattended.md](./permissions-unattended.md) | **done** |
| P0-2 | Issue 完了ゲート + CLI フォールバック | [issue-posting.md](./issue-posting.md) | **done** |
| P0-3 | doctor「接続完了」診断 | [doctor-and-setup.md](./doctor-and-setup.md) | **done** |
| P0-4 | `run-loop.sh --status` | [loop-runner.md](./loop-runner.md) | **done** |

## P1（完了）

| ID | 機能 | 文書 | 状態 |
| --- | --- | --- | --- |
| P1-1 | `setup/update.sh` ワンショット更新 | [porting-and-update.md](./porting-and-update.md) | **done** |
| P1-2 | init の `--target-config` 対応 | [target-config.md](./target-config.md) | **done** |
| P1-3 | レポート/動画のポスト処理オプション | [report-video-pipeline.md](./report-video-pipeline.md) | **done** |
| P1-4 | sync 時のカスタム保護 + マルチループ和集合 | [ecc-sync.md](./ecc-sync.md) | **done** |
| P1-5 | 成果物ライフサイクル（list/clean） | [artifact-lifecycle.md](./artifact-lifecycle.md) | **done** |

## P2（完了）

| ID | 機能 | メモ |
| --- | --- | --- |
| P2-1 | エンジン smoke テスト / CI | **done** — `./tests/smoke.sh` / `.github/workflows/smoke.yml` |
| P2-2 | Linux 既定 TTS 自動選択 | **done** — `say` 不在時 `voicevox`/`none` |
| P2-3 | Marp バージョン固定の推奨明示 | **done** — doctor / docs |
| P2-4 | ターゲットレジストリ `targets/*.yaml` | **done** — [target-config.md](./target-config.md) |
| P2-5 | 未使用 `engine/opencode/opencode.json.tmpl` 整理 | **done** — 参考として保持 |
| P2-6 | 追加ループ製品化 | **done** — [`security-audit`](../../loops/security-audit/) |

## P3 / Remaining

実装済みの骨格に対する、真に残っている任意項目。

| ID | 項目 | メモ |
| --- | --- | --- |
| P3-1 | 細粒度 MCP permission | **done** — サーバ別 `mcp_permission_overrides` → `permission.<server>_*`（ツール単位 DSL は未対応。[permissions-unattended.md](./permissions-unattended.md) FR-PERM-4） |
| P3-2 | `deps-audit` 専用ループ | **done** — [`loops/deps-audit/`](../../loops/deps-audit/)。outdated・audit CLI・lockfile衛生に特化（[bundled-loops.md](./bundled-loops.md)） |
| P3-3 | report.md → Marp e2e 受け入れの厚み | **done** — fixture + stub npx で pin/`report.md`→pdf+slides/欠落スキップを smoke 固定。実 Chromium・TTS・フル動画は CI 外（[report-video-pipeline.md](./report-video-pipeline.md)） |
| P3-4 | 同梱ループのシード改善 | **done** — `ensure_seed_files`（型別スタブ・不正パス拒否・非上書き）+ smoke + [bundled-loops.md](./bundled-loops.md) |

**P3 完了**（2026-08-11）。ロードマップ上の P3 項目はすべて done。

**完了済み（参照用）**: マルチループ ECC sync（`--loop` × N / `--all-loops` / `update.sh` 経由の和集合）— [ecc-sync.md](./ecc-sync.md)


## P4（P3 後の薄いギャップ）

P3 完了後に残る、発明ではなく既知の回帰・発見性ギャップ。

| ID | 項目 | メモ |
| --- | --- | --- |
| P4-1 | `--all-loops` の smoke 固定 | **done** — 列挙に `deps-audit` を含み `_template` を除外、和集合スキルが揃うことを `./tests/smoke.sh` で検証（[ecc-sync.md](./ecc-sync.md)） |
| P4-2 | 成果物 list/clean の smoke | **done** — 偽 RUN ツリーで `list-runs`（latest `*`）/ `clean-runs --dry-run` / `--keep N` を `./tests/smoke.sh` で固定（[artifact-lifecycle.md](./artifact-lifecycle.md)） |
| P4-3 | doctor の同梱ループ一覧 | **done** — `doctor.sh` が `loops/*/loop.yaml` を列挙（`_template` 除外）。`./tests/smoke.sh` で既知ループを固定（[doctor-and-setup.md](./doctor-and-setup.md)） |
| P4-4 | doctor 未 init 受け入れの smoke | **done** — 未 init target（`.opencode/opencode.json` 不在）で ERROR + 非ゼロを `./tests/smoke.sh` で固定（[doctor-and-setup.md](./doctor-and-setup.md)） |

**P4 完了**（2026-08-11）。ロードマップ上の P4 項目はすべて done。

## P5（受け入れ厚み・運用 DX・観測性）

P0–P4 で骨格は揃ったあとに残っていた、**コード／文書で根拠のある**建設タスク。優先は需要と回帰リスクで選ぶ。

| ID | 項目 | スコープ（一行） | 状態 |
| --- | --- | --- | --- |
| P5-1 | 実 Marp/Chromium/TTS+動画 e2e（opt-in） | CI 外の手元スクリプトで fixture→実 `npx` Marp→（任意）ffmpeg/TTS フル動画を通す。stub smoke は維持 | **done** — `./tests/e2e-report-video.sh`（`--with-video` 任意） |
| P5-2 | ターゲットレジストリ発見 UX | `run-loop` / `doctor` / `init` / `update` で `--list-targets`（`list_target_registry_names` 公開）。sync `--list` と対称 | **done** |
| P5-3 | Issue CLI フォールバックの smoke | stub `gh`/`glab` で `issue.sh` create/comment と `run-loop --issue-fallback cli` 経路を固定 | **done** — `./tests/smoke.sh` |
| P5-4 | `update.sh` オーケストレーション受け入れ | 一時 target で sync→init→doctor→`--dry-run-loop` を smoke（`--pull` 無し）。STEP 失敗で非ゼロも固定 | **done** — `./tests/smoke.sh` |
| P5-5 | ループ作成 DX（検証 + new-loop 回帰） | `loop.yaml` 必須キー／参照ファイル存在チェック + `new-loop.sh`→dry-run を smoke | **done** — `validate_loop_dir` |
| P5-6 | 実行メタ / 終了コード契約 | `OUTPUT_DIR/run-meta.json`（loop / started / exit_code 等）とホスト終了コードの文書化。`--status` の smoke も | **done** |
| P5-7 | doctor ↔ PORTING 整合 | PORTING チェックリスト未カバー（`.gitignore` に `.loop-engineering/`、sync/init 痕跡の薄い WARN 等）を doctor に寄せ | **done** |
| P5-8 | ランタイム gitignore / ステージ健全性 | 対象 `.gitignore` の取りこぼし検出、`.loop-engineering` が追跡されていないことの doctor WARN、ステージコピーと基盤の乖離検査 | **done** |

**P5 完了**（2026-08-11）。ロードマップ上の P5 項目はすべて done。

**据え置き（P5 に入れない）**:

- ツール単位 MCP permission DSL（OpenCode 表現に依存・[permissions-unattended.md](./permissions-unattended.md) 非目標）
- CI ジョブでの実 Chromium / 実 TTS / フル動画（環境差・時間。P5-1 は手元 opt-in のみ）
- Windows ネイティブ対応スクリプト（README 前提は macOS/Linux 系ツール列。需要が出てから）
- 需要のない新規製品ループ（`_template` / `new-loop.sh` で十分）
- ステージ済み script への `LOOP_ENGINEERING_ROOT` 参照の全面再設計（[workspace-boundary.md](./workspace-boundary.md) の既知メモ。今の report/video は `SCRIPT_DIR` 相対で足りる）

関連: [report-video-pipeline.md](./report-video-pipeline.md)・[target-config.md](./target-config.md)・[issue-posting.md](./issue-posting.md)・[porting-and-update.md](./porting-and-update.md)・[bundled-loops.md](./bundled-loops.md)・[artifact-lifecycle.md](./artifact-lifecycle.md)・[doctor-and-setup.md](./doctor-and-setup.md)・[workspace-boundary.md](./workspace-boundary.md)・[loop-runner.md](./loop-runner.md)

## 推奨実装順（履歴）

```mermaid
flowchart LR
  P0_1[P0-1 permissions] --> P0_2[P0-2 issue gate]
  P0_3[P0-3 doctor]
  P0_4[P0-4 status]
  P0_3 --> P1_1[P1-1 update.sh]
  P1_2[P1-2 target-config]
  P1_3[P1-3 post-report]
  P1_4[P1-4 sync protect]
  P1_5[P1-5 artifacts]
```

P0–P5 は完了。新ループは `_template` / `new-loop.sh`。据え置きは上表の「据え置き」を参照。

## 完了の定義（マイルストーン）

### M1: Unattended Ready

- [x] ループを対話なしで完走できる permission プロファイルがある
- [x] Issue 未投稿のまま promise で「完了」にならない
- [x] `doctor` が target / init / token 不足を WARN/ERROR で出す
- [x] `--status` が動く

### M2: Ops Ready

- [x] `update.sh` で pull→sync→init→doctor が一発
- [x] init と run-loop が同じ target-config 解決規則
- [x] エージェントが Marp を飛ばしても `--post-report` で救済可能
- [x] カスタム rules が sync で不意に消えない
- [x] 複数ループの ECC 和集合 sync（`--loop` × N / `--all-loops`）

### M3: Quality

- [x] smoke CI（`./tests/smoke.sh` / `.github/workflows/smoke.yml`）
- [x] 成果物の list/clean（`list-runs` / `clean-runs`）
- [x] TTS / Marp の環境差が doctor で案内される
- [x] 未使用 `engine/opencode/opencode.json.tmpl` の整理（参考 README）
- [x] ターゲットレジストリ（`--target-name` / `targets/*.yaml`）
- [x] 追加ループ製品化（`security-audit` / `deps-audit`）

### M4: Acceptance / Ops DX（P5）

- [x] opt-in 実 Marp e2e（`./tests/e2e-report-video.sh`；CI は stub smoke 維持）
- [x] `--list-targets`（run-loop / doctor / init / update）
- [x] Issue CLI フォールバックの smoke（stub gh + `--issue-fallback cli`）
- [x] `update.sh` オーケストレーション受け入れ（STEP 失敗含む）
- [x] `validate_loop_dir` + `new-loop.sh` 回帰
- [x] `run-meta.json` / 終了コード契約 / `--status` smoke
- [x] doctor ↔ PORTING（gitignore / sync 痕跡 / lmstudio）
- [x] ステージ健全性（追跡 WARN・基盤との乖離）
