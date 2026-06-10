#!/bin/sh
set -eu

# mesotron7x-backup.sh
#
# Generic Restic backup engine configured entirely through environment
# variables. Create a small wrapper script for each backup job, export the
# MESOTRON7X_* variables, then exec this script.
#
# Required variables:
#   MESOTRON7X_SOURCE_DIR      Directory to back up.
#   MESOTRON7X_REPOSITORY      Local Restic repository path.
#
# Optional variables:
#   MESOTRON7X_VOLUME_DIR
#     Mounted volume path to verify before writing. If unset, the script only
#     checks that the repository parent directory exists and is writable.
#
#   MESOTRON7X_PRUNE_FREE_SPACE_THRESHOLD_BYTES
#     Free-space threshold for adding --prune to restic forget.
#     Default: 34359738368 (32 GiB).
#
#   MESOTRON7X_RESTIC_ARGS
#     Whitespace-delimited Restic global arguments. For example:
#       --insecure-no-password --compression max
#     Keep arguments simple; this interface does not support a single Restic
#     argument that itself contains whitespace.
#
#   MESOTRON7X_EXCLUDES
#     Newline-delimited Restic exclude patterns. Empty lines are ignored.
#
#   MESOTRON7X_KEEP_DAILY      Daily snapshots to keep. Default: 7.
#   MESOTRON7X_KEEP_WEEKLY     Weekly snapshots to keep. Default: 4.
#   MESOTRON7X_KEEP_MONTHLY    Monthly snapshots to keep. Default: 12.
#
# Example one-command wrapper:
#
#   #!/bin/sh
#   set -eu
#
#   MESOTRON7X_SOURCE_DIR="$HOME/Documents"
#   MESOTRON7X_VOLUME_DIR="/Volumes/BackupDrive"
#   MESOTRON7X_REPOSITORY="${MESOTRON7X_VOLUME_DIR}/Restic"
#   MESOTRON7X_RESTIC_ARGS="--insecure-no-password --compression max"
#   MESOTRON7X_EXCLUDES='.DS_Store
#   .TemporaryItems'
#
#   export MESOTRON7X_SOURCE_DIR
#   export MESOTRON7X_VOLUME_DIR
#   export MESOTRON7X_REPOSITORY
#   export MESOTRON7X_RESTIC_ARGS
#   export MESOTRON7X_EXCLUDES
#
#   exec "$HOME/.local/bin/mesotron7x-backup.sh"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_env() {
  eval "value=\${$1:-}"
  [ -n "$value" ] || die "Required environment variable is missing or empty: $1"
}

is_unsigned_integer() {
  case "$1" in
    ''|*[!0-9]*)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

require_unsigned_integer() {
  is_unsigned_integer "$2" || die "$1 must be an unsigned integer: $2"
}

repository_parent_dir() {
  case "$MESOTRON7X_REPOSITORY" in
    */*)
      printf '%s\n' "${MESOTRON7X_REPOSITORY%/*}"
      ;;
    *)
      printf '.\n'
      ;;
  esac
}

run_restic() {
  (
    set -f
    RESTIC_REPOSITORY=$MESOTRON7X_REPOSITORY
    export RESTIC_REPOSITORY
    # Intentionally split MESOTRON7X_RESTIC_ARGS into Restic arguments.
    # shellcheck disable=SC2086
    exec restic ${MESOTRON7X_RESTIC_ARGS:-} "$@"
  )
}

is_restic_repo_initialized() {
  [ -f "$MESOTRON7X_REPOSITORY/config" ]
}

is_volume_mounted() {
  mount | grep -F " on $MESOTRON7X_VOLUME_DIR " >/dev/null 2>&1
}

verify_storage_target() {
  if [ -n "${MESOTRON7X_VOLUME_DIR:-}" ]; then
    [ -d "$MESOTRON7X_VOLUME_DIR" ] || die "MESOTRON7X_VOLUME_DIR does not exist: $MESOTRON7X_VOLUME_DIR"
    is_volume_mounted || die "MESOTRON7X_VOLUME_DIR is not mounted: $MESOTRON7X_VOLUME_DIR"
    return
  fi

  parent_dir=$(repository_parent_dir)
  [ -d "$parent_dir" ] || die "Repository parent directory does not exist: $parent_dir"
  [ -w "$parent_dir" ] || die "Repository parent directory is not writable: $parent_dir"
}

verify_existing_repository_access() {
  run_restic snapshots --latest 1 >/dev/null || die "Existing Restic repository cannot be opened with the supplied MESOTRON7X_RESTIC_ARGS; refusing to migrate, overwrite, or reinitialize it: $MESOTRON7X_REPOSITORY"
}

free_space_check_path() {
  if [ -n "${MESOTRON7X_VOLUME_DIR:-}" ]; then
    printf '%s\n' "$MESOTRON7X_VOLUME_DIR"
  else
    repository_parent_dir
  fi
}

free_space_bytes() {
  path=$(free_space_check_path)
  available_kib=$(df -Pk "$path" | awk 'NR == 2 { print $4 }') || die "Failed to check free space for: $path"

  [ -n "$available_kib" ] || die "Could not parse free space for $path: empty value"
  is_unsigned_integer "$available_kib" || die "Could not parse free space for $path: $available_kib"
  [ "$available_kib" -gt 0 ] || die "Could not parse free space for $path: $available_kib"

  printf '%s\n' "$((available_kib * 1024))"
}

format_bytes_gib() {
  awk -v bytes="$1" 'BEGIN { printf "%.2f GiB", bytes / 1024 / 1024 / 1024 }'
}

backup_source() {
  set -- backup "$MESOTRON7X_SOURCE_DIR"

  if [ -n "${MESOTRON7X_EXCLUDES:-}" ]; then
    while IFS= read -r exclude_pattern; do
      [ -n "$exclude_pattern" ] || continue
      set -- "$@" --exclude "$exclude_pattern"
    done <<EOF
$MESOTRON7X_EXCLUDES
EOF
  fi

  run_restic "$@"
}

run_retention() {
  available_bytes=$(free_space_bytes)
  available_gib=$(format_bytes_gib "$available_bytes")

  log "Available space after backup: $available_gib ($available_bytes bytes)."

  set -- forget \
    --keep-daily "$MESOTRON7X_KEEP_DAILY" \
    --keep-weekly "$MESOTRON7X_KEEP_WEEKLY" \
    --keep-monthly "$MESOTRON7X_KEEP_MONTHLY"

  if [ "$available_bytes" -lt "$MESOTRON7X_PRUNE_FREE_SPACE_THRESHOLD_BYTES" ]; then
    log "Available space is below prune threshold; applying retention policy with prune."
    set -- "$@" --prune
  else
    log "Available space is at or above prune threshold; applying retention policy without prune."
  fi

  run_restic "$@"
}

main() {
  : "${MESOTRON7X_PRUNE_FREE_SPACE_THRESHOLD_BYTES:=34359738368}"
  : "${MESOTRON7X_RESTIC_ARGS:=}"
  : "${MESOTRON7X_KEEP_DAILY:=7}"
  : "${MESOTRON7X_KEEP_WEEKLY:=4}"
  : "${MESOTRON7X_KEEP_MONTHLY:=12}"

  require_env MESOTRON7X_SOURCE_DIR
  require_env MESOTRON7X_REPOSITORY
  require_unsigned_integer MESOTRON7X_PRUNE_FREE_SPACE_THRESHOLD_BYTES "$MESOTRON7X_PRUNE_FREE_SPACE_THRESHOLD_BYTES"
  require_unsigned_integer MESOTRON7X_KEEP_DAILY "$MESOTRON7X_KEEP_DAILY"
  require_unsigned_integer MESOTRON7X_KEEP_WEEKLY "$MESOTRON7X_KEEP_WEEKLY"
  require_unsigned_integer MESOTRON7X_KEEP_MONTHLY "$MESOTRON7X_KEEP_MONTHLY"

  require_command restic
  require_command mkdir
  require_command date
  require_command df
  require_command awk
  require_command mount
  require_command grep

  [ -d "$MESOTRON7X_SOURCE_DIR" ] || die "MESOTRON7X_SOURCE_DIR does not exist: $MESOTRON7X_SOURCE_DIR"
  verify_storage_target

  mkdir -p "$MESOTRON7X_REPOSITORY" || die "Failed to create MESOTRON7X_REPOSITORY: $MESOTRON7X_REPOSITORY"

  if ! is_restic_repo_initialized; then
    log "Initializing Restic repository at $MESOTRON7X_REPOSITORY."
    run_restic init
  else
    log "Verifying existing Restic repository."
    verify_existing_repository_access
  fi

  log "Starting Restic backup from $MESOTRON7X_SOURCE_DIR to $MESOTRON7X_REPOSITORY."
  backup_source

  log "Backup succeeded. Applying retention policy."
  run_retention

  log "Recent snapshots:"
  run_restic snapshots --latest 5

  log "Latest snapshot restore-size stats:"
  run_restic stats --mode restore-size latest

  log "Repository check:"
  run_restic check

  log "Backup workflow completed successfully."
}

main "$@"
