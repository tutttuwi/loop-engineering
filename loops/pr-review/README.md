# MR/PRレビューループ

指定したMR/PRの差分・説明・CI結果を読み解き、code-reviewer/security-reviewerの
観点でレビューを行い、インラインコメント+総括コメントを投稿するループです。
他のループと異なり、通常はスライド/動画レポートを作らず、MR/PRへの直接コメントが
主な成果物です(重大な指摘が多い場合のみ任意でスライド化します)。

## 実行方法

```bash
# 1. 必要な資材をECCから取り込む(初回のみ)
./setup/sync-ecc-assets.sh --loop pr-review

# 2. 対象プロジェクトに接続設定を配置する(初回のみ)
./setup/init-target-project.sh --target /path/to/target-project --repo-provider github

# 3. project-config/target.yaml の pr_review_target にPR/MRのURLまたは番号を設定する

# 4. プロンプトの内容を確認する(任意)
./engine/run-loop.sh --loop pr-review --dry-run

# 5. 実行する
./engine/run-loop.sh --loop pr-review --target /path/to/target-project --max-iterations 8
```

## 出力

`output/pr-review/<RUN_ID>/` に `review-notes.md` (レビューメモ)が生成されます。
最終成果物はMR/PR本体へのコメントです。
