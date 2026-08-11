# ECC 同期（sync-ecc-assets）

| 項目 | 値 |
| --- | --- |
| ステータス | `done`（P1-4 マニフェスト保護実装済み） |
| 関連実装 | `setup/sync-ecc-assets.sh`, `loops/*/loop.yaml` (`ecc_agents` / `ecc_skills` / `ecc_rules`) |
| ロードマップ | P1-4 |

## 現状

- `vendor/ecc` 全体は巨大なため、**使う分だけ** `project-config/{agents,skills,rules}` へ抽出
- `--loop <name>` で `loop.yaml` の ecc_* を読む
- `--list` で候補表示
- コピー元（vendor）は直接編集しない方針

### ギャップ

- `cp -R` 相当の上書きで、ユーザーが `project-config` に足したカスタムが **消える／潰れる**可能性がある
- sync と init の「いつやるか」がドキュメント依存（自動化は [porting-and-update.md](./porting-and-update.md)）

## 要件定義（P1-4）

### FR-SYNC-1

ユーザー追加ファイル（例: `project-config/rules/common/project-specific.md`）を、ECC 由来ファイルの再同期で削除しないこと。

### FR-SYNC-2

同名パスで ECC 側が更新された場合の方針を明示し、実装がそれに従うこと。推奨:

- **既定**: ECC 由来は上書き更新、ユーザー専用パスは触らない
- **オプション**: `--backup` で上書き前に timestamp バックアップ

### FR-SYNC-3

「ECC 由来」と「ユーザー由来」を区別できること（マニフェストまたはディレクトリ規約）。

## 設計

### 案: マニフェスト方式（推奨）

```
project-config/.ecc-sync-manifest
# 相対パス一覧（前回 sync で配置したファイル）
```

同期アルゴリズム:

1. マニフェスト記載ファイルのみ削除／置換の対象
2. マニフェストに無いファイルはユーザー資産として保持
3. 新規抽出分をコピーし、マニフェストを更新

### 案: ディレクトリ規約

```
project-config/rules/
├── ecc/          # sync が管理（丸ごと置換可）
└── local/        # ユーザー専用（init は両方を対象へコピー）
```

init / opencode `instructions` が両系を読むよう更新が必要。

### 非目標

- vendor/ecc へのパッチ管理（upstream は submodule update）

## 受け入れ条件

- [ ] ユーザー専用 md を置いた状態で sync → ファイルが残る
- [ ] ECC 更新後の sync で ecc 由来ファイルは新内容になる
- [ ] PORTING / README に方針が書かれている
