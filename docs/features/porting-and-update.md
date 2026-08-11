# 移植とアップデート

| 項目 | 値 |
| --- | --- |
| ステータス | `partial` |
| 関連実装 | README 手動手順, `docs/PORTING.md`, setup 各スクリプト |
| ロードマップ | P1-1 |

## 現状

### 移植パターン

- A. 隣に置く（推奨）
- B. 対象の submodule
- C. テンプレとして fork

差し替えポイントは主に `project-config/`。詳細は [../PORTING.md](../PORTING.md)。

### 更新

README に手動 A→D（pull → submodule → sync → init → doctor → dry-run）があるが、**ワンショットスクリプトは未実装**。

## 要件定義（P1-1）

### FR-UPD-1

`./setup/update.sh` が次を順に実行できること。

1. （オプション）`git pull` — フラグで on/off。既定はオフでも可（破壊的なため）
2. `bootstrap-submodules.sh` または `git submodule update --init --recursive`
3. 指定ループの `sync-ecc-assets.sh`（複数 `--loop` 可）
4. `init-target-project.sh`（同じ target-config 解決）
5. `doctor.sh`
6. （オプション）`run-loop.sh --dry-run --loop <name>`

### FR-UPD-2

失敗したステップで止まり、どのステップかを明示すること。

### FR-UPD-3

`project-config/target.yaml` やユーザー local rules を git pull で消さないこと（gitignore / sync 保護と整合）。

### FR-UPD-4

README の更新節から `update.sh` を案内すること。

## 設計

### CLI 案

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
  → sync-ecc-assets.sh (loop...)
  → init-target-project.sh
  → doctor.sh
  → run-loop.sh --dry-run
```

### submodule 配置時

`--target` を必須または yaml から解決。作業ディレクトリは loop-engineering ルート。

## 受け入れ条件

- [ ] 1 コマンドで sync+init+doctor まで完了できる
- [ ] 途中失敗で非ゼロ
- [ ] README / PORTING からリンクされる
