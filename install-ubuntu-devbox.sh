#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[install-ubuntu-devbox] %s\n' "$*"
}

die() {
  printf '[install-ubuntu-devbox] ERROR: %s\n' "$*" >&2
  exit 1
}

require_ubuntu_2204_or_newer() {
  if [[ ! -r /etc/os-release ]]; then
    die "cannot read /etc/os-release"
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    die "unsupported distribution: ${PRETTY_NAME:-unknown}; Ubuntu 22.04+ is required"
  fi

  local major minor
  IFS=. read -r major minor _ <<< "${VERSION_ID:-0.0}"
  major="${major:-0}"
  minor="${minor:-0}"

  if (( major < 22 || (major == 22 && minor < 4) )); then
    die "unsupported Ubuntu version: ${VERSION_ID:-unknown}; Ubuntu 22.04+ is required"
  fi
}

resolve_login_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s\n' "${SUDO_USER}"
  elif [[ -n "${USER:-}" && "${USER}" != "root" ]]; then
    printf '%s\n' "${USER}"
  else
    die "cannot determine the non-root login user"
  fi
}

install_packages() {
  local packages=(
    ca-certificates
    curl
    git
    git-lfs
    sudo
    tmux
    vim
  )

  log "installing required packages"
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
}

write_gitconfig() {
  local home_dir="$1"
  local target="${home_dir}/.gitconfig"

  log "writing ${target}"
  {
    cat <<'GITCONFIG'
[color]
	diff = auto
	status = auto
	branch = auto
	interactive = auto
	ui = true
	pager = true
[pager]
	branch = false
GITCONFIG

    if [[ -n "${GIT_USER_NAME:-}" || -n "${GIT_USER_EMAIL:-}" ]]; then
      printf '[user]\n'
      if [[ -n "${GIT_USER_EMAIL:-}" ]]; then
        printf '\temail = %s\n' "${GIT_USER_EMAIL}"
      fi
      if [[ -n "${GIT_USER_NAME:-}" ]]; then
        printf '\tname = %s\n' "${GIT_USER_NAME}"
      fi
    fi

    cat <<'GITCONFIG'
[credential]
	helper = store
[core]
	editor = /usr/bin/vim
	quotepath = false
[init]
	defaultBranch = main
[pull]
	ff = only
[filter "lfs"]
	clean = git-lfs clean -- %f
	smudge = git-lfs smudge -- %f
	process = git-lfs filter-process
	required = true
GITCONFIG

    if [[ -n "${GIT_LFS_URL:-}" ]]; then
      printf '[lfs]\n\turl = %s\n' "${GIT_LFS_URL}"
    fi
  } | sudo tee "${target}" >/dev/null
}

write_tmux_conf() {
  local home_dir="$1"
  local target="${home_dir}/.tmux.conf"

  log "writing ${target}"
  sudo tee "${target}" >/dev/null <<'TMUX'
set -g status-right 'CST #(TZ="Asia/Shanghai" date +"%%H:%%M:%%S")'
set -g mouse off
set -g status-interval 1
set -g default-command "${SHELL}"
set -g default-terminal "tmux-256color"
set-option -ga terminal-overrides ",xterm-256color:Tc,screen-256color:Tc,tmux-256color:Tc,xterm-ghostty:Tc"
set-option -g history-limit 1000000
set-window-option -g allow-rename off
set-window-option -g automatic-rename off
set-option -g renumber-windows on
bind '"' split-window -c "#{pane_current_path}"
bind % split-window -h -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"
bind -n PageUp copy-mode -u
bind -T copy-mode PageUp send-keys -X page-up
bind -T copy-mode PageDown send-keys -X page-down
TMUX
}

write_vimrc() {
  local home_dir="$1"
  local target="${home_dir}/.vimrc"

  log "writing ${target}"
  sudo tee "${target}" >/dev/null <<'VIMRC'
syntax on
let $LANG='en_US'
set langmenu=en_US
set encoding=utf8
set showcmd
set showmatch
set ignorecase
set smartcase
set autowrite
set hidden
set nobackup
set nowritebackup
set noswapfile
set noundofile
set nocompatible
set expandtab
set tabstop=4
set shiftwidth=4
set incsearch
set hlsearch
set backspace=indent,eol,start
set ruler
set autoindent
set smartindent
set cursorline
highlight CursorLine ctermbg=237 guibg=#d3d3d3 gui=NONE cterm=NONE
highlight Visual ctermbg=green guibg=green

if has("gui_running")
    set guioptions-=b " remove the bottom scrollbar
    set guioptions-=r " remove the right scrollbar
    set guioptions-=m " remove the menu
    set guioptions-=T " remove the toolbar
    set guifont=Ubuntu\ Mono:h13
    set lines=30 columns=100
endif
VIMRC
}

write_sudoers() {
  local login_user="$1"
  local safe_user="${login_user//[^A-Za-z0-9_.-]/_}"
  local target="/etc/sudoers.d/citadel-${safe_user}"
  local tmp

  tmp="$(mktemp)"
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${login_user}" > "${tmp}"

  log "writing ${target}"
  sudo chown root:root "${tmp}"
  sudo chmod 0440 "${tmp}"
  sudo visudo -cf "${tmp}" >/dev/null
  sudo install -o root -g root -m 0440 "${tmp}" "${target}"
  rm -f "${tmp}"
}

fix_ownership() {
  local login_user="$1"
  local home_dir="$2"

  sudo chown "${login_user}:${login_user}" \
    "${home_dir}/.gitconfig" \
    "${home_dir}/.tmux.conf" \
    "${home_dir}/.vimrc"
  sudo chmod 0644 \
    "${home_dir}/.gitconfig" \
    "${home_dir}/.tmux.conf" \
    "${home_dir}/.vimrc"
}

main() {
  require_ubuntu_2204_or_newer

  if ! command -v sudo >/dev/null 2>&1; then
    die "sudo is required to bootstrap this devbox"
  fi

  local login_user home_dir
  login_user="$(resolve_login_user)"
  home_dir="$(getent passwd "${login_user}" | cut -d: -f6)"

  if [[ -z "${home_dir}" || ! -d "${home_dir}" ]]; then
    die "cannot resolve home directory for ${login_user}"
  fi

  install_packages
  write_gitconfig "${home_dir}"
  write_tmux_conf "${home_dir}"
  write_vimrc "${home_dir}"
  write_sudoers "${login_user}"
  fix_ownership "${login_user}" "${home_dir}"

  log "done"
}

main "$@"
