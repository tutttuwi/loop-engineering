# OpenCode 初期化（init / configure）

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（permission 拡張は planned → [permissions-unattended.md](./permissions-unattended.md)） |
| 関連実装 | `setup/init-target-project.sh`, `setup/configure-opencode.sh`, `setup/lib/build_target_opencode_config.py`, `setup/lib/opencode_mcp_servers.py` |

## 要件定義（維持）

1. ループ実行に必要な設定は **対象PJの** `.opencode/opencode.json` に集約する
2. グローバル `~/.config/opencode/opencode.json` は任意（マシン全体の既定）
3. LM Studio（OpenAI 互換）プロバイダと既定モデルを設定できる
4. MCP（github / gitlab / playwright / serena）と `lsp: true` を登録できる（opt-out 可）
5. `project-config/{agents,skills,rules}` を対象の `.opencode/loop-engineering/` にコピーし、opencode.json から参照する
6. 既存 opencode.json がある場合はバックアップしてから更新する

## 設計（現状）

### 役割分担

| スクリプト | 書き込み先 | 必須？ |
| --- | --- | --- |
| `init-target-project.sh` | `<target>/.opencode/` | **ループ必須** |
| `configure-opencode.sh` | `~/.config/opencode/` | 任意 |

### 生成物

```
<target>/.opencode/
├── opencode.json
└── loop-engineering/
    ├── agents/
    ├── skills/
    └── rules/
```

`build_target_opencode_config.py` が:

- `provider.lmstudio` + `model`
- `skills.paths`
- `instructions`（rules 配下 md）
- `agent`（subagent、write/edit は false）
- MCP / lsp（`apply_mcp_servers`）
- `permission.mcp_*` 既定 `ask`

### 既知のデッドコード

`engine/opencode/opencode.json.tmpl` は現行フローで未使用。削除か「参考テンプレ」と明記する（P2-5）。

## 受け入れ条件（現状維持）

- [x] init 後に対象で `opencode` が LM Studio モデルを選べる
- [x] MCP を `--without-*` で選べる
- [x] Serena 起動時にブラウザダッシュボードを開かない
