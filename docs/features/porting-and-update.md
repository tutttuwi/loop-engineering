# 移植とアップデート

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（P1-1 `update.sh` 実装済み） |
| 関連実装 | `setup/update.sh`, README / [../PORTING.md](../PORTING.md), setup 各スクリプト |
| ロードマップ | P1-1 |

## 現状

### 移植パターン

- A. 隣に置く（推奨）
- B. 対象の submodule
- C. テンプレとして fork

差し替えポイントは主に `project-config/`。詳細は [../PORTING.md](../PORTING.md)。

### 更新

`./setup/update.sh` で pull（任意）→ submodule → sync → init → doctor → dry-run（任意）を一発実行できる。  
手動手順（A→D）も README / PORTING に残している。

複数ループ併用時は `--loop` を複数渡すか `--all-loops` で **1 回の和集合 sync**（[ecc-sync.md](./ecc-sync.md)）。

## 要件定義（P1-1）— 実装済み

### FR-UPD-1

`./setup/update.sh` が次を順に実行できること。

1. （オプション）`git pull` — `--pull` で on（既定オフ）
2. `bootstrap-submodules.sh` または同等の submodule 更新
3. 指定ループの `sync-ecc-assets.sh`（複数 `--loop` は **1 回の和集合 sync**）
4. `init-target-project.sh`（同じ target-config 解決）
5. `doctor.sh`
6. （オプション）`run-loop.sh --dry-run --loop <name>`（`--dry-run-loop`）

### FR-UPD-2

失敗したステップで止まり、どのステップかを明示すること。

### FR-UPD-3

`project-config/target.yaml` やユーザー local rules を git pull / sync で消さないこと。

### FR-UPD-4

README の更新節から `update.sh` を案内すること。

## 設計

### CLI

```bash
./setup/update.sh \
  --pull \
  --loop yabaiyo --loop monkey-test \
  --mcp-permission allow \
  --dry-run-loop yabaiyo
```

### 内部

薄いオーケストレータ。新規ロジックは既存スクリプトへ委譲。

```
update.sh
  → bootstrap-submodules.sh
  → sync-ecc-assets.sh (--loop ... をまとめて1回 / または --all-loops)
  → init-target-project.sh
  → doctor.sh
  → run-loop.sh --dry-run
```

## 受け入れ条件

- [x] 1 コマンドで sync+init+doctor まで完了できる
- [x] 途中失敗で非ゼロ
- [x] README / PORTING からリンクされる
