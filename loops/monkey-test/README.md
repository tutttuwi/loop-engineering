# モンキーテストループ

フロントエンド/モバイルアプリの画面構成を把握したうえで、Playwright MCPを使って
ひたすら例外操作(不正入力・多重送信・ネットワーク遮断・権限外アクセス等)を試行し、
想定外の挙動や仕様/設計上の不備を検出して報告するループです。

## 前提

- 対象アプリがローカルまたはアクセス可能なURLで起動していること
  (`project-config/target.yaml` の `monkey_test_target_url` に設定)
- 対象プロジェクトの `.opencode/opencode.json` に Playwright MCP が登録されていること
  (`./setup/init-target-project.sh` を実行すると自動で設定される)

## 実行方法

```bash
# 1. 必要な資材をECCから取り込む(初回のみ)
#    他ループと併用する場合は使うループをすべて一度に指定
#    例: ./setup/sync-ecc-assets.sh --loop monkey-test --loop yabaiyo
./setup/sync-ecc-assets.sh --loop monkey-test

# 2. 対象プロジェクトに接続設定を配置する(初回のみ)
./setup/init-target-project.sh --target /path/to/target-project

# 3. プロンプトの内容を確認する(任意)
./engine/run-loop.sh --loop monkey-test --dry-run

# 4. 実行する
./engine/run-loop.sh --loop monkey-test --target /path/to/target-project --max-iterations 25

# 前回の操作記録・発見を続きから再開する
# ./engine/run-loop.sh --loop monkey-test --resume
```

## 出力

`<target>/.loop-engineering/output/monkey-test/<RUN_ID>/` に以下が生成されます:

- `state.md`        : 解析済み画面・実施済み操作の記録(ホストが `seed_files` で初回シード)
- `findings.md`     : 発見した問題の一覧(同上)
- `screenshots/`    : Playwrightで撮影したスクリーンショット
- `report.md`       : Marp形式のスライドレポート
- `report.pdf` / `slides/` : スライドのPDF・画像
- `report.mp4`      : ナレーション付き報告動画
- GitHub/GitLab Issue: 上記の要約が自動投稿される
