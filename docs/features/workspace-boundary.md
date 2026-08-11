# ワークスペース境界

| 項目 | 値 |
| --- | --- |
| ステータス | `done` |
| 関連実装 | `engine/run-loop.sh`, `engine/lib/common.sh`, `setup/init-target-project.sh` |
| 関連ドキュメント | [../ARCHITECTURE.md](../ARCHITECTURE.md) |

## 背景

OpenCode / Ralph は **対象プロジェクトを cwd** にして動く。エージェントの Read / Write / Bash は、既定でプロジェクト外パスを `external_directory` として拒否する。  
基盤リポジトリ側の `output/` に成果物を置くと、ループが「Tools: none / No file changes」で死ぬ（実害確認済み）。

## 要件定義

### 必須

1. エージェントが読む・書く成果物パスは、常に対象PJツリー内であること
2. エージェントが bash で呼ぶ `report.sh` / `video.sh` / `tts` も対象PJ内から実行可能であること
3. `report-template.md` も対象PJ内に存在すること（Read が境界外に出ない）
4. 成果物ディレクトリは対象PJの git 管理外であること（`.gitignore`）
5. 基盤リポジトリ直下の `output/` は互換用とし、実行の正としないこと

### 非機能

- ステージングは実行ごと（または init 時）に冪等であること
- 対象PJに余計なコミットが発生しないこと

## 設計（現状）

### ディレクトリ契約

```
<target>/
├── .opencode/                 # OpenCode 設定（init）
└── .loop-engineering/         # ランタイム（gitignore）
    ├── engine/lib/            # report/video/tts 同期先 = {{ENGINE_ROOT}}/engine/lib
    └── output/<loop>/<RUN_ID>/  # = {{OUTPUT_DIR}}
        ├── prompt.md
        ├── report-template.md
        └── ...
```

### 変数マッピング

| 変数 | 実体 |
| --- | --- |
| `OUTPUT_DIR` | `<target>/.loop-engineering/output/<loop>/<RUN_ID>/` |
| `ENGINE_ROOT` | `<target>/.loop-engineering`（基盤リポジトリルートではない） |
| `REPORT_TEMPLATE_PATH` | `{{OUTPUT_DIR}}/report-template.md` |

### 処理フロー

1. `ensure_loop_engineering_gitignore(target)` — `.loop-engineering/` を追記
2. `stage_engine_lib_into_target(target)` — `engine/lib` の必要ファイルをコピー
3. `mkdir` OUTPUT_DIR、report-template をコピー、prompt をレンダリング
4. `cd target && bun ralph.ts --prompt-file <OUTPUT_DIR>/prompt.md ...`

### 注意（既知の脆さ）

ステージ済み `common.sh` の `LOOP_ENGINEERING_ROOT` は、配置場所から見て `.loop-engineering` を指す。現状の report/video は `SCRIPT_DIR` 相対で動くため問題ないが、**基盤ルート参照をステージ済みスクリプトに足す場合は別途設計が必要**。

## 受け入れ条件

- [x] dry-run の `OUTPUT_DIR` / プロンプト内パスが対象PJ配下
- [x] エージェントが `plan.md` を Read/Write しても `external_directory` にならない
- [x] `.gitignore` に `.loop-engineering/` が追加される
