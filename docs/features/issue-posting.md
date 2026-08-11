# Issue 投稿

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（P0-2 ゲート + CLI フォールバック実装済み） |
| 関連実装 | `engine/run-loop.sh`（`ISSUE_POST_INSTRUCTIONS` / ゲート）, `engine/lib/common.sh`（`verify_issue_url_file`）, `engine/lib/issue.sh`, MCP via `opencode_mcp_servers.py`, 各 `loops/*/prompt.md` |
| ロードマップ | P0-2 |

## 現状

### できること

- `issue_post_mode: create | update`
- create: 毎回新規 Issue、URL を `issue-url.txt` に保存するようプロンプト指示
- update: 既存 Issue へコメント追記
- GitHub remote MCP / GitLab local MCP（トークンは環境変数）
- ホスト完了ゲート: `require_issue`（loop.yaml、既定 true）時に `verify_issue_url_file`
- CLI フォールバック: `--issue-fallback cli` で `issue.sh`（`gh` / `glab`）
- `--skip-issue-gate` で検証スキップ（明示時のみ）

### `verify_issue_url_file` 受け入れ条件

先頭1行を trim したうえで、次をすべて満たすこと。

| 条件 | 例（拒否） |
| --- | --- |
| ファイルが存在する | （欠落） |
| 非空（空白のみ不可） | ` ` / 空ファイル |
| `http://` または `https://` | `ftp://...` / `not-a-url` |
| URL 内に空白なし | `https://.../1 trailing` |
| ホストあり・パス非空 | `https://github.com` / `https://github.com/` |

### 残ギャップ（軽微）

| 問題 | 影響 |
| --- | --- |
| 投稿はエージェント遵守依存 | MCP 失敗時はゲートで非ゼロ（または CLI フォールバック） |
| 細粒度 MCP permission | サーバ別 `mcp_permission_overrides` 対応（→ [permissions-unattended.md](./permissions-unattended.md) FR-PERM-4）。ツール単位は未対応 |

## 要件定義（P0-2）— 実装済み

### FR-ISSUE-1 完了ゲート

`{{OUTPUT_DIR}}/issue-url.txt` が上記検証を通ること。満たさない場合は既定で非ゼロ終了。

### FR-ISSUE-2 CLI フォールバック

```bash
engine/lib/issue.sh create --provider github --repo-url ... --title ... --body-file ... --out ...
engine/lib/issue.sh comment --provider github --issue ... --body-file ... --out ...
```

`run-loop.sh --issue-fallback cli` から呼ぶ。

### FR-ISSUE-3 プロンプト整合

`ISSUE_POST_INSTRUCTIONS` に「失敗時は書かない」「ホスト検証（http(s)・パスあり）」を明記。

### FR-ISSUE-4

create モードで既存 `issue-url.txt` がある場合は新規作成せず追記（プロンプト指示済み）。CLI ヘルパーも同規則。

## 設計

### 完了ゲート挿入点

```
if require_issue && ! skip_issue_gate; then
  verify_issue_url_file "$output_dir/issue-url.txt" \
    || (--issue-fallback cli なら issue.sh → 再検証) \
    || exit 1
fi
```

`require_issue` は `loop.yaml` で上書き可能（既定 true）。

### doctor との関係

[doctor-and-setup.md](./doctor-and-setup.md): `GITHUB_TOKEN` / `GITLAB_TOKEN` / `gh` / `glab` の有無を WARN。

## 受け入れ条件

- [x] Issue 未作成のまま exit 0 にならない（ゲート有効時）
- [x] `gh`/`glab` があれば MCP なしでも issue-url.txt を作れる（`--issue-fallback cli`）
- [x] update モードで `issue_target` 必須
- [x] dry-run で Issue API を呼ばない
- [x] 空白のみ・非 http(s)・パスなし URL をゲートが拒否する（smoke）
