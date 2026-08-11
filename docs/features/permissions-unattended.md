# 無人実行向け Permission

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（P0-1 一括 + P3-1 サーバ別） |
| 関連実装 | `setup/lib/opencode_mcp_servers.py`, `init-target-project.sh` / `configure-opencode.sh`（`--mcp-permission` / `--mcp-permission-overrides`） |
| ロードマップ | P0-1, P3-1 |

## 背景

ループは長時間・非対話で回す前提だが、MCP permission の既定は `ask`。  
Issue 作成や PR コメントが確認待ちになり、ヘッドレス実行と相性が悪い。

常時 `allow` は破壊的操作リスクがあるため、**プロファイル切替**（ask / allow / deny）と、必要なら **サーバ別上書き**を使える。

## 要件定義（P0-1）

### FR-PERM-1

init / configure 時に MCP permission を選択できること。

| プロファイル | `permission.mcp_*` | 用途 |
| --- | --- | --- |
| `ask`（既定・現状維持） | `ask` | 対話・初回検証 |
| `allow` | `allow` | CI / 夜間無人ループ |
| `deny`（任意） | `deny` | MCP 副作用禁止の読取専用検証 |

### FR-PERM-2

指定手段（いずれかまたは併用）:

- CLI: `./setup/init-target-project.sh --mcp-permission allow`
- 環境変数: `LOOP_MCP_PERMISSION=ask|allow|deny`
- （任意）`target.yaml` の `mcp_permission`

優先順位: CLI > 環境変数 > target.yaml > 既定 `ask`

### FR-PERM-3

README / SETUP / doctor に「無人実行時は allow を明示せよ」と記載すること。

### FR-PERM-4（P3-1・実装済み）

サーバ別制御:

- OpenCode は MCP ツールを `<server>_*` glob で permission できる（例: `github_*`）
- 一括 `mcp_*` を既定にし、上書きだけサーバ別に書く
- **ツール単位**（例: `github_create_issue` だけ）の DSL は未対応（OpenCode 側の表現に合わせた最小拡張）

| 指定 | 例 |
| --- | --- |
| CLI | `--mcp-permission-overrides github=allow,playwright=deny` |
| 環境変数 | `LOOP_MCP_PERMISSION_OVERRIDES=github=allow,playwright=deny` |
| target.yaml | `mcp_permission_overrides: github=allow,playwright=deny` |

優先順位は一括と同様: CLI > 環境変数 > yaml > （なし）

生成例:

```json
{
  "permission": {
    "mcp_*": "ask",
    "github_*": "allow",
    "playwright_*": "deny"
  }
}
```

`force`（init/configure 再実行）時、既知サーバ（`github` / `gitlab` / `playwright` / `serena`）の上書きキーは yaml/CLI の内容に同期する（指定から外したキーは削除）。カスタムサーバ名のキーは手編集分を消さない。

### 非機能

- 既存のユーザー独自 `permission` キーは可能なら尊重（上書き方針をログに出す）
- 秘密情報を設定ファイルに埋め込まない
- bash 3.2 互換（フラット YAML・カンマ区切りマップ）

## 設計

### 変更箇所

1. `opencode_mcp_servers.py`  
   - `apply_mcp_servers(..., mcp_permission, mcp_permission_overrides=...)`  
   - `permission["mcp_*"]` + `permission["<server>_*"]`
2. `build_target_opencode_config.py` / `configure-opencode.sh`  
   - `LOOP_MCP_PERMISSION` / `LOOP_MCP_PERMISSION_OVERRIDES`
3. `init-target-project.sh` / `update.sh`  
   - `--mcp-permission` / `--mcp-permission-overrides`
4. `engine/lib/common.sh`  
   - `resolve_mcp_permission` / `resolve_mcp_permission_overrides`

### 推奨運用

```bash
# 開発・確認
./setup/init-target-project.sh --mcp-permission ask

# 無人（一括 allow）
./setup/init-target-project.sh --mcp-permission allow
./engine/run-loop.sh --loop yabaiyo

# 一括は ask、Issue 用 github だけ allow（ブラウザ MCP は deny）
./setup/init-target-project.sh \
  --mcp-permission ask \
  --mcp-permission-overrides github=allow,playwright=deny
```

### セキュリティ注意

`allow` は GitHub/GitLab への書き込みを無人承認する。トークン権限は最小（public_repo / api 等）に留め、対象リポジトリを限定すること。  
サーバ別 `allow` でも、そのサーバの**全ツール**が許可される点に注意。

## 受け入れ条件

- [x] `--mcp-permission allow` 後の opencode.json が `"mcp_*": "allow"`
- [x] 未指定時は従来どおり `ask`
- [x] ドキュメントに無人運用手順がある
- [x] `--mcp-permission-overrides github=allow` で `"github_*": "allow"` が付く
- [x] 不正な overrides 文字列は init が失敗する
- [ ] Issue 投稿ループが対話なしで MCP ツールを実行できる（結合確認・環境依存）
