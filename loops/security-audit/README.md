# security-audit ループ

対象コードベースの**セキュリティ監査**に特化したループです。
秘密情報・認証認可・インジェクション・依存関係の既知脆弱性などを計画的に洗い出し、
重大度付きの findings・レポート・Issue を残します。

一般的な設計・実装品質の洗い出しは [`yabaiyo`](../yabaiyo/) を使ってください。
本ループは「悪用可能性」と「放置リスク」に焦点を絞ります。

## 実行方法

```bash
# 1. 必要な資材をECCから取り込む(初回、または loop.yaml の ecc_* を変えたとき)
#    ※ sync はマニフェスト上の ECC 由来を「今回指定分」に揃えるため、
#      複数ループを併用する場合は使う直前に再 sync するか、
#      --agents/--skills/--rules で和集合を指定する
./setup/sync-ecc-assets.sh --loop security-audit

# 2. 対象プロジェクトに接続設定を配置する(初回のみ)
./setup/init-target-project.sh --target /path/to/target-project

# 3. プロンプトの内容を確認する(任意)
./engine/run-loop.sh --loop security-audit --dry-run

# 4. 実行する
./engine/run-loop.sh --loop security-audit --target /path/to/target-project --max-iterations 20
```

## 出力

`<target>/.loop-engineering/output/security-audit/<RUN_ID>/` に以下が生成されます:

- `plan.md`      : 監査計画と進捗（観点チェックリスト）
- `findings.md`  : 発見した脆弱性・不備（重大度・該当箇所・修正方針）
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

未取り込みの場合は `./setup/sync-ecc-assets.sh --loop security-audit` を実行してください。
`security-review` が vendor/ecc に無い・スキップされた場合でもループ定義はそのまま使え、
エージェントはルール `common/security.md` と `security-reviewer` を主軸に監査できます。

## カスタマイズのヒント

- 言語固有のレビュアー（例: `python-reviewer`）を `ecc_agents` に追加してもよい
- 依存監査を厚くしたい場合は prompt のチェックリストにスタック固有コマンドを追記する
- Issue を既存チケットへ追記する場合は `--issue-post-mode update --issue-target <n>`
