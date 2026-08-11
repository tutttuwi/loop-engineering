# Doctor とセットアップ診断

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（P0-3 Target/Auth + P4-3 同梱ループ一覧 + P4-4 未 init smoke） |
| 関連実装 | `setup/doctor.sh`, `setup/install.sh` |
| ロードマップ | P0-3 / P4-3 / P4-4 |

## 現状

doctor が見るもの（概略）:

- bun / opencode / node / ffmpeg / python3 / git 等のコマンド
- submodule（ralph / ecc）の存在
- 同梱ループ一覧（`loops/*/loop.yaml`、`_template` 除外 — sync `--all-loops` と同契約）
- LM Studio 疎通（任意・WARN）
- Target readiness（`target.yaml` / init / mcp permission）
- Auth / Issue readiness（token / gh / glab）
- TTS / Marp（`say` 有無と既定エンジン、`LOOP_MARP_VERSION` ピン推奨）

### 見ないもの（ギャップ）

- sync / init の実施痕跡の詳細監査
- `.loop-engineering` ステージの健全性の深い検査

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

## P4-3 同梱ループ一覧

運用時にメタリポの同梱ループが見えると、`sync --all-loops` / `update.sh` の対象漏れを防ぎやすい。

| 規則 | 内容 |
| --- | --- |
| 列挙 | `loops/*/loop.yaml` があるディレクトリ名 |
| 除外 | `_template`（ひな形。製品ループではない） |
| 出力 | `[ OK ] loop: <name> (loops/<name>/loop.yaml)` + 件数サマリ |
| 0 件 | ERROR（メタリポ破損の可能性） |
| 検証 | `./tests/smoke.sh` — monkey-test / yabaiyo / pr-review / security-audit / deps-audit を含み `_template` を出さない |

## P4-4 未 init 受け入れ

`target_path` は存在するが `<target>/.opencode/opencode.json` が無い状態を「未 init」とみなし、ループ実行不可として ERROR にする（FR-DOC-1）。

| 規則 | 内容 |
| --- | --- |
| 判定 | `target_path` ディレクトリあり ∧ `.opencode/opencode.json` 不在 |
| 出力 | `[ERROR] 未 init: <path> がありません。./setup/init-target-project.sh を実行してください` |
| exit | ERROR≥1 なら非ゼロ（FR-DOC-2） |
| 検証 | `./tests/smoke.sh` — 一時 target + `--target-config` で上記を固定 |

## 受け入れ条件

- [x] 未 init の target で doctor が ERROR を出し非ゼロ終了する（P4-4 / smoke）
- [ ] PORTING チェックリストの主要項目が doctor でカバーされる
- [ ] install.sh 経由でも新チェックが走る（または明示的に doctor 推奨）
- [x] doctor が同梱ループを列挙し `_template` を除外する（P4-3 / smoke）
