# 成果物ライフサイクル

| 項目 | 値 |
| --- | --- |
| ステータス | `planned` |
| 関連実装 | なし（出力は `<target>/.loop-engineering/output/<loop>/<RUN_ID>/`） |
| ロードマップ | P1-5 |

## 背景

毎回 RUN_ID（タイムスタンプ）でディレクトリが増える。スライド・動画を含むと肥大化し、どれが最新か分かりにくい。

## 要件定義（P1-5）

### FR-ART-1 一覧

```bash
./engine/list-runs.sh [--target ...] [--loop yabaiyo]
```

各 RUN のパス、更新時刻、主要成果物の有無（plan/findings/report.pdf/issue-url）を表示すること。

### FR-ART-2 最新リンク

実行成功時（または常に）:

```
<target>/.loop-engineering/output/<loop>/latest → <RUN_ID>/
```

相対 symlink 推奨。

### FR-ART-3 掃除

```bash
./engine/clean-runs.sh --loop yabaiyo --keep 5
./engine/clean-runs.sh --older-than 14d
```

- `latest` が指す先は削除しない
- dry-run モード必須

### FR-ART-4

対象外の基盤 `output/` は触らない（互換用空置き場）。

## 設計

### 配置

```
engine/list-runs.sh
engine/clean-runs.sh
```

または `engine/lib/artifacts.sh` + 薄いエントリ。

### latest 更新タイミング

`run-loop.sh` 末尾（Ralph 起動前でも可だが、成功後の方が安全）:

```bash
ln -sfn "$run_id" "${runtime_root}/output/${loop_name}/latest"
```

### メタデータ（任意）

`OUTPUT_DIR/run-meta.json` に loop / started / exit_code を書くと list が楽。

## 受け入れ条件

- [ ] list で複数 RUN が見える
- [ ] latest が最新 RUN を指す
- [ ] clean --keep 5 で古いものが消え、latest は残る
- [ ] clean --dry-run で削除しない
