# ECC 同期（sync-ecc-assets）

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（P1-4 マニフェスト保護 + マルチループ和集合） |
| 関連実装 | `setup/sync-ecc-assets.sh`, `setup/update.sh`, `loops/*/loop.yaml` (`ecc_agents` / `ecc_skills` / `ecc_rules`) |
| ロードマップ | P1-4 |

## 現状

- `vendor/ecc` 全体は巨大なため、**使う分だけ** `project-config/{agents,skills,rules}` へ抽出
- `--loop <name>` で `loop.yaml` の ecc_* を読む（**複数指定で和集合**）
- `--all-loops` で `loops/*/loop.yaml`（`_template` 除外）をすべて和集合
- `--list` で候補表示
- OpenCode 用 `.txt` と Claude Code 用 `.md` の両方がある agent は **両方コピー**する（init がそれぞれのレイアウトへ配る）
- マニフェスト外のユーザーファイルは保護される

### マルチループ（重要）

`project-config/.ecc-sync-manifest` は **1 つ**だけ。sync は「今回指定した ecc_* の集合」にマニフェストを揃える。

- **悪い例**: ループごとに別々に sync → 後から実行したループ以外の ECC 由来が削除される
- **良い例**: 併用するループを一度に指定して和集合 sync

```bash
./setup/sync-ecc-assets.sh --loop yabaiyo --loop security-audit --loop monkey-test
# または
./setup/sync-ecc-assets.sh --all-loops

./setup/update.sh --loop yabaiyo --loop monkey-test
```

単一 `--loop` のときは警告を出し、他ループ用資材が落ちうることを明示する。

## 要件定義（P1-4）

### FR-SYNC-1

ユーザー追加ファイル（例: `project-config/rules/common/project-specific.md`）を、ECC 由来ファイルの再同期で削除しないこと。

### FR-SYNC-2

同名パスで ECC 側が更新された場合の方針を明示し、実装がそれに従うこと。推奨:

- **既定**: ECC 由来は上書き更新、ユーザー専用パスは触らない
- **オプション**: `--backup` で上書き前に timestamp バックアップ

### FR-SYNC-3

「ECC 由来」と「ユーザー由来」を区別できること（マニフェストまたはディレクトリ規約）。

### FR-SYNC-4

複数ループ併用時、各ループの ecc_* を和集合して一度の sync / 一つのマニフェストにできること。

## 設計

### 案: マニフェスト方式（推奨・実装済み）

```
project-config/.ecc-sync-manifest
# 相対パス一覧（前回 sync で配置したファイル）
```

同期アルゴリズム:

1. 指定ループ（複数可）の ecc_* を CSV 和集合（重複除去）
2. マニフェスト記載ファイルのみ削除／置換の対象
3. マニフェストに無いファイルはユーザー資産として保持
4. 新規抽出分をコピーし、マニフェストを更新

### 案: ディレクトリ規約

```
project-config/rules/
├── ecc/          # sync が管理（丸ごと置換可）
└── local/        # ユーザー専用（init は両方を対象へコピー）
```

init / opencode `instructions` が両系を読むよう更新が必要（未採用）。

### 非目標

- vendor/ecc へのパッチ管理（upstream は submodule update）

## 受け入れ条件

- [x] ユーザー専用 md を置いた状態で sync → ファイルが残る
- [x] ECC 更新後の sync で ecc 由来ファイルは新内容になる
- [x] 複数 `--loop` / `--all-loops` で和集合 sync できる
- [x] PORTING / README / SETUP に方針が書かれている
- [x] smoke で 2 ループ union + ユーザー資産保護を検証
- [x] smoke で `--all-loops` が同梱ループ（`deps-audit` 含む）を列挙し `_template` を除外、和集合スキルを同期（P4-1）
