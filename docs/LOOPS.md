# ループカタログ

ループはすべて同じ枠組み（Ralph + 選択したエージェント + 成果物パイプライン）で動き、  
`./engine/run-loop.sh --loop <name>` の引数だけで切り替えます。エージェントは `--agent` / `target.yaml` の `agent`。

複数ループを併用する場合、ECC sync は使うループを **一度に** 指定してください（和集合で 1 マニフェスト）。

```bash
./setup/sync-ecc-assets.sh --loop monkey-test --loop yabaiyo --loop security-audit --loop deps-audit
# または ./setup/sync-ecc-assets.sh --all-loops
```

詳細は [features/ecc-sync.md](./features/ecc-sync.md)。

## 同梱ループ

### monkey-test — モンキーテストループ

| 項目 | 内容 |
| --- | --- |
| 目的 | ユーザー種別・アクセス権・構造とユースケースを解析し、多様なペルソナで業務フローと例外操作を検証 |
| 完了 promise | `MONKEY_TEST_COMPLETE` |
| 既定イテレーション | min 5 / max 25 |
| 主な入力 | `monkey_test_target_url` / 任意 `monkey_test_accounts` |
| 進捗ファイル | `state.md`, `app-model.md`, `scenarios.md`, `findings.md` |
| ECC資材 | e2e-runner, architect / e2e-testing, frontend-patterns, browser-qa / common, web |
| 補足スキル | `project-config/skills/persona-driven-qa`（ECC由来ではない。init で対象へコピー） |

詳細: [`loops/monkey-test/README.md`](../loops/monkey-test/README.md)

```bash
./setup/sync-ecc-assets.sh --loop monkey-test
./setup/init-target-project.sh --target /path/to/app
# または target.yaml の target_path があれば:
# ./setup/init-target-project.sh
./engine/run-loop.sh --loop monkey-test --target /path/to/app
```

### yabaiyo — ヤバイヨループ

| 項目 | 内容 |
| --- | --- |
| 目的 | 十分な計画のうえで設計・実装の不備を収集し、響く報告にする |
| 完了 promise | `YABAIYO_COMPLETE` |
| 既定イテレーション | min 3 / max 25 |
| ECC資材 | architect, code-reviewer, security-reviewer / architecture-decision-records, production-audit, agentic-engineering / common |

詳細: [`loops/yabaiyo/README.md`](../loops/yabaiyo/README.md)

```bash
./setup/sync-ecc-assets.sh --loop yabaiyo
./engine/run-loop.sh --loop yabaiyo --target /path/to/app
```

### pr-review — MR/PRレビューループ

| 項目 | 内容 |
| --- | --- |
| 目的 | 特定 MR/PR を読み解き、インライン＋総括レビューを投稿 |
| 完了 promise | `PR_REVIEW_COMPLETE` |
| 既定イテレーション | min 1 / max 8 |
| 主な入力 | `pr_review_target` / `issue_post_mode` / `issue_target` |
| ECC資材 | code-reviewer, security-reviewer / architecture-decision-records / common |

Issue投稿は既定で実行ごとに新規作成（`issue_post_mode: create`）。既存Issueへ追記する場合は `update` + `issue_target` を設定。

詳細: [`loops/pr-review/README.md`](../loops/pr-review/README.md)

```bash
./setup/sync-ecc-assets.sh --loop pr-review
./engine/run-loop.sh --loop pr-review --target /path/to/app
```

### security-audit — セキュリティ監査ループ

| 項目 | 内容 |
| --- | --- |
| 目的 | 対象コードのセキュリティ監査（OWASP・秘密情報・認証認可・依存関係） |
| 完了 promise | `SECURITY_AUDIT_COMPLETE` |
| 既定イテレーション | min 3 / max 20 |
| ECC資材 | security-reviewer, code-reviewer / security-review, production-audit / common |

一般の設計・実装品質の洗い出しは yabaiyo、本ループは悪用可能性に特化。

詳細: [`loops/security-audit/README.md`](../loops/security-audit/README.md)

```bash
./setup/sync-ecc-assets.sh --loop security-audit
./engine/run-loop.sh --loop security-audit --target /path/to/app
```

### deps-audit — 依存関係・サプライチェーン監査ループ

| 項目 | 内容 |
| --- | --- |
| 目的 | outdated・既知脆弱性ツール・lockfile衛生など依存関係に特化した監査 |
| 完了 promise | `DEPS_AUDIT_COMPLETE` |
| 既定イテレーション | min 2 / max 15 |
| ECC資材 | security-reviewer, code-reviewer / security-review, production-audit / common |

アプリコードの OWASP 全般は security-audit、本ループはマニフェスト / lock / 依存リスクに特化。

詳細: [`loops/deps-audit/README.md`](../loops/deps-audit/README.md)

```bash
./setup/sync-ecc-assets.sh --loop deps-audit
./engine/run-loop.sh --loop deps-audit --target /path/to/app
```

---

## 新規ループの追加

```bash
./setup/new-loop.sh my-new-loop
# 中身を編集
$EDITOR loops/my-new-loop/loop.yaml
$EDITOR loops/my-new-loop/prompt.md
$EDITOR loops/my-new-loop/report-template.md

./setup/sync-ecc-assets.sh --loop my-new-loop
./engine/run-loop.sh --loop my-new-loop --dry-run
./engine/run-loop.sh --loop my-new-loop --target /path/to/app
```

手動で行う場合:

```bash
cp -R loops/_template loops/my-new-loop
```

### 各ファイルの役割

同梱ループの既定自律度は **L1（レポート専用）** です。対象アプリのソースは変更しません。運用の正は [LOOP.md](../LOOP.md)、安全装置は [features/loop-safety.md](./features/loop-safety.md)。

| ファイル | 役割 |
| --- | --- |
| `loop.yaml` | 名前・イテレーション・完了promise・`autonomy_level`・`seed_files`・ECC取り込み一覧 |
| `prompt.md` | 毎イテレーション同じプロンプト（`{{VAR}}` 展開あり） |
| `report-template.md` | スライド構成の指針 |
| `README.md` | 人間向けの使い方 |

### prompt 設計のコツ（Ralph 向け）

1. **完了条件を検証可能にする**（Issue投稿済み・ファイル存在など）
2. **進捗を必ずファイルに残す**（次イテレーションの入力になる）
3. **1イテレーションで全部終わらせない前提**で書く
4. 最後に必ず `<promise>{{COMPLETION_PROMISE}}</promise>` を指示する
5. レポート生成コマンドは `{{ENGINE_ROOT}}/engine/lib/...` を使う（対象PJ内にステージされたパス）

利用可能なテンプレート変数は [`loops/_template/README.md`](../loops/_template/README.md) を参照。

---

## 成果物の共通パターン

どのループも最終的に次を目指します（必須ではないが推奨）:

```
<target>/.loop-engineering/output/<loop>/<RUN_ID>/
├── prompt.md          # 展開済みプロンプト
├── report-template.md # 実行開始時にコピーされたひな形
├── state.md / plan.md / review-notes.md / app-model.md / scenarios.md  # 進捗
├── findings.md        # 発見物
├── report.md          # Marp スライド原稿
├── narration.txt      # ナレーション（---`区切り）
├── slides/            # PNG
├── report.pdf
└── report.mp4
```

+ GitHub / GitLab Issue（MCP経由）

`.loop-engineering/` は `init-target-project.sh` / `run-loop.sh` が対象PJの `.gitignore` に追加します。