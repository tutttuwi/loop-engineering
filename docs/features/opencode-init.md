# OpenCode 初期化（init / configure）

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（permission プロファイル含む → [permissions-unattended.md](./permissions-unattended.md)） |
| 関連実装 | `setup/init-target-project.sh`, `setup/configure-opencode.sh`, `setup/lib/build_target_opencode_config.py`, `setup/lib/opencode_mcp_servers.py` |

## 要件定義（維持）

1. ループ実行に必要な設定は **対象PJ内** に集約する（OpenCode は `.opencode/opencode.json`）
2. グローバル `~/.config/opencode/opencode.json` は任意（マシン全体の既定）
3. OpenCode 時: LM Studio（OpenAI 互換）プロバイダと既定モデルを設定できる
4. Claude Code / Cursor Agent 時: ネイティブ skills/rules/MCP を init が書く（[multi-agent.md](./multi-agent.md)）
4. MCP（github / gitlab / playwright / serena）と `lsp: true` を登録できる（opt-out 可）
5. `project-config/{agents,skills,rules}` を対象の `.opencode/loop-engineering/` にコピーし、opencode.json から参照する
6. 既存 opencode.json がある場合はバックアップしてから更新する
7. MCP permission を `ask` / `allow` / `deny` で選べる（CLI / 環境変数 / target.yaml）

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
- `permission.mcp_*`（既定 `ask`。`--mcp-permission allow` 等で変更）
- 任意で `permission.<server>_*`（`--mcp-permission-overrides github=allow,...`）

### 参考テンプレ（未使用）

`engine/opencode/opencode.json.tmpl` は現行フローでは未使用。init は Python ビルダー（上記）が生成する。  
詳細は [engine/opencode/README.md](../../engine/opencode/README.md)（P2-5 対応済み）。

## 受け入れ条件（現状維持）

- [x] init 後に対象で `opencode` が LM Studio モデルを選べる
- [x] MCP を `--without-*` で選べる
- [x] Serena 起動時にブラウザダッシュボードを開かない
- [x] `--mcp-permission` で `permission.mcp_*` を切替できる
- [x] `--mcp-permission-overrides` でサーバ別 `permission.<server>_*` を付与できる
