# engine/opencode（参考のみ・未使用）

`opencode.json.tmpl` は **現行フローでは使われません**。

対象プロジェクト／グローバルの `opencode.json` は次の Python ビルダーが生成します。

- `setup/lib/build_target_opencode_config.py`（`init-target-project.sh`）
- `setup/lib/opencode_mcp_servers.py`（MCP / permission 共通）
- `setup/configure-opencode.sh`（グローバル任意設定）

このディレクトリは初期設計時の最小テンプレを残した参考用です。編集しても init / configure には反映されません。
