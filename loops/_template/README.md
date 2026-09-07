# _template ループ

新しいループのアイデアを追加するためのひな形です。**このディレクトリ自体は実行対象外**です。

## 新しいループを追加する手順

1. このディレクトリを `loops/<新しいループ名>/` としてコピーする

   ```bash
   cp -R loops/_template loops/my-new-loop
   ```

2. `loop.yaml` を編集する(名前、完了promise、`autonomy_level`、イテレーション数、`seed_files`、ECCから取り込む資材)
   - `autonomy_level`: `L1`(レポート専用・既定) / `L2`(最小修正) / `L3`(無人・`--allow-l3` 必須)
   - `seed_files`: OUTPUT_DIR 直下にホストが初回スタブを作る進捗ファイル(カンマ区切り)。既存は上書きしない
3. `prompt.md` を編集する(`{{VAR}}` プレースホルダーは `engine/run-loop.sh` が自動展開する)
4. `report-template.md` を編集する(生成させたいスライド構成の指針)
5. 必要なら `./setup/sync-ecc-assets.sh --loop my-new-loop` でECCから資材を取り込む
6. `./engine/run-loop.sh --loop my-new-loop --dry-run` でプロンプトを確認する
7. `./engine/run-loop.sh --loop my-new-loop --target <path>` で実行する
   - 前回 RUN から続ける場合: `./engine/run-loop.sh --loop my-new-loop --resume`

## 利用可能なテンプレート変数(`prompt.md` / `report-template.md` 内で使用可)

| 変数 | 内容 |
| --- | --- |
| `{{LOOP_NAME}}` | ループ名 |
| `{{TARGET_PATH}}` | 対象プロジェクトの絶対パス |
| `{{TARGET_NAME}}` | 対象プロジェクトの表示名 |
| `{{REPO_PROVIDER}}` | `github` または `gitlab` |
| `{{REPO_URL}}` | Issue投稿先リポジトリURL |
| `{{DEFAULT_BRANCH}}` | 対象プロジェクトの既定ブランチ |
| `{{RUN_ID}}` | 実行ID(タイムスタンプ) |
| `{{RUN_DATE}}` | 実行日時 |
| `{{OUTPUT_DIR}}` | このループ実行の出力ディレクトリ（`<target>/.loop-engineering/output/...`） |
| `{{ENGINE_ROOT}}` | 対象PJ内ランタイムルート（`<target>/.loop-engineering`。report/video スクリプトを同期済み） |
| `{{COMPLETION_PROMISE}}` | 完了を示すpromiseタグの中身 |
| `{{REPORT_TEMPLATE_PATH}}` | 出力ディレクトリ内にコピーされた report-template.md の絶対パス |
| `{{ISSUE_POST_MODE}}` | `create` または `update` |
| `{{ISSUE_TARGET}}` | update時の既存Issue番号/URL |
| `{{AGENT}}` | 実行エージェント (`opencode` / `claude-code` / `cursor-agent` 等) |
| `{{RESUME_FROM_RUN_ID}}` | `--resume` 時の元 RUN_ID（未指定時は空。ホストがプロンプト先頭にもバナーを挿入する） |
| `{{LOOP_AUTONOMY_LEVEL}}` | `L0`–`L3`（ホストが Loop Guardrails を prompt.md 先頭にも挿入する） |
| `{{MONKEY_TEST_TARGET_URL}}` | モンキーテスト対象URL |
| `{{MONKEY_TEST_ACCOUNTS}}` | モンキーテスト用アカウントDSL（`role` または `role|login|secret` のカンマ区切り。未設定時は空） |
| `{{PR_REVIEW_TARGET}}` | PR/MRレビュー対象 |
