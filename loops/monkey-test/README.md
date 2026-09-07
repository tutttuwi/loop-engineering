# モンキーテストループ

対象アプリの **ユーザー種別・アクセス権・情報構造** をドキュメントとソースから解析し、
ユースケース／業務フロー／利用パターンをカタログ化したうえで、
**多様なペルソナ**（ロール × 行動特性）として Playwright MCP で業務フローと例外操作を踏むループです。

ランダムクリックから入らず、分析 → カタログ → ペルソナ実行の順で進めます。

## 前提

- 対象アプリがローカルまたはアクセス可能なURLで起動していること
  (`project-config/target.yaml` の `monkey_test_target_url` に設定)
- 対象プロジェクトの `.opencode/opencode.json` に Playwright MCP が登録されていること
  (`./setup/init-target-project.sh` を実行すると自動で設定される)
- 複数ロールを実際にログインして試す場合は、**テスト用**アカウントを
  `monkey_test_accounts` に書くか、対象PJの docs / E2E fixtures / seed から発見できること
  （本番アカウントは使わない）

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

`min_iterations` の既定は 5 です（分析2フェーズ + 複数ペルソナ実行を急いで完了扱いにしないため）。

## テストアカウント（任意）

`target.yaml` はフラットな `key: value` のみなので、アカウントは1行のDSLで渡します。

```yaml
# カンマ区切り。各エントリは role または role|login|secret
# 値にカンマ・パイプ・# を含めないこと。本番アカウントは書かない。
monkey_test_accounts: guest,member|user@example.com|test-pass,admin|admin@example.com|test-pass
```

空のときは、エージェントが README / docs / E2E fixtures / seed / `.env.example` からテスト用アカウントを探します。
パスワードは findings / レポート / Issue / スクリーンショット注釈には出ません。

## 出力

`<target>/.loop-engineering/output/monkey-test/<RUN_ID>/` に以下が生成されます:

- `state.md`        : フェーズ進捗・解析済み画面・実施済み操作（ホストが `seed_files` で初回シード）
- `app-model.md`    : ユーザー種別・アクセス権マトリクス・画面/ルート構造
- `scenarios.md`    : ユースケース／業務フロー／ペルソナとテストカタログ
- `findings.md`     : 発見した問題の一覧
- `screenshots/`    : Playwrightで撮影したスクリーンショット
- `report.md`       : Marp形式のスライドレポート
- `report.pdf` / `slides/` : スライドのPDF・画像
- `report.mp4`      : ナレーション付き報告動画
- GitHub/GitLab Issue: 上記の要約が自動投稿される
