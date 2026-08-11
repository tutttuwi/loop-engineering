# 同梱ループ

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（枠組み + `security-audit` 製品化）。個別アイデアの改善は継続 |
| 関連実装 | `loops/monkey-test`, `loops/yabaiyo`, `loops/pr-review`, `loops/security-audit`, `loops/_template`, `setup/new-loop.sh` |
| 詳細 | [../LOOPS.md](../LOOPS.md) |

## 要件定義（共通）

1. 各ループは `loop.yaml` + `prompt.md` + `report-template.md` + `README.md` を持つ
2. 進捗を OUTPUT_DIR 上のファイルに残し、イテレーション再開可能であること
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

## 設計上の改善候補（実装は任意）

1. **初回シード**: run-loop 開始時に空の `plan.md` / `findings.md` / `state.md` をホストが作成し、エージェントの「File not found」ノイズを減らす — `require_issue` / `seed_files` は loop.yaml で対応済み（ループごと）
2. 追加の製品ループ（deps-audit 専用など）は需要に応じて `_template` から追加

## 受け入れ条件（現状）

- [x] 同梱ループが dry-run でプロンプト展開できる（monkey-test / yabaiyo / pr-review / security-audit）
- [x] new-loop でひな形複製ができる
- [x] セキュリティ監査専用ループ（`security-audit`）を製品化
- [ ] （改善）シードファイルで初回 Read 失敗を消す — planned 小項目（ホスト側シードは一部実装済み）
