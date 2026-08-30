---
name: persona-driven-qa
description: Analyze an application's roles, permissions, IA, and documented/code-derived use cases, then drive exploratory tests as diverse personas. Use with the monkey-test loop.
---

# Persona-driven exploratory QA

ランダムなクリックの前に、対象アプリの **誰が・何を・どの順で** 使うかをモデル化する。
本スキルは `loops/monkey-test` のフェーズA/Bの探し方と、ペルソナ設計の観点を固定する。

## Safety

- テスト用アカウントのみ。本番ログイン・本番シークレットは使わない
- パスワード・トークン・PII を findings / レポート / Issue / スクリーンショット注釈に残さない
- 本番URLでの破壊的操作（課金、削除、一括更新）は行わない
- 推測でロールを捏造しない。根拠（パス・ドキュメント見出し）を `app-model.md` に残す。不明は「不明」と書く

## Phase A — ユーザー種別・アクセス権・構造

存在する範囲だけ読む。スタックに無いパスを探して止まらない。

### ドキュメント

- `README*`, `docs/`, `CONTRIBUTING*`, `AGENTS.md`, 仕様・権限・ユーザーガイド
- プロダクト概要、ロール説明、オンボーディング手順

### ルーティング / IA

| 手がかり | 例 |
| --- | --- |
| フロント | `app/`, `pages/`, `src/routes*`, `src/app/`, `nuxt.config`, `remix routes` |
| バック | `config/routes.rb`, `urls.py`, `routes.ts`, `*Controller`, OpenAPI, GraphQL schema |
| ナビ | Sidebar, Header, ロール別メニューコンポーネント |

画面ごとに「目的・想定ロール・主要操作」を表にする。

### 認可

コード検索のキーワード例: `role`, `permission`, `policy`, `ability`, `can?`, `authorize`, `Casbin`, `OPA`, `gate`, `RBAC`, `scope`, `@PreAuthorize`, `middleware`, `requireAdmin`, `forbidden`, `403`。

マトリクスは **リソース × ロール**（許可 / 拒否 / 不明）。最低でも次を列にする:

- 未認証（ゲスト）
- 認証済みの各ロール（member / admin / support / tenant-owner 等、コード上の名前を使う）
- 同一ロールで主体が違うユーザー（他人のリソース、別テナント）があるなら列を分ける

### 認証・セッション

ログイン、ログアウト、招待、パスワードリセット、OAuth、セッション期限、ロール切替、なりすまし（impersonation）。
期限切れとロール変更直後は後のペルソナ状態として使う。

### テストアカウントの発見順

1. `target.yaml` の `monkey_test_accounts`（`role` または `role|login|secret` のカンマ区切り）
2. E2E fixtures / `playwright` の storageState / `*.spec` 内のテストユーザー
3. `seed`, `factory`, `fixtures/`, `.env.example`（`TEST_USER` 等）
4. ドキュメントに書かれたデモアカウント
5. 見つからなければ未認証 + アプリのサインアップ／デモログイン

本番の個人アカウントや共有パスワードを採用しない。

## Phase B — ユースケース / 業務フロー / 利用パターン

### 抽出元（優先順）

1. 既存 E2E（意図したハッピーパスの最良の証拠）
2. ドキュメントのユーザーストーリー・操作手順
3. ナビとルートから再構成した「仕事の流れ」
4. OpenAPI / GraphQL の mutation 名、ジョブ名、feature flag 名

各フローに主経路・代替（キャンセル、差し戻し）・例外（バリデーション、権限、ネットワーク）を付ける。

### ペルソナはロールのコピーではない

識別した各ロールに、行動特性を掛けて **3種以上** 作る。

| 軸 | 例 |
| --- | --- |
| 習熟 | 初回 / 日常 / パワー（一括・ショートカット） |
| 操作速度 | 慎重に読む / 連打・早送り |
| デバイス | デスクトップ / 狭いビューポート |
| 入力 | 正常値 / 空・長文・特殊文字 |
| 状態 | セッション切れ、権限変更直後、他人のデータ |

カタログ行 = ペルソナ × フロー × バリアント。状態は 未実施 / 実施済 / ブロッカー。

必ず含める行:

- 各ロールの主業務フロー（ハッピーパス）
- 未認証または権限外ロールの保護URL直叩き
- 自分のリソース vs 他人のリソース（該当時）
- 主要フローの例外バリアント
- クロスロール境界を少なくとも1つ

## Phase C — 実行時の切替

- ペルソナを変えるときはログアウトするか、別ブラウザコンテキストを使う
- 未実施のロールと未実施の業務フローを先に潰す
- ログイン失敗はブロッカーにして止めない。未認証や別ロールで継続
- 観察対象: 想定外の200、空白画面、権限エラーの欠落、データの漏れ、二重送信の副作用、モバイル崩れ

## 成果物との対応

| ファイル | このスキルが埋めるもの |
| --- | --- |
| `app-model.md` | ロール、マトリクス、画面/ルート、根拠パス |
| `scenarios.md` | フロー、利用パターン、ペルソナ、カバレッジ表 |
| `state.md` | フェーズ、現在ペルソナ、実施ログ |
| `findings.md` | 逸脱。再現手順にペルソナ/ロールを含める |
