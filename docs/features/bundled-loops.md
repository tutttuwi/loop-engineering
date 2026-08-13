# 同梱ループ

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（枠組み + `security-audit` / `deps-audit` + P5-5 検証） |
| 関連実装 | `loops/monkey-test`, `loops/yabaiyo`, `loops/pr-review`, `loops/security-audit`, `loops/deps-audit`, `loops/_template`, `setup/new-loop.sh`, `validate_loop_dir`（`common.sh`） |
| 詳細 | [../LOOPS.md](../LOOPS.md) |

## 要件定義（共通）

1. 各ループは `loop.yaml` + `prompt.md` + `report-template.md` + `README.md` を持つ
2. 進捗を OUTPUT_DIR 上のファイルに残し、イテレーション再開可能であること。実行をまたぐ場合は `run-loop --resume`（[loop-runner.md](./loop-runner.md)）
3. 完了時に `<promise>{{COMPLETION_PROMISE}}</promise>` を出力するよう指示すること
4. Issue 投稿手順は `{{ISSUE_POST_INSTRUCTIONS}}` に従うこと
5. 新規ループは `_template` / `new-loop.sh` で追加できること

## ループ別契約

### monkey-test

| 項目 | 内容 |
| --- | --- |
| 目的 | Playwright で探索的例外操作、仕様/設計逸脱の検出 |
| 入力 | `monkey_test_target_url` |
| 進捗ファイル | `state.md`, `findings.md`, `screenshots/` |
| 成果 | report.md / narration / pdf / mp4 / Issue |
| 依存 MCP | playwright, github/gitlab |

### yabaiyo

| 項目 | 内容 |
| --- | --- |
| 目的 | 設計・実装の「ヤバい」不備の収集と報告 |
| 入力 | 対象ソース（cwd） |
| 進捗ファイル | `plan.md`, `findings.md` |
| 成果 | report / narration / pdf / mp4 / Issue |
| 依存 | architect / code-reviewer / security-reviewer 等 |

### pr-review

| 項目 | 内容 |
| --- | --- |
| 目的 | 特定 PR/MR のインライン＋総括レビューと Issue 記録 |
| 入力 | `pr_review_target`, issue モード |
| 進捗ファイル | `review-notes.md` |
| 成果 | PR コメント、任意 report、Issue |
| 依存 MCP | github/gitlab |

### security-audit

| 項目 | 内容 |
| --- | --- |
| 目的 | 対象コードのセキュリティ監査（OWASP・秘密情報・認証認可・依存関係） |
| 入力 | 対象ソース（cwd） |
| 進捗ファイル | `plan.md`, `findings.md` |
| 成果 | report / narration / pdf / mp4 / Issue |
| 依存 | security-reviewer / code-reviewer、security-review / production-audit |

### deps-audit

| 項目 | 内容 |
| --- | --- |
| 目的 | 依存関係・サプライチェーン監査（outdated・既知脆弱性ツール・lockfile衛生） |
| 入力 | 対象ソース（cwd） |
| 進捗ファイル | `plan.md`, `findings.md` |
| 成果 | report / narration / pdf / mp4 / Issue |
| 依存 | security-reviewer / code-reviewer、security-review / production-audit |

## 設計上の改善候補（実装は任意）

1. ~~初回シード~~ — **done**（下記「seed_files 契約」）
2. ~~deps-audit 専用ループ~~ — **done**（`loops/deps-audit/`）
3. 追加の製品ループは需要に応じて `_template` から追加

## seed_files 契約

`loop.yaml` の `seed_files`（カンマ区切り）で、run-loop 開始時にホストが OUTPUT_DIR 直下へ進捗スタブを作る。

| 規則 | 内容 |
| --- | --- |
| 配置 | `<target>/.loop-engineering/output/<loop>/<RUN_ID>/` 直下のみ |
| 名前 | 単純ファイル名（英数字・`._-`）。パス区切り / `..` / 絶対パスは拒否 |
| 既存 | 既にあるファイルは上書きしない（再開・手動編集を保護） |
| スタブ | `findings.md` / `plan.md` / `state.md` / `review-notes.md` は見出し付き。その他は汎用ヘッダ |
| 実装 | `ensure_seed_files`（`engine/lib/common.sh`）← `engine/run-loop.sh` |

同梱ループの設定例: monkey-test=`state.md,findings.md`、yabaiyo/security-audit/deps-audit=`plan.md,findings.md`、pr-review=`review-notes.md`。

## loop.yaml 検証（P5-5）

`validate_loop_dir`（`engine/lib/common.sh`）が必須キーと参照ファイルを検査する。`run-loop` / `new-loop.sh` から呼ばれ、壊れた yaml の黙デフォルトを早期検出する。

必須キー: `name`, `agent`, `max_iterations`, `min_iterations`, `completion_promise`, `prompt_file`, `report_template`  
参照: `prompt_file` / `report_template` の実ファイル存在

## 受け入れ条件（現状）

- [x] 同梱ループが dry-run でプロンプト展開できる（monkey-test / yabaiyo / pr-review / security-audit / deps-audit）
- [x] new-loop でひな形複製ができる
- [x] セキュリティ監査専用ループ（`security-audit`）を製品化
- [x] 依存関係監査専用ループ（`deps-audit`）を製品化
- [x] シードファイルで初回 Read 失敗を抑制（`seed_files` + `ensure_seed_files` + smoke）
- [x] `validate_loop_dir` + `new-loop.sh`→dry-run を smoke 固定（P5-5）
