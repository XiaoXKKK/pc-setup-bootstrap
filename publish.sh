#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DEFAULT="pc-setup-bootstrap"

ask_value() {
  local prompt="$1"
  local default_value="${2:-}"
  local input=""

  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt [$default_value]: " input
    printf "%s" "${input:-$default_value}"
  else
    read -r -p "$prompt: " input
    printf "%s" "$input"
  fi
}

ensure_git_repo() {
  if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  git -C "$SCRIPT_DIR" init
  git -C "$SCRIPT_DIR" branch -M main
}

commit_changes() {
  git -C "$SCRIPT_DIR" add .
  if ! git -C "$SCRIPT_DIR" diff --cached --quiet; then
    git -C "$SCRIPT_DIR" commit -m "chore: setup interactive bootstrap project"
  fi
}

set_remote() {
  local owner="$1"
  local repo="$2"
  local remote_url="https://github.com/$owner/$repo.git"

  if git -C "$SCRIPT_DIR" remote get-url origin >/dev/null 2>&1; then
    git -C "$SCRIPT_DIR" remote set-url origin "$remote_url"
  else
    git -C "$SCRIPT_DIR" remote add origin "$remote_url"
  fi
}

create_repo_with_gh_if_needed() {
  local owner="$1"
  local repo="$2"

  if ! command -v gh >/dev/null 2>&1; then
    return 0
  fi

  if gh repo view "$owner/$repo" >/dev/null 2>&1; then
    return 0
  fi

  if gh auth status >/dev/null 2>&1; then
    gh repo create "$owner/$repo" --public --confirm
  fi
}

push_main() {
  git -C "$SCRIPT_DIR" push -u origin main
}

enable_pages_if_possible() {
  local owner_repo="$1"

  if ! command -v gh >/dev/null 2>&1; then
    echo "[WARN] 未检测到 gh，无法自动启用 GitHub Pages。"
    return 0
  fi

  if ! gh auth status >/dev/null 2>&1; then
    echo "[WARN] gh 未登录，无法自动启用 GitHub Pages。"
    return 0
  fi

  if gh api "repos/$owner_repo/pages" >/dev/null 2>&1; then
    gh api "repos/$owner_repo/pages" -X PUT -f source[branch]=main -f source[path]=/docs >/dev/null
    return 0
  fi

  gh api "repos/$owner_repo/pages" -X POST -f source[branch]=main -f source[path]=/docs >/dev/null
}

main() {
  echo "=== 发布到 GitHub 与 GitHub Pages ==="

  local owner
  local repo
  owner="$(ask_value "请输入 GitHub 用户名（owner）")"
  repo="$(ask_value "请输入仓库名" "$REPO_DEFAULT")"

  if [[ -z "$owner" || -z "$repo" ]]; then
    echo "[ERROR] owner/repo 不能为空。"
    exit 1
  fi

  ensure_git_repo
  commit_changes
  create_repo_with_gh_if_needed "$owner" "$repo"
  set_remote "$owner" "$repo"
  push_main
  enable_pages_if_possible "$owner/$repo"

  echo
  echo "发布完成。"
  echo "一行命令（raw）:"
    echo "一行命令（GitHub Pages）:"
    echo "curl -fsSL https://$owner.github.io/$repo/bootstrap.sh | bash"
  echo
  echo "GitHub Pages（若已开启）:"
  echo "https://$owner.github.io/$repo/"
}

main "$@"
