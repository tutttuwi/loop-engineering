# Loop Constraints — loop-engineering

> ホスト (`engine/lib/gate.sh`) が毎実行のプロンプト先頭にこのファイルを埋め込みます。
> ここにある制約は **binding** です。エージェントは必ず従ってください。

## Push & Merge

- 対象アプリの `main` / デフォルトブランチへ自動マージしない
- L1 では対象アプリのソース・設定・lockfile を変更しない
- 変更を出す場合はドラフト PR。人間が ready にする

## Paths

- `.env` / `.env.*` / `secrets/` / `credentials/` / `*_key*` / `*_secret*` を編集しない
- `auth/` / `payments/` / `billing/` / `migrations/` / `.terraform/` / `k8s/production/` を自動編集しない
- 基盤の `vendor/` は submodule。直接編集しない

## Code

- テストを消して CI を緑にしない
- 無関係なリファクタを同梱しない（1実行1目的）
- 同一項目の自動修正は最大3回。超えたら STATE.md へエスカレーション
- フレークをタイムアウト延長やリトライ増だけで「修正」しない

## Communication

- Issue / PR を人間の承認なく close しない
- 秘密情報を findings / STATE / Issue / ログに書かない

## Budget / Kill switch

- `LOOP_PAUSE_ALL` または `.loop-pause` が有効ならホストが起動を拒否する
- トークンや実行回数が [loop-budget.md](loop-budget.md) の目安を超えたらレポート専用に落とすか停止する
