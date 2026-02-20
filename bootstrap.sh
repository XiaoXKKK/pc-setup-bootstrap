#!/usr/bin/env bash

set -u

SCRIPT_NAME="$(basename "$0")"
OS_TYPE=""
PKG_MANAGER=""
SUDO_CMD=""
GITHUB_ACCESSIBLE=1
PROXY_URL=""
FAILURES=()
SUCCESSES=()
SKIPPED=()

log_info() {
  printf "[INFO] %s\n" "$1"
}

log_warn() {
  printf "[WARN] %s\n" "$1"
}

log_error() {
  printf "[ERROR] %s\n" "$1"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

record_success() {
  SUCCESSES+=("$1")
}

record_failure() {
  FAILURES+=("$1")
}

record_skip() {
  SKIPPED+=("$1")
}

ask_yes_no() {
  local prompt="$1"
  local default_answer="${2:-N}"
  local answer=""

  while true; do
    if [[ "$default_answer" == "Y" ]]; then
      read -r -p "$prompt [Y/n]: " answer
      answer="${answer:-Y}"
    else
      read -r -p "$prompt [y/N]: " answer
      answer="${answer:-N}"
    fi

    case "$answer" in
      Y|y) return 0 ;;
      N|n) return 1 ;;
      *) log_warn "请输入 y 或 n。" ;;
    esac
  done
}

read_input() {
  local prompt="$1"
  local value=""
  read -r -p "$prompt" value
  printf "%s" "$value"
}

run_step() {
  local step_name="$1"
  shift

  if "$@"; then
    record_success "$step_name"
  else
    record_failure "$step_name"
  fi
}

detect_os() {
  local uname_s
  uname_s="$(uname -s)"

  case "$uname_s" in
    Darwin) OS_TYPE="macos" ;;
    Linux) OS_TYPE="linux" ;;
    *)
      log_error "不支持的系统: $uname_s"
      return 1
      ;;
  esac

  log_info "检测到系统: $OS_TYPE"
  return 0
}

init_sudo_cmd() {
  if [[ "$EUID" -eq 0 ]]; then
    SUDO_CMD=""
  elif command_exists sudo; then
    SUDO_CMD="sudo"
  else
    log_warn "当前不是 root 且未检测到 sudo，某些安装步骤可能失败。"
    SUDO_CMD=""
  fi
}

ensure_homebrew() {
  if command_exists brew; then
    return 0
  fi

  log_info "未检测到 Homebrew，准备安装..."
  if ! ask_yes_no "是否立即安装 Homebrew？" "Y"; then
    log_warn "已跳过 Homebrew 安装。"
    return 1
  fi

  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  command_exists brew
}

detect_pkg_manager() {
  if [[ "$OS_TYPE" == "macos" ]]; then
    if ensure_homebrew; then
      PKG_MANAGER="brew"
      return 0
    fi
    log_error "macOS 需要 Homebrew 才能继续自动安装。"
    return 1
  fi

  if command_exists apt-get; then
    PKG_MANAGER="apt"
    return 0
  fi

  log_error "当前 Linux 未检测到 apt-get。最小版本仅支持 apt 系发行版。"
  return 1
}

check_url_access() {
  local url="$1"
  curl -fsSLI --connect-timeout 5 --max-time 10 "$url" >/dev/null 2>&1
}

check_github_connectivity() {
  if ! command_exists curl; then
    log_warn "未检测到 curl，无法检测 GitHub 连通性。"
    GITHUB_ACCESSIBLE=0
    return 1
  fi

  if check_url_access "https://github.com" && check_url_access "https://raw.githubusercontent.com"; then
    GITHUB_ACCESSIBLE=1
    log_info "GitHub 连通性正常。"
    return 0
  fi

  GITHUB_ACCESSIBLE=0
  log_warn "当前无法稳定访问 GitHub。"
  return 1
}

is_valid_proxy_url() {
  local value="$1"
  [[ "$value" =~ ^(http|https|socks5)://.+$ ]]
}

apply_proxy_env() {
  local proxy_url="$1"

  export http_proxy="$proxy_url"
  export https_proxy="$proxy_url"
  export all_proxy="$proxy_url"
  export HTTP_PROXY="$proxy_url"
  export HTTPS_PROXY="$proxy_url"
  export ALL_PROXY="$proxy_url"

  if command_exists git; then
    git config --global http.proxy "$proxy_url" >/dev/null 2>&1 || true
    git config --global https.proxy "$proxy_url" >/dev/null 2>&1 || true
  fi
}

persist_proxy_to_zshrc() {
  local proxy_url="$1"
  replace_or_append_zshrc_line '^export http_proxy=' "export http_proxy=\"$proxy_url\""
  replace_or_append_zshrc_line '^export https_proxy=' "export https_proxy=\"$proxy_url\""
  replace_or_append_zshrc_line '^export all_proxy=' "export all_proxy=\"$proxy_url\""
  replace_or_append_zshrc_line '^export HTTP_PROXY=' "export HTTP_PROXY=\"$proxy_url\""
  replace_or_append_zshrc_line '^export HTTPS_PROXY=' "export HTTPS_PROXY=\"$proxy_url\""
  replace_or_append_zshrc_line '^export ALL_PROXY=' "export ALL_PROXY=\"$proxy_url\""
}

download_flclash_by_url() {
  local download_url="$1"

  if [[ -z "$download_url" ]]; then
    log_warn "未提供 FlClash 安装包 URL。"
    return 1
  fi

  if ! command_exists curl; then
    log_error "未检测到 curl，无法下载 FlClash。"
    return 1
  fi

  if [[ "$OS_TYPE" == "macos" ]]; then
    local target="/tmp/FlClash-installer"
    curl -fL "$download_url" -o "$target" || return 1
    log_info "已下载 FlClash 安装包到 $target"
    if command_exists open; then
      open "$target" || true
    fi
    log_info "请完成 FlClash 图形化安装后返回终端继续。"
    return 0
  fi

  local linux_target_dir="$HOME/.local/bin"
  local linux_target="$linux_target_dir/flclash.AppImage"
  mkdir -p "$linux_target_dir"
  curl -fL "$download_url" -o "$linux_target" || return 1
  chmod +x "$linux_target"
  log_info "已下载 FlClash 到 $linux_target"
  log_info "可执行: $linux_target"
  return 0
}

step_install_flclash() {
  log_info "优先安装 FlClash"

  if command_exists flclash; then
    log_info "检测到 flclash 命令，跳过安装。"
    return 0
  fi

  if [[ "$OS_TYPE" == "macos" ]] && command_exists brew; then
    if brew list --cask flclash >/dev/null 2>&1 || brew install --cask flclash; then
      log_info "已通过 Homebrew 安装 FlClash。"
      return 0
    fi
    log_warn "通过 Homebrew 安装 FlClash 失败，将改为 URL 下载安装。"
  fi

  local flclash_url
  flclash_url="$(read_input "请输入 FlClash 安装包 URL（可从 https://github.com/chen08209/FlClash/releases 获取，留空则跳过）: ")"
  download_flclash_by_url "$flclash_url"
}

step_configure_proxy_url() {
  local value

  while true; do
    value="$(read_input "请输入代理 URL（示例: http://127.0.0.1:7890 或 socks5://127.0.0.1:7890）: ")"
    if is_valid_proxy_url "$value"; then
      PROXY_URL="$value"
      apply_proxy_env "$PROXY_URL"

      if ask_yes_no "是否将代理环境变量写入 ~/.zshrc 以持久化？" "Y"; then
        persist_proxy_to_zshrc "$PROXY_URL"
      fi

      log_info "代理已设置为: $PROXY_URL"
      return 0
    fi

    log_warn "URL 格式无效，请使用 http://、https:// 或 socks5:// 开头。"
  done
}

step_network_guard() {
  if check_github_connectivity; then
    return 0
  fi

  if ask_yes_no "检测到无法访问 GitHub，是否优先安装 FlClash 并配置代理 URL？" "Y"; then
    run_step "安装 FlClash" step_install_flclash
    run_step "配置代理 URL" step_configure_proxy_url

    if check_github_connectivity; then
      log_info "代理配置后 GitHub 连通性已恢复。"
      return 0
    fi

    log_warn "GitHub 仍不可达，后续依赖 GitHub 的步骤可能失败。"
    return 1
  fi

  record_skip "FlClash 与代理配置"
  return 1
}

install_with_brew() {
  local package="$1"
  local type="${2:-formula}"

  if [[ "$type" == "cask" ]]; then
    brew list --cask "$package" >/dev/null 2>&1 || brew install --cask "$package"
  else
    brew list "$package" >/dev/null 2>&1 || brew install "$package"
  fi
}

install_with_apt() {
  local package="$1"
  $SUDO_CMD apt-get update -y >/dev/null 2>&1
  $SUDO_CMD apt-get install -y "$package"
}

install_pkg() {
  local package="$1"
  local type="${2:-formula}"

  case "$PKG_MANAGER" in
    brew)
      install_with_brew "$package" "$type"
      ;;
    apt)
      install_with_apt "$package"
      ;;
    *)
      log_error "未知包管理器: $PKG_MANAGER"
      return 1
      ;;
  esac
}

step_install_git() {
  log_info "安装 Git"
  if command_exists git; then
    log_info "Git 已安装，跳过。"
    return 0
  fi
  install_pkg git
}

step_install_nodejs() {
  log_info "安装 Node.js（含 npm）"

  if command_exists node && command_exists npm; then
    log_info "Node.js 与 npm 已安装，跳过。"
    return 0
  fi

  if [[ "$PKG_MANAGER" == "brew" ]]; then
    install_pkg node
    return $?
  fi

  install_pkg nodejs && install_pkg npm
}

step_install_cmake() {
  log_info "安装 CMake"
  if command_exists cmake; then
    log_info "CMake 已安装，跳过。"
    return 0
  fi
  install_pkg cmake
}

step_install_vscode() {
  log_info "安装 VS Code"
  if command_exists code; then
    log_info "检测到 code 命令，VS Code 可能已安装，跳过。"
    return 0
  fi

  if [[ "$PKG_MANAGER" == "brew" ]]; then
    install_pkg visual-studio-code cask
    return $?
  fi

  if install_pkg code; then
    return 0
  fi

  if command_exists snap; then
    log_warn "apt 安装 code 失败，尝试使用 snap。"
    $SUDO_CMD snap install code --classic
    return $?
  fi

  log_warn "未能自动安装 VS Code。请手动安装后继续。"
  return 1
}

step_install_claude_cli() {
  log_info "安装 Claude CLI"

  if command_exists claude; then
    log_info "Claude CLI 已安装，跳过。"
    return 0
  fi

  if ! command_exists curl; then
    log_error "未检测到 curl，无法执行 Claude 官方安装脚本。"
    return 1
  fi

  curl -fsSL https://claude.ai/install.sh | bash
}

step_install_claude_settings() {
  local settings_repo="https://github.com/feiskyer/claude-code-settings.git"
  local target_dir="$HOME/.claude"
  local backup_dir="${target_dir}.bak"

  log_info "安装 Claude settings"

  if ! command_exists git; then
    log_error "未检测到 git，无法拉取 Claude settings。"
    return 1
  fi

  if [[ -e "$target_dir" ]]; then
    if [[ -e "$backup_dir" ]]; then
      backup_dir="${target_dir}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    log_warn "检测到已存在的 $target_dir，已备份到 $backup_dir"
    mv "$target_dir" "$backup_dir" || return 1
  fi

  git clone "$settings_repo" "$target_dir"
}

step_install_copilot_api() {
  log_info "安装 copilot-api"

  if ! command_exists npm; then
    log_error "未检测到 npm，请先安装 Node.js。"
    return 1
  fi

  if npm list -g --depth=0 copilot-api >/dev/null 2>&1; then
    log_info "copilot-api 已安装，跳过。"
    return 0
  fi

  npm install -g copilot-api
}

step_install_zsh() {
  log_info "安装 zsh"
  if command_exists zsh; then
    log_info "zsh 已安装，跳过。"
    return 0
  fi
  install_pkg zsh
}

step_install_oh_my_zsh() {
  local ohmyzsh_dir="$HOME/.oh-my-zsh"
  log_info "安装 oh-my-zsh"

  if [[ -d "$ohmyzsh_dir" ]]; then
    log_info "oh-my-zsh 已存在，跳过。"
    return 0
  fi

  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

ensure_plugin_repo() {
  local plugin_name="$1"
  local plugin_git="$2"
  local custom_plugins_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
  local plugin_dir="$custom_plugins_dir/$plugin_name"

  mkdir -p "$custom_plugins_dir"
  if [[ -d "$plugin_dir/.git" ]]; then
    return 0
  fi

  git clone --depth=1 "$plugin_git" "$plugin_dir"
}

replace_or_append_zshrc_line() {
  local key_regex="$1"
  local new_line="$2"
  local zshrc="$HOME/.zshrc"

  touch "$zshrc"
  if grep -Eq "$key_regex" "$zshrc"; then
    local temp_file
    temp_file="$(mktemp)"
    sed -E "s|$key_regex.*|$new_line|" "$zshrc" > "$temp_file"
    mv "$temp_file" "$zshrc"
  else
    printf "\n%s\n" "$new_line" >> "$zshrc"
  fi
}

step_configure_theme_plugins() {
  local zshrc="$HOME/.zshrc"
  local plugin_line='plugins=(git zsh-autosuggestions zsh-syntax-highlighting)'
  local theme_line='ZSH_THEME="robbyrussell"'

  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log_error "oh-my-zsh 未安装，无法配置主题与插件。"
    return 1
  fi

  if ! command_exists git; then
    log_error "需要 git 来下载插件。"
    return 1
  fi

  ensure_plugin_repo "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git" || return 1
  ensure_plugin_repo "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git" || return 1

  replace_or_append_zshrc_line '^ZSH_THEME=' "$theme_line"
  replace_or_append_zshrc_line '^plugins=' "$plugin_line"

  if ! grep -Eq '^export ZSH=' "$zshrc"; then
    printf "\nexport ZSH=\"$HOME/.oh-my-zsh\"\n" >> "$zshrc"
  fi
  if ! grep -Eq '^source \$ZSH/oh-my-zsh.sh' "$zshrc"; then
    printf "source \$ZSH/oh-my-zsh.sh\n" >> "$zshrc"
  fi

  log_info "已写入主题与插件配置到 ~/.zshrc"
  return 0
}

step_set_default_shell() {
  local zsh_path
  zsh_path="$(command -v zsh || true)"

  if [[ -z "$zsh_path" ]]; then
    log_error "未检测到 zsh，无法切换默认 shell。"
    return 1
  fi

  if [[ "$SHELL" == "$zsh_path" ]]; then
    log_info "默认 shell 已是 zsh。"
    return 0
  fi

  log_info "尝试切换默认 shell 到: $zsh_path"
  if chsh -s "$zsh_path" "$USER"; then
    log_info "默认 shell 切换成功。"
    return 0
  fi

  log_warn "自动切换失败。可手动执行: chsh -s $zsh_path $USER"
  return 1
}

print_summary() {
  local -a success_items
  local -a failure_items
  local -a skipped_items
  local item

  success_items=("${SUCCESSES[@]-}")
  failure_items=("${FAILURES[@]-}")
  skipped_items=("${SKIPPED[@]-}")

  printf "\n===== 初始化结果汇总 =====\n"

  printf "\n成功项目 (%d):\n" "${#success_items[@]}"
  for item in "${success_items[@]}"; do
    [[ -z "$item" ]] && continue
    printf "  - %s\n" "$item"
  done

  printf "\n失败项目 (%d):\n" "${#failure_items[@]}"
  for item in "${failure_items[@]}"; do
    [[ -z "$item" ]] && continue
    printf "  - %s\n" "$item"
  done

  printf "\n跳过项目 (%d):\n" "${#skipped_items[@]}"
  for item in "${skipped_items[@]}"; do
    [[ -z "$item" ]] && continue
    printf "  - %s\n" "$item"
  done

  printf "\n建议执行: exec zsh\n"
  printf "=========================\n"
}

main() {
  printf "=== 新电脑初始化脚本（macOS/Linux 最小版）===\n"
  printf "脚本: %s\n\n" "$SCRIPT_NAME"

  detect_os || exit 1
  init_sudo_cmd
  run_step "网络预检与代理引导" step_network_guard
  detect_pkg_manager || log_warn "部分安装步骤可能不可用。"

  if ask_yes_no "[分段] 是否安装基础开发工具（git/nodejs/cmake）？" "Y"; then
    run_step "安装 Git" step_install_git
    run_step "安装 Node.js" step_install_nodejs
    run_step "安装 CMake" step_install_cmake
  else
    record_skip "基础开发工具（git/nodejs/cmake）"
  fi

  if ask_yes_no "[分段] 是否安装 VS Code？" "Y"; then
    run_step "安装 VS Code" step_install_vscode
  else
    record_skip "VS Code"
  fi

  if ask_yes_no "[分段] 是否安装 Claude CLI？" "Y"; then
    run_step "安装 Claude CLI" step_install_claude_cli
  else
    record_skip "Claude CLI"
  fi

  if ask_yes_no "[分段] 是否安装 Claude settings（~/.claude）？" "Y"; then
    run_step "安装 Claude settings" step_install_claude_settings
  else
    record_skip "Claude settings（~/.claude）"
  fi

  if ask_yes_no "[分段] 是否安装 copilot-api（npm -g）？" "Y"; then
    run_step "安装 copilot-api" step_install_copilot_api
  else
    record_skip "copilot-api"
  fi

  if ask_yes_no "[分段] 是否安装 zsh？" "Y"; then
    run_step "安装 zsh" step_install_zsh
  else
    record_skip "zsh"
  fi

  if ask_yes_no "[分段] 是否安装 oh-my-zsh？" "Y"; then
    run_step "安装 oh-my-zsh" step_install_oh_my_zsh
  else
    record_skip "oh-my-zsh"
  fi

  if ask_yes_no "[分段] 是否配置 oh-my-zsh 主题和插件？" "Y"; then
    run_step "配置主题与插件" step_configure_theme_plugins
  else
    record_skip "oh-my-zsh 主题与插件"
  fi

  if ask_yes_no "[分段] 是否尝试将默认 shell 切换为 zsh？" "Y"; then
    run_step "切换默认 shell 为 zsh" step_set_default_shell
  else
    record_skip "切换默认 shell 为 zsh"
  fi

  print_summary

  if [[ "${#FAILURES[@]}" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"