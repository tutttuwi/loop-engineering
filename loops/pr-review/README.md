# MR/PRレビューループ

指定したMR/PRの差分・説明・CI結果を読み解き、code-reviewer/security-reviewerの
観点でレビューを行い、インラインコメント+総括コメントを投稿するループです。
あわせてレビュー結果を GitHub/GitLab の **Issue** に記録します。

## Issue投稿モード

`project-config/target.yaml`（または実行時フラグ）で切り替えます。

| モード | 設定 | 動作 |
| --- | --- | --- |
| `create`（既定） | `issue_post_mode: create` | **ループ実行ごとに新規Issueを作成**（チケット番号を新規払い出し）。URLを `.loop-engineering/output/.../issue-url.txt` に保存 |
| `update` | `issue_post_mode: update` + `issue_target: <番号orURL>` | **指定した既存Issueへコメント追記** |

```yaml
# target.yaml 例
issue_post_mode: create
issue_target:

# 既存チケットへ追記する場合
# issue_post_mode: update
# issue_target: 42
# または
# issue_target: https://github.com/your-org/your-repo/issues/42
```

実行時上書き:

```bash
# 毎回新規Issue
./engine/run-loop.sh --loop pr-review --issue-post-mode create

# 特定Issueへ追記
./engine/run-loop.sh --loop pr-review --issue-post-mode update --issue-target 42
```

## 実行方法

```bash
# 1. 必要な資材をECCから取り込む(初回のみ)
./setup/sync-ecc-assets.sh --loop pr-review

# 2. 対象プロジェクトに接続設定を配置する(初回のみ)
./setup/init-target-project.sh --target /path/to/target-project --repo-provider github

# 3. project-config/target.yaml を設定
#    - pr_review_target: レビュー対象のPR/MR
#    - issue_post_mode / issue_target: 結果のIssue投稿先

# 4. プロンプトの内容を確認する(任意)
./engine/run-loop.sh --loop pr-review --dry-run

# 5. 実行する
./engine/run-loop.sh --loop pr-review --target /path/to/target-project --max-iterations 8
```

## 出力

`<target>/.loop-engineering/output/pr-review/<RUN_ID>/` に以下が生成されます。

- `review-notes.md` … レビューメモ
- `issue-url.txt` … 作成または追記したIssueのURL
- （任意）`report.md` / `slides/` … 重大指摘が多い場合のスライド
