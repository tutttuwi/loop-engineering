# ループカタログ

ループはすべて同じ枠組み（Ralph + OpenCode + 成果物パイプライン）で動き、  
`./engine/run-loop.sh --loop <name>` の引数だけで切り替えます。

## 同梱ループ

### monkey-test — モンキーテストループ

| 項目 | 内容 |
| --- | --- |
| 目的 | 画面構成把握後、Playwright で例外操作を繰り返し逸脱を検出 |
| 完了 promise | `MONKEY_TEST_COMPLETE` |
| 既定イテレーション | min 3 / max 25 |
| 主な入力 | `monkey_test_target_url` |
| ECC資材 | e2e-runner, architect / e2e-testing, frontend-patterns, browser-qa / common, web |

詳細: [`loops/monkey-test/README.md`](../loops/monkey-test/README.md)

```bash
./setup/sync-ecc-assets.sh --loop monkey-test
./setup/init-target-project.sh --target /path/to/app
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
| 主な入力 | `pr_review_target` |
| ECC資材 | code-reviewer, security-reviewer / architecture-decision-records / common |

詳細: [`loops/pr-review/README.md`](../loops/pr-review/README.md)

```bash
./setup/sync-ecc-assets.sh --loop pr-review
./engine/run-loop.sh --loop pr-review --target /path/to/app
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

| ファイル | 役割 |
| --- | --- |
| `loop.yaml` | 名前・イテレーション・完了promise・ECC取り込み一覧 |
| `prompt.md` | 毎イテレーション同じプロンプト（`{{VAR}}` 展開あり） |
| `report-template.md` | スライド構成の指針 |
| `README.md` | 人間向けの使い方 |

### prompt 設計のコツ（Ralph 向け）

1. **完了条件を検証可能にする**（Issue投稿済み・ファイル存在など）
2. **進捗を必ずファイルに残す**（次イテレーションの入力になる）
3. **1イテレーションで全部終わらせない前提**で書く
4. 最後に必ず `<promise>{{COMPLETION_PROMISE}}</promise>` を指示する
5. レポート生成コマンドは `{{ENGINE_ROOT}}/engine/lib/...` を使う（移植後もパスが通る）

利用可能なテンプレート変数は [`loops/_template/README.md`](../loops/_template/README.md) を参照。

---

## 成果物の共通パターン

どのループも最終的に次を目指します（必須ではないが推奨）:

```
output/<loop>/<RUN_ID>/
├── prompt.md          # 展開済みプロンプト
├── state.md / plan.md / review-notes.md  # 進捗
├── findings.md        # 発見物
├── report.md          # Marp スライド原稿
├── narration.txt      # ナレーション（---`区切り）
├── slides/            # PNG
├── report.pdf
└── report.mp4
```

+ GitHub / GitLab Issue（MCP経由）
