# ヤバイヨループ

十分な調査計画を立てたうえでソースコードを読み解き、設計・実装上の不備を
ひたすら収集し、最終的に「何が具体的に問題で、ベストプラクティスは何か」を
ユーザーに響く形で報告するループです。

## 実行方法

```bash
# 1. 必要な資材をECCから取り込む(初回のみ)
./setup/sync-ecc-assets.sh --loop yabaiyo

# 2. 対象プロジェクトに接続設定を配置する(初回のみ)
./setup/init-target-project.sh --target /path/to/target-project

# 3. プロンプトの内容を確認する(任意)
./engine/run-loop.sh --loop yabaiyo --dry-run

# 4. 実行する
./engine/run-loop.sh --loop yabaiyo --target /path/to/target-project --max-iterations 25

# 前回の調査を続きから再開する
# ./engine/run-loop.sh --loop yabaiyo --resume
# ./engine/list-runs.sh --loop yabaiyo
```

## 出力

`<target>/.loop-engineering/output/yabaiyo/<RUN_ID>/` に以下が生成されます:

- `plan.md`      : 調査計画と進捗(ホストが `seed_files` で初回シード)
- `findings.md`  : 発見した不備の一覧(重大度・該当箇所・ベストプラクティス付き。同上)
- `report.md` / `report.pdf` / `slides/` : スライドレポート
- `report.mp4`   : ナレーション付き報告動画
- GitHub/GitLab Issue: 上記の要約が自動投稿される

## カスタマイズのヒント

- `loop.yaml` の `ecc_agents` / `ecc_skills` を変更すると、使用するサブエージェントや
  参照ナレッジを差し替えられます(例: 特定言語のレビュアーを追加する等)
- `prompt.md` の観点リスト(アーキテクチャ/セキュリティ/パフォーマンス等)は
  プロジェクトの技術スタックに応じて自由に編集してください
