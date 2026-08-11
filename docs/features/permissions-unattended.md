# 無人実行向け Permission

| 項目 | 値 |
| --- | --- |
| ステータス | `planned` |
| 関連実装 | `setup/lib/opencode_mcp_servers.py`（現状 `permission.mcp_* = ask` 固定） |
| ロードマップ | P0-1 |

## 背景

ループは長時間・非対話で回す前提だが、現行の対象 `opencode.json` は MCP を `ask` にする。  
Issue 作成や PR コメントが確認待ちになり、ヘッドレス実行と相性が悪い。

一方、常時 `allow` は破壊的操作リスクがあるため、**プロファイル切替**が必要。

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

優先順位（案）: CLI > 環境変数 > target.yaml > 既定 `ask`

### FR-PERM-3

README / SETUP / doctor に「無人実行時は allow を明示せよ」と記載すること。

### FR-PERM-4（任意）

より細かい制御（例: `mcp_github: allow`, `mcp_playwright: ask`）は P2。まずは `mcp_*` 一括でよい。

### 非機能

- 既存のユーザー独自 `permission` キーは可能なら尊重（上書き方針をログに出す）
- 秘密情報を設定ファイルに埋め込まない

## 設計

### 変更箇所

1. `opencode_mcp_servers.py`  
   - `apply_mcp_servers(..., mcp_permission: str = "ask")`  
   - `permission["mcp_*"] = mcp_permission`（setdefault ではなく、init 再実行時は更新するかをフラグで制御）
2. `build_target_opencode_config.py` / `configure-opencode.sh`  
   - 環境変数 `LOOP_MCP_PERMISSION` を読む
3. `init-target-project.sh`  
   - `--mcp-permission` をパースして export

### 推奨運用

```bash
# 開発・確認
./setup/init-target-project.sh --mcp-permission ask

# 無人
./setup/init-target-project.sh --mcp-permission allow
./engine/run-loop.sh --loop yabaiyo
```

### セキュリティ注意

`allow` は GitHub/GitLab への書き込みを無人承認する。トークン権限は最小（public_repo / api 等）に留め、対象リポジトリを限定すること。

## 受け入れ条件

- [ ] `--mcp-permission allow` 後の opencode.json が `"mcp_*": "allow"`
- [ ] 未指定時は従来どおり `ask`
- [ ] ドキュメントに無人運用手順がある
- [ ] Issue 投稿ループが対話なしで MCP ツールを実行できる（結合確認）
