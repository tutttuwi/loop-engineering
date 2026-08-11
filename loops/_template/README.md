# _template ループ

新しいループのアイデアを追加するためのひな形です。**このディレクトリ自体は実行対象外**です。

## 新しいループを追加する手順

1. このディレクトリを `loops/<新しいループ名>/` としてコピーする

   ```bash
   cp -R loops/_template loops/my-new-loop
   ```

2. `loop.yaml` を編集する(名前、完了promise、イテレーション数、ECCから取り込む資材)
3. `prompt.md` を編集する(`{{VAR}}` プレースホルダーは `engine/run-loop.sh` が自動展開する)
4. `report-template.md` を編集する(生成させたいスライド構成の指針)
5. 必要なら `./setup/sync-ecc-assets.sh --loop my-new-loop` でECCから資材を取り込む
6. `./engine/run-loop.sh --loop my-new-loop --dry-run` でプロンプトを確認する
7. `./engine/run-loop.sh --loop my-new-loop --target <path>` で実行する

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
| `{{OUTPUT_DIR}}` | このループ実行の出力ディレクトリ |
| `{{ENGINE_ROOT}}` | loop-engineeringリポジトリのルート絶対パス |
| `{{COMPLETION_PROMISE}}` | 完了を示すpromiseタグの中身 |
| `{{REPORT_TEMPLATE_PATH}}` | report-template.md の絶対パス |
