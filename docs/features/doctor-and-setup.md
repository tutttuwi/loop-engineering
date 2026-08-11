# Doctor とセットアップ診断

| 項目 | 値 |
| --- | --- |
| ステータス | `partial` |
| 関連実装 | `setup/doctor.sh`, `setup/install.sh` |
| ロードマップ | P0-3 |

## 現状

doctor が見るもの（概略）:

- bun / opencode / node / ffmpeg / python3 / git 等のコマンド
- submodule（ralph / ecc）の存在
- LM Studio 疎通（任意・WARN）

### 見ないもの（ギャップ）

- `project-config/target.yaml` の有無・`target_path` 実在
- 対象の `.opencode/opencode.json`（init 済みか）
- `GITHUB_TOKEN` / `GITLAB_TOKEN`
- `gh` / `glab`（フォールバック用）
- sync / init の実施痕跡
- `.loop-engineering` ステージの健全性
- `LOOP_MCP_PERMISSION` / permission プロファイル

ドキュメントの PORTING チェックリストと doctor が一致していない。

## 要件定義（P0-3）

### FR-DOC-1 接続完了チェック

次を ERROR または WARN で報告すること。

| 検査 | 推奨レベル |
| --- | --- |
| `target.yaml` 不在 | ERROR（または WARN + 手順） |
| `target_path` がディレクトリでない | ERROR |
| `<target>/.opencode/opencode.json` 不在 | ERROR（ループ実行不可） |
| `GITHUB_TOKEN` 不在かつ github MCP 想定 | WARN |
| `gh` 不在 | WARN（CLI 代替不可の旨） |
| LM Studio `/models` 失敗 | WARN |
| `uvx` 不在かつ serena 有効 | WARN（既存） |

### FR-DOC-2

exit コード: ERROR が1件以上なら非ゼロ。WARN のみならゼロ（現行方針を維持してよいが文書化）。

### FR-DOC-3

出力は人間可読。将来の `update.sh` から呼び出せること。

### FR-DOC-4（任意）

`--target-config` を受け取り、その yaml を検査対象にできること。

## 設計

### チェック関数の追加場所

`doctor.sh` にセクションを追加:

1. Tools（既存）
2. Submodules（既存）
3. **Target readiness（新規）**
4. **Auth / Issue readiness（新規）**
5. LLM（既存）

target 解決は `resolve_target_config` + `yaml_get` を再利用（`common.sh` source 済み想定）。

### メッセージ例

```
[ERROR] target.yaml がありません: cp project-config/target.yaml.example ...
[ERROR] 未 init: ./setup/init-target-project.sh
[WARN]  GITHUB_TOKEN 未設定 — Issue MCP は失敗します
[WARN]  mcp permission が ask です — 無人実行時は --mcp-permission allow
```

## 受け入れ条件

- [ ] 未 init の target で doctor が ERROR を出す
- [ ] PORTING チェックリストの主要項目が doctor でカバーされる
- [ ] install.sh 経由でも新チェックが走る（または明示的に doctor 推奨）
