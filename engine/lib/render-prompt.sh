#!/usr/bin/env bash
# engine/lib/render-prompt.sh
#
# loops/<name>/prompt.md のようなテンプレートファイル内の {{VAR_NAME}} を
# 同名の環境変数の値で置換して標準出力に書き出す、極小のテンプレートエンジン。
# 複数行の値も安全に扱うため置換処理自体はPython3に委譲する(sedの改行処理は壊れやすいため)。
#
# 使い方:
#   VAR1=foo VAR2=bar render-prompt.sh path/to/template.md > out.md
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

template_file="${1:-}"
if [[ -z "$template_file" || ! -f "$template_file" ]]; then
  log_error "テンプレートファイルを指定してください: render-prompt.sh <file>"
  exit 1
fi

require_cmd python3 "https://www.python.org/ からインストールしてください"

python3 - "$template_file" <<'PYEOF'
import os
import re
import sys

template_path = sys.argv[1]
with open(template_path, "r", encoding="utf-8") as f:
    content = f.read()

pattern = re.compile(r"\{\{([A-Z_][A-Z0-9_]*)\}\}")


def replace(match: "re.Match[str]") -> str:
    name = match.group(1)
    return os.environ.get(name, "")


sys.stdout.write(pattern.sub(replace, content))
PYEOF
