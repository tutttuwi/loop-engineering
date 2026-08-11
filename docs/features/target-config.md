# ターゲット設定

| 項目 | 値 |
| --- | --- |
| ステータス | `partial` |
| 関連実装 | `project-config/target.yaml(.example)`, `engine/run-loop.sh`, `setup/init-target-project.sh`, `engine/lib/common.sh` (`resolve_target_config`) |
| ロードマップ | P1-2, P2-4 |

## 現状

### キー（フラット YAML）

| キー | 用途 |
| --- | --- |
| `target_path` | 対象ローカルパス |
| `target_name` | 表示名 |
| `repo_provider` | `github` / `gitlab` / `both`（プロンプト文言用） |
| `repo_url` | Issue 投稿先 |
| `default_branch` | 既定ブランチ |
| `monkey_test_target_url` | monkey-test 用 URL |
| `pr_review_target` | pr-review 対象 |
| `issue_post_mode` | `create` / `update` |
| `issue_target` | update 時の Issue |

### 解決優先順位（run-loop）

1. `--target` / `--target-config` 等の CLI
2. `LOOP_TARGET_CONFIG` 環境変数（config ファイル）
3. `project-config/target.yaml`

### ギャップ

- **`init-target-project.sh` は `project-config/target.yaml` 固定**で、`resolve_target_config` / `--target-config` と不一致
- `repo_provider: both` は文言用。MCP の on/off は init の `--without-*` / 既定オンで別系統
- 複数プロジェクト用のレジストリ（`targets/*.yaml`）なし

## 要件定義

### FR-TC-1（P1-2）

`init-target-project.sh` が `run-loop.sh` と同じ規則で target-config を解決すること。

- `--target-config <path>`
- `LOOP_TARGET_CONFIG`
- 既定 `project-config/target.yaml`

### FR-TC-2（P1-2）

`--target` 指定時は従来どおりパス優先。必要なら yaml の他キー（repo_url 等）は解決済み config から読む。

### FR-TC-3（P2-4・任意）

`project-config/targets/<name>.yaml` を列挙し、`--target-name <name>` で選択できること。

### 制約（維持）

- ネストなし・リストなしのフラット `key: value`（bash 3.2 簡易パーサ）

## 設計

### init への組み込み

```
resolve_target_config "$target_config_override"
→ target_yaml
→ target_path = --target | yaml_get target_path
```

`init-target-project.sh` の引数に `--target-config` を追加し、yaml 更新処理もそのファイルを対象にする。

### マルチターゲット運用（文書化済みパターン）

現状でも可能な回避策（実装前）:

```bash
./engine/run-loop.sh --loop yabaiyo --target-config project-config/target-b.yaml
```

init 未対応のため、別 yaml のプロジェクトは `--target` 直指定で init する必要がある → FR-TC-1 で解消。

### レジストリ案（P2）

```
project-config/
├── target.yaml              # 既定
└── targets/
    ├── app-a.yaml
    └── app-b.yaml
```

`run-loop --target-name app-a` → `targets/app-a.yaml` を `resolve_target_config` 相当で開く。

## 受け入れ条件

- [ ] init / run-loop で同じ `--target-config` が使える
- [ ] 既存の `target.yaml` のみ運用が壊れない
- [ ] example と docs のキー説明が一致
