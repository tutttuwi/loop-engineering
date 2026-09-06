# Loop State — loop-engineering（tutttuwi）

Last run: (手動または今後の運用ループが更新)

このファイルは基盤リポジトリ自身の inbox です。対象PJの進捗は
`<target>/.loop-engineering/output/<loop>/<RUN_ID>/` 側に置きます。

スキーマは `vendor/cobusgreyling-loop-engineering/templates/STATE.md.template` に合わせています。

## High Priority (loop is acting or waiting on human)

- cobusgreyling 参考パターンのうち、まだ同梱ループになっていないもの（daily-triage / PR babysitter 等）は需要が出てから `_template` で追加する。勝手に L2/L3 化しない。

## Watch List

- `vendor/cobusgreyling-loop-engineering` の更新（`./setup/bootstrap-submodules.sh`）
- 同梱ループの L1 品質（誤完了・Issue ゲートすり抜け・ソース改変）

## Recent Noise (ignored this run)

- （まだ運用ループを回していない）

---
Run log: 対象PJ側は `<target>/.loop-engineering/loop-run-log.md`。本リポジトリの実行メタは各 `run-meta.json`。
