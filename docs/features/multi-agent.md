# マルチエージェント（OpenCode / Claude Code / Cursor Agent）

| 項目 | 値 |
| --- | --- |
| ステータス | `done` |
| 関連実装 | `engine/lib/common.sh`（`resolve_loop_agent` 等）, `engine/run-loop.sh --agent`, `setup/init-target-project.sh --agents`, `setup/lib/stage_agent_assets.py`, `setup/doctor.sh` |
| 関連ドキュメント | [../SETUP.md](../SETUP.md), [loop-runner.md](./loop-runner.md), [opencode-init.md](./opencode-init.md) |

## 現状

Ralph（`vendor/open-ralph-wiggum`）は `--agent` でコーディングエージェントを切り替えられる。loop-engineering はその第一級として次を扱う。

| エージェント | Ralph フラグ | CLI | 対象PJに init が書くもの |
| --- | --- | --- | --- |
| **OpenCode**（既定） | `opencode` | `opencode` | `.opencode/opencode.json` + `.opencode/loop-engineering/` |
| **Claude Code** | `claude-code` | `claude` | `.claude/{CLAUDE.md,skills,agents,rules,settings.json}` + `.mcp.json` |
| **Cursor Agent** | `cursor-agent` | `cursor-agent` または `agent` | `.cursor/{rules/loop-engineering.mdc,skills,mcp.json}` |

Ralph 通過（専用 init なし）: `codex` / `copilot` / `qwen-code`。

エイリアス: `claude` → `claude-code`、`cursor` / `agent` → `cursor-agent`、`local` / `lmstudio` → `opencode`。

### 解決優先順位

1. `./engine/run-loop.sh --agent <name>`
2. `target.yaml` の `agent`
3. `loops/<name>/loop.yaml` の `agent`
4. 既定 `opencode`

init が書くレイアウトは別キー:

1. `./setup/init-target-project.sh --agents <csv|all>`
2. `target.yaml` の `init_agents`
3. 上で解決した実行エージェントのみ

```bash
# いつも Cursor Agent で回す
# target.yaml: agent: cursor-agent
./setup/init-target-project.sh --agent cursor-agent
./engine/run-loop.sh --loop yabaiyo

# レイアウトだけ全エージェント分書いておき、実行時に切替
./setup/init-target-project.sh --agents all
./engine/run-loop.sh --loop yabaiyo --agent claude-code
./engine/run-loop.sh --loop yabaiyo --agent opencode --model lmstudio/qwen3-coder-30b
```

## 要件定義

### FR-AGENT-1 実行時切替

`run-loop.sh --agent` が Ralph の `--agent` にそのまま渡り、`run-meta.json` の `agent` とプロンプト変数 `{{AGENT}}` に残ること。

### FR-AGENT-2 対象PJレイアウト

init がエージェント別のネイティブ設定を対象ツリー内に書くこと（cwd 境界を破らない）。既存のユーザー MCP キーは上書きしない（setdefault）。

### FR-AGENT-3 doctor

必須 CLI は **解決済み実行エージェント** のみ。OpenCode 以外では LM Studio 欠如を ERROR にしない。未 init 判定もエージェント別。

### FR-AGENT-4 後方互換

フラグも `agent:` も省略時は従来どおり OpenCode + `opencode.json`。既存の未 init ERROR 文言（`.opencode/opencode.json`）を維持する。

## 設計

### CLI 解決

`resolve_agent_binary`:

| agent | 探索順 |
| --- | --- |
| opencode | `RALPH_OPENCODE_BINARY` → `opencode` |
| claude-code | `RALPH_CLAUDE_BINARY` → `claude` |
| cursor-agent | `RALPH_CURSOR_AGENT_BINARY` → `cursor-agent` → `agent` |

見つかったバイナリ名を Ralph の環境変数へ渡し、`agent` しか無いマシンでも `cursor-agent` として動かす。

### 資材コピー

ECC の skills（`SKILL.md`）はそのまま Claude / Cursor の skills ディレクトリへ。agents は Claude Code 用に `.md` + frontmatter へ揃える（`.txt` のみなら生成）。rules は連結して 1 ファイルにする。

MCP は OpenCode 形式（`type: local|remote`）から Claude/Cursor の `mcpServers`（`command`/`args` または `url`）へ変換し、`.mcp.json` / `.cursor/mcp.json` にマージする。

無人実行: OpenCode は `--mcp-permission allow`。Claude Code は同指定時に `.claude/settings.json` の `permissions.defaultMode=bypassPermissions`。Cursor / Claude 本体は Ralph の `--allow-all`（既定オン）に依存。ヘッドレス Cursor は `CURSOR_API_KEY`。

### Issue 投稿

MCP がエージェント側で動かない場合は `--issue-fallback cli`（`gh` / `glab`）を使う。

## 受け入れ条件

- [x] `--agent` 未指定時は OpenCode（既存 smoke）
- [x] `--agent cursor-agent` / `claude-code` の dry-run が `run-meta.json` に agent を書く
- [x] `init --agents all` が 3 レイアウトを書く
- [x] `init --agent claude-code` は opencode.json を必須としない
- [x] doctor の OpenCode 未 init は従来どおり ERROR
- [x] 不正な agent 名はホスト終了コード 1
