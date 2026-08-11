# ターゲット設定

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（P1-2 target-config 共有 + P2-4 レジストリ + P5-2 `--list-targets`） |
| 関連実装 | `project-config/target.yaml(.example)`, `project-config/targets/`, `engine/run-loop.sh`, `setup/init-target-project.sh`, `setup/doctor.sh`, `setup/update.sh`, `engine/lib/common.sh` (`resolve_target_config` / `--target-name` / `print_target_registry_list`) |
| ロードマップ | P1-2, P2-4, P5-2 |

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
| `mcp_permission` | `ask` / `allow` / `deny` |
| `mcp_permission_overrides` | 任意。`github=allow,playwright=deny` 形式（サーバ別 → OpenCode `permission.<server>_*`） |

### 解決優先順位（run-loop / init / doctor 等）

1. `--target-config <path>`（明示パス）
2. `--target-name <name>` → `project-config/targets/<name>.yaml`
3. `LOOP_TARGET_CONFIG` 環境変数
4. `project-config/target.yaml`

`--target` は上記で選んだ yaml の `target_path` を上書きする（パス優先）。  
`--target-config` と `--target-name` は同時指定不可。

### レジストリ配置

```
project-config/
├── target.yaml              # 既定
└── targets/
    ├── README.md
    ├── app-a.yaml           # --target-name app-a
    └── app-b.yaml
```

## 要件定義

### FR-TC-1（P1-2）

`init-target-project.sh` が `run-loop.sh` と同じ規則で target-config を解決すること。

- `--target-config <path>`
- `LOOP_TARGET_CONFIG`
- 既定 `project-config/target.yaml`

### FR-TC-2（P1-2）

`--target` 指定時は従来どおりパス優先。必要なら yaml の他キー（repo_url 等）は解決済み config から読む。

### FR-TC-3（P2-4）

`project-config/targets/<name>.yaml` を列挙し、`--target-name <name>` で選択できること。

### FR-TC-4（P5-2）

`run-loop` / `doctor` / `init` / `update` が `--list-targets` でレジストリ名を列挙できること（`sync --list` と対称の発見 UX）。

### 制約（維持）

- ネストなし・リストなしのフラット `key: value`（bash 3.2 簡易パーサ）
- レジストリ名は英数字と `._-` のみ

## 設計

### 共有ヘルパー（`engine/lib/common.sh`）

- `resolve_target_config [explicit] [registry_name]`
- `resolve_target_registry_path <name>`
- `list_target_registry_names`
- `print_target_registry_list`（`--list-targets`）
- `require_target_config_file <path> [registry_name]`

### init の表示名

レジストリ選択が `--target-name` のため、対象の表示名 CLI は `--display-name`（yaml キー `target_name` は従来どおり）。

### マルチターゲット例

```bash
cp project-config/target.yaml.example project-config/targets/app-a.yaml
# 編集後
./setup/init-target-project.sh --target-name app-a
./engine/run-loop.sh --loop yabaiyo --target-name app-a
```

従来どおり明示パスも可:

```bash
./engine/run-loop.sh --loop yabaiyo --target-config project-config/target-b.yaml
```

```bash
./engine/run-loop.sh --list-targets
./setup/doctor.sh --list-targets
./setup/init-target-project.sh --list-targets
./setup/update.sh --list-targets
```

## 受け入れ条件

- [x] init / run-loop で同じ `--target-config` が使える
- [x] 既存の `target.yaml` のみ運用が壊れない
- [x] `--target-name` で `targets/<name>.yaml` を選択できる
- [x] `--list-targets` でレジストリ名を列挙できる（P5-2 / smoke）
- [x] example / README と docs のキー説明が一致
