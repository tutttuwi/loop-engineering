# deps-audit ループ

対象プロジェクトの**依存関係・サプライチェーン監査**に特化したループです。
outdated・既知脆弱性ツール・lockfile 衛生などを計画的に洗い出し、
重大度付きの findings・レポート・Issue を残します。

アプリコードの OWASP 全般（XSS・認証など）は [`security-audit`](../security-audit/) を使ってください。
本ループはマニフェスト / lock / 依存リスクに焦点を絞ります。

## 実行方法

```bash
# 1. 必要な資材をECCから取り込む(初回、または loop.yaml の ecc_* を変えたとき)
#    他ループと併用する場合は使うループをすべて一度に指定すること
#    例: ./setup/sync-ecc-assets.sh --loop deps-audit --loop security-audit
./setup/sync-ecc-assets.sh --loop deps-audit

# 2. 対象プロジェクトに接続設定を配置する(初回のみ)
./setup/init-target-project.sh --target /path/to/target-project

# 3. プロンプトの内容を確認する(任意)
./engine/run-loop.sh --loop deps-audit --dry-run

# 4. 実行する
./engine/run-loop.sh --loop deps-audit --target /path/to/target-project --max-iterations 15
```

## 出力

`<target>/.loop-engineering/output/deps-audit/<RUN_ID>/` に以下が生成されます:

- `plan.md`      : 監査計画と進捗（スタック検出・観点チェックリスト。ホストが `seed_files` で初回シード）
- `findings.md`  : 発見した依存リスク・衛生問題（重大度・該当パッケージ・推奨アクション。同上）
- `report.md` / `report.pdf` / `slides/` : スライドレポート
- `report.mp4`   : ナレーション付き報告動画
- GitHub/GitLab Issue: 上記の要約が自動投稿される

## ECC 資材

`loop.yaml` 既定:

| 種別 | 名前 |
| --- | --- |
| agents | `security-reviewer`, `code-reviewer` |
| skills | `security-review`, `production-audit` |
| rules | `common` |

未取り込みの場合は `./setup/sync-ecc-assets.sh --loop deps-audit` を実行してください。
`security-review` が vendor/ecc に無い・スキップされた場合でもループ定義はそのまま使え、
エージェントはルール `common` とマニフェスト/lock の読み取り・利用可能な audit CLI で進められます。

## カスタマイズのヒント

- 単一スタックに寄せる場合は prompt のチェックリストをそのマネージャだけに削るとよい
- CI で既に `npm audit` 等を回しているなら、prompt に「CI ログとの差分を見る」を追記する
- Issue を既存チケットへ追記する場合は `--issue-post-mode update --issue-target <n>`
