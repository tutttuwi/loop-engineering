---
marp: true
theme: default
paginate: true
lang: ja
---

<!-- pr-review ループでは、重大な指摘がある場合のみこのテンプレートを使って
     スライドを作成する(通常はMR/PRへの直接コメント投稿がメインの成果物)。 -->

# MR/PRレビュー報告

対象: {{TARGET_NAME}}
レビュー対象: {{PR_REVIEW_TARGET}}
実行日: {{RUN_DATE}}

---

## サマリー

- 変更の概要
- 総合判定(Approve / Request Changes / Comment)
- must fix / should fix / nits の件数内訳

---

## Must Fix: <指摘タイトル>

- 該当箇所(ファイル:行番号)
- 何が問題か
- 修正案

---

## 総評

- 良かった点
- 今後同様のMR/PRで気をつけてほしいこと
