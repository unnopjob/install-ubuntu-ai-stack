#!/usr/bin/env bash
set -euo pipefail

MODEL="${OLLAMA_MODEL:-gemma2:9b}"
FLOWISE_PORT="${FLOWISE_PORT:-3000}"
NODE_MAJOR="${NODE_MAJOR:-22}"
ENABLE_SWAP="${ENABLE_SWAP:-0}"
SWAP_SIZE_GB="${SWAP_SIZE_GB:-8}"
ENABLE_PM2_LOGROTATE="${ENABLE_PM2_LOGROTATE:-1}"
RUN_MODEL_SMOKE_TEST="${RUN_MODEL_SMOKE_TEST:-1}"
CREATE_DESKTOP_LAUNCHER="${CREATE_DESKTOP_LAUNCHER:-1}"
MIN_FREE_DISK_GB="${MIN_FREE_DISK_GB:-25}"
MIN_RAM_GB_WARN="${MIN_RAM_GB_WARN:-16}"
SPINNER_ENABLED="${SPINNER_ENABLED:-1}"
ACTION="install"
SCRIPT_PATH=""
INSTALLER_URL="${INSTALLER_URL:-https://raw.githubusercontent.com/unnopjob/install-ubuntu-ai-stack/main/install.sh}"
LINUX_FAMILY=""
SUDO_KEEPALIVE_PID=""
INSTALL_PROGRESS_TOTAL=0
INSTALL_PROGRESS_STEP=0

log() {
  printf '\n[%s] %s\n' "$(date +'%H:%M:%S')" "$(progress_label "$*")"
}

warn() {
  printf '[WARN] %s\n' "$(progress_label "$*")" >&2
}

die() {
  printf '[ERROR] %s\n' "$(progress_label "$*")" >&2
  exit 1
}

progress_label() {
  local label="$1"

  if [[ "${INSTALL_PROGRESS_TOTAL}" =~ ^[0-9]+$ && "${INSTALL_PROGRESS_STEP}" =~ ^[0-9]+$ && "${INSTALL_PROGRESS_TOTAL}" -gt 0 && "${INSTALL_PROGRESS_STEP}" -gt 0 ]]; then
    printf '[%s/%s] %s' "$INSTALL_PROGRESS_STEP" "$INSTALL_PROGRESS_TOTAL" "$label"
  else
    printf '%s' "$label"
  fi
}

spinner_supported() {
  [[ "${SPINNER_ENABLED}" == "1" && -z "${CI:-}" ]] || return 1
  [[ -t 1 || -t 2 ]]
}

run_with_spinner() {
  local label="$1"
  shift
  local display_label

  display_label="$(progress_label "$label")"

  if ! spinner_supported; then
    log "$label"
    "$@"
    return
  fi

  local output_file
  local pid
  local status
  local spin_chars='|/-\'
  local spin_index=0

  output_file="$(mktemp)"
  printf '[%s] %s... ' "$(date +'%H:%M:%S')" "$display_label" >&2

  "$@" >"$output_file" 2>&1 &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\033[K[%s] %s... %s' "$(date +'%H:%M:%S')" "$display_label" "${spin_chars:spin_index%4:1}" >&2
    sleep 0.1
    ((spin_index++))
  done

  if wait "$pid"; then
    status=0
  else
    status=$?
  fi

  if (( status == 0 )); then
    printf '\r\033[K[%s] %s... done\n' "$(date +'%H:%M:%S')" "$display_label" >&2
  else
    printf '\r\033[K[%s] %s... failed\n' "$(date +'%H:%M:%S')" "$display_label" >&2
    if [[ -s "$output_file" ]]; then
      tail -n 80 "$output_file" >&2 || true
    fi
  fi

  rm -f "$output_file"
  return "$status"
}

detect_script_path() {
  SCRIPT_PATH=""

  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    SCRIPT_PATH="$script_dir/$(basename "${BASH_SOURCE[0]}")"
  fi
}

detect_platform() {
  [[ "$(uname -s)" == "Linux" ]] || die "This installer supports Ubuntu/Debian and Fedora/RedHat-family Linux only."

  [[ -f /etc/os-release ]] || die "Linux detected, but /etc/os-release is missing."
  # shellcheck disable=SC1091
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *" debian "*|*" ubuntu "*) LINUX_FAMILY="debian" ;;
    *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*|*" amzn "*)
      LINUX_FAMILY="rpm"
      ;;
    *)
      die "Unsupported Linux distribution: ${ID:-unknown} (${ID_LIKE:-unknown})."
      ;;
  esac
}

port_listening() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | awk -v port=":${port}" 'NR > 1 && $4 ~ port "$" { found = 1 } END { exit !found }'; then
      return 0
    fi
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && return 0
  fi

  return 1
}

open_url() {
  local url="$1"

  if command -v xdg-open >/dev/null 2>&1 && { [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; }; then
    xdg-open "$url" >/dev/null 2>&1 &
    return 0
  fi

  printf 'Open this URL: %s\n' "$url"
}

installer_invocation() {
  if [[ -n "$SCRIPT_PATH" ]]; then
    printf '%s' "$SCRIPT_PATH"
  else
    printf 'curl -fsSL %s | bash -s --' "$INSTALLER_URL"
  fi
}

usage() {
  cat <<EOF
Usage:
  $(installer_invocation) [--install|--status|--open-flowise|--help]

Commands:
  --install       Install Ollama, ${MODEL}, Node.js, Flowise, and PM2
  --status        Show versions and service health
  --open-flowise  Open the local Flowise UI in a browser
  --help          Show this help

Environment:
  OLLAMA_MODEL=${MODEL}
  FLOWISE_PORT=${FLOWISE_PORT}
  NODE_MAJOR=${NODE_MAJOR}
  INSTALLER_URL=${INSTALLER_URL}
  ENABLE_SWAP=${ENABLE_SWAP}
  SWAP_SIZE_GB=${SWAP_SIZE_GB}
  ENABLE_PM2_LOGROTATE=${ENABLE_PM2_LOGROTATE}
  RUN_MODEL_SMOKE_TEST=${RUN_MODEL_SMOKE_TEST}
  CREATE_DESKTOP_LAUNCHER=${CREATE_DESKTOP_LAUNCHER}
  MIN_FREE_DISK_GB=${MIN_FREE_DISK_GB}
  MIN_RAM_GB_WARN=${MIN_RAM_GB_WARN}
  SPINNER_ENABLED=${SPINNER_ENABLED}
EOF
}

parse_args() {
  local arg

  for arg in "$@"; do
    case "$arg" in
      --install)
        ACTION="install"
        ;;
      --status)
        ACTION="status"
        ;;
      --open-flowise|--open)
        ACTION="open"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $arg"
        ;;
    esac
  done
}

cleanup() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
}

require_service_manager() {
  command -v systemctl >/dev/null 2>&1 || die "systemd/systemctl is required on Linux."
}

require_non_root() {
  [[ "${EUID}" -ne 0 ]] || die "Run this as your normal user. The script will call sudo when needed."
}

need_cmds() {
  local missing=()
  local cmd

  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    die "Missing required commands: ${missing[*]}"
  fi
}

http_ready() {
  local url="$1"
  local attempts="${2:-30}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

wait_for_http() {
  local label="$1"
  local url="$2"
  local attempts="${3:-60}"
  local attempt
  local spin_index=0
  local spin_chars='|/-\'
  local display_label

  display_label="$(progress_label "$label")"

  if spinner_supported; then
    printf '[%s] %s... ' "$(date +'%H:%M:%S')" "$display_label" >&2
    for ((attempt = 1; attempt <= attempts; attempt++)); do
      if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
        printf '\r\033[K[%s] %s... done\n' "$(date +'%H:%M:%S')" "$display_label" >&2
        return 0
      fi
      printf '\r\033[K[%s] %s... %s' "$(date +'%H:%M:%S')" "$display_label" "${spin_chars:spin_index%4:1}" >&2
      ((spin_index++))
      sleep 2
    done
    printf '\r\033[K[%s] %s... failed\n' "$(date +'%H:%M:%S')" "$display_label" >&2
    die "$label did not become ready at $url"
  fi

  if http_ready "$url" "$attempts"; then
    return 0
  fi

  die "$label did not become ready at $url"
}

check_preflight() {
  local free_disk_gb
  local total_ram_gb

  need_cmds curl sudo awk grep sed df mktemp

  if ! curl -fsI --max-time 10 https://ollama.com >/dev/null 2>&1; then
    warn "Could not reach ollama.com right now. The install may still work if the network issue is temporary."
  fi

  if ! curl -fsI --max-time 10 https://registry.npmjs.org >/dev/null 2>&1; then
    warn "Could not reach the npm registry right now."
  fi

  free_disk_gb="$(df -Pk / | awk 'NR==2 {print int($4 / 1024 / 1024)}')"
  if (( free_disk_gb < MIN_FREE_DISK_GB )); then
    die "Only ${free_disk_gb}G free on /; please free up space before installing."
  fi

  total_ram_gb="$(awk '/MemTotal:/ {print int($2 / 1024 / 1024)}' /proc/meminfo)"

  if (( total_ram_gb < MIN_RAM_GB_WARN )); then
    warn "Only ${total_ram_gb}G RAM detected. gemma2:9b may need swap or may run slowly."
  fi

  if command -v nvidia-smi >/dev/null 2>&1; then
    log "NVIDIA GPU detected."
  else
    warn "No nvidia-smi detected. This stack will run in CPU mode unless GPU drivers are already installed."
  fi

  if port_listening 11434 || port_listening "$FLOWISE_PORT"; then
    warn "Port 11434 or ${FLOWISE_PORT} is already listening. The install may collide with an existing service."
  fi
}

install_prereqs() {
  if [[ "$LINUX_FAMILY" == "debian" ]]; then
    run_with_spinner "Updating apt metadata" sudo apt-get update
    run_with_spinner "Installing prerequisites" sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
      build-essential \
      ca-certificates \
      curl \
      gnupg \
      iproute2 \
      lsb-release \
      python3 \
      xdg-utils \
      zstd
  else
    local pkg_mgr

    if command -v dnf >/dev/null 2>&1; then
      pkg_mgr="dnf"
    else
      pkg_mgr="yum"
    fi

    run_with_spinner "Refreshing package metadata" sudo "$pkg_mgr" makecache --refresh
    run_with_spinner "Installing prerequisites" sudo "$pkg_mgr" install -y \
      ca-certificates \
      curl \
      gnupg2 \
      gcc-c++ \
      make \
      iproute \
      python3 \
      xdg-utils \
      zstd
  fi
}

maybe_setup_swap() {
  local current_swap_kb
  local swap_path
  local required_bytes
  local free_bytes

  if [[ "$ENABLE_SWAP" != "1" ]]; then
    log "Swap setup disabled. Set ENABLE_SWAP=1 to create a swap file."
    return 0
  fi

  current_swap_kb="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)"
  if (( current_swap_kb > 0 )); then
    log "Existing swap detected. Skipping swap file creation."
    return 0
  fi

  swap_path="${SWAP_PATH:-/swapfile}"
  required_bytes=$((SWAP_SIZE_GB * 1024 * 1024 * 1024))
  free_bytes="$(df --output=avail -B1 / | tail -n 1 | tr -d ' ')"

  if (( free_bytes < required_bytes )); then
    warn "Not enough free disk to create a ${SWAP_SIZE_GB}G swap file at ${swap_path}. Skipping swap."
    return 0
  fi

  if [[ ! -e "$swap_path" ]]; then
    log "Creating ${SWAP_SIZE_GB}G swap file at ${swap_path}..."
    if command -v fallocate >/dev/null 2>&1; then
      if ! sudo fallocate -l "${SWAP_SIZE_GB}G" "$swap_path"; then
        warn "fallocate failed; falling back to dd."
        sudo dd if=/dev/zero of="$swap_path" bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
      fi
    else
      sudo dd if=/dev/zero of="$swap_path" bs=1M count=$((SWAP_SIZE_GB * 1024)) status=progress
    fi
    sudo chmod 600 "$swap_path"
  else
    log "Swap file ${swap_path} already exists. Reusing it."
  fi

  sudo chmod 600 "$swap_path"

  if ! swapon --show=NAME --noheadings 2>/dev/null | awk '{print $1}' | grep -Fxq "$swap_path"; then
    sudo mkswap "$swap_path" >/dev/null
  fi

  if ! swapon --show=NAME --noheadings 2>/dev/null | awk '{print $1}' | grep -Fxq "$swap_path"; then
    sudo swapon "$swap_path"
  fi

  if ! grep -qE "^[^#].*[[:space:]]${swap_path//\//\\/}[[:space:]]swap[[:space:]]" /etc/fstab; then
    echo "${swap_path} none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
  fi

  log "Swap is ready at ${swap_path}."
}

install_ollama() {
  if command -v ollama >/dev/null 2>&1; then
    log "Ollama already installed: $(command -v ollama)"
  else
    run_with_spinner "Installing Ollama from the official installer" bash -lc 'curl -fsSL https://ollama.com/install.sh | sh'
  fi

  run_with_spinner "Starting Ollama service" sudo systemctl enable --now ollama

  log "Waiting for Ollama to answer on localhost:11434..."
  wait_for_http "Ollama" "http://127.0.0.1:11434/api/tags"

  log "Pulling model ${MODEL}..."
  ollama pull "$MODEL"

  if [[ "$RUN_MODEL_SMOKE_TEST" == "1" ]]; then
    run_ollama_smoke_test
  else
    log "Skipping Ollama smoke test."
  fi
}

run_ollama_smoke_test() {
  local response_file

  response_file="$(mktemp)"
  log "Running an Ollama API smoke test for ${MODEL}..."

  if curl -fsS --max-time 180 "http://127.0.0.1:11434/api/generate" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL}\",\"prompt\":\"Reply with exactly OK.\",\"stream\":false}" \
    >"$response_file"; then
    if grep -q '"done":true' "$response_file"; then
      log "Ollama smoke test passed."
    else
      warn "Ollama answered but the response did not look complete. Check ${response_file}."
    fi
  else
    warn "Ollama smoke test failed. Check ${response_file}."
  fi

  rm -f "$response_file"
}

install_node_and_global_tools() {
  if [[ "$LINUX_FAMILY" == "debian" ]]; then
    run_with_spinner "Adding NodeSource repository for Node.js ${NODE_MAJOR}.x" bash -lc "curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | sudo -E bash -"
    run_with_spinner "Installing Node.js" sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
  else
    run_with_spinner "Adding NodeSource repository for Node.js ${NODE_MAJOR}.x" bash -lc "curl -fsSL https://rpm.nodesource.com/setup_${NODE_MAJOR}.x | sudo bash -"
    if command -v dnf >/dev/null 2>&1; then
      run_with_spinner "Installing Node.js" sudo dnf install -y nodejs
    else
      run_with_spinner "Installing Node.js" sudo yum install -y nodejs
    fi
  fi

  export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
  hash -r

  command -v node >/dev/null 2>&1 || die "node was not found in PATH after installation."
  command -v npm >/dev/null 2>&1 || die "npm was not found in PATH after installation."

  log "Node version: $(node -v)"
  log "npm version: $(npm -v)"

  run_with_spinner "Installing Flowise and PM2 globally" sudo npm install -g --unsafe-perm flowise pm2

  export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
  hash -r

  command -v flowise >/dev/null 2>&1 || die "flowise was not found in PATH after installation."
  command -v pm2 >/dev/null 2>&1 || die "pm2 was not found in PATH after installation."
}

configure_flowise_pm2() {
  local flowise_bin
  local pm2_bin
  local node_bin_dir
  local -a startup_cmd

  flowise_bin="$(command -v flowise)"
  pm2_bin="$(command -v pm2)"
  node_bin_dir="$(dirname "$(command -v node)")"

  if "$pm2_bin" describe flowise >/dev/null 2>&1; then
    run_with_spinner "Restarting Flowise under PM2" env PORT="$FLOWISE_PORT" "$pm2_bin" restart flowise --update-env
  else
    run_with_spinner "Starting Flowise under PM2" env PORT="$FLOWISE_PORT" "$pm2_bin" start "$flowise_bin" --name flowise -- start
  fi

  run_with_spinner "Saving the PM2 process list" "$pm2_bin" save

  log "Registering the PM2 startup hook for user ${USER}..."
  startup_cmd=(sudo env PATH="$PATH:$node_bin_dir" "$pm2_bin" startup systemd -u "$USER" --hp "$HOME")

  run_with_spinner "Registering the PM2 startup hook" "${startup_cmd[@]}" || warn "PM2 startup hook returned a non-zero status; review the output above."

  run_with_spinner "Saving the PM2 process list again" "$pm2_bin" save
}

configure_pm2_logrotate() {
  local pm2_bin

  if [[ "$ENABLE_PM2_LOGROTATE" != "1" ]]; then
    log "PM2 log rotation disabled. Set ENABLE_PM2_LOGROTATE=1 to enable it."
    return 0
  fi

  pm2_bin="$(command -v pm2)"

  run_with_spinner "Configuring PM2 log rotation" sudo env PATH="$PATH" "$pm2_bin" logrotate -u "$USER" || warn "PM2 log rotation setup failed; you can run 'sudo pm2 logrotate -u $USER' later."
}

create_gui_launchers() {
  local bin_dir
  local app_dir
  local desktop_dir
  local open_launcher
  local install_launcher
  local flowise_desktop
  local install_desktop

  if [[ "$CREATE_DESKTOP_LAUNCHER" != "1" ]]; then
    log "GUI launcher creation disabled. Set CREATE_DESKTOP_LAUNCHER=1 to enable it."
    return 0
  fi

  bin_dir="$HOME/.local/bin"
  desktop_dir="$HOME/Desktop"
  open_launcher="$bin_dir/open-flowise"
  install_launcher="$bin_dir/install-ai-stack"

  mkdir -p "$bin_dir"

  cat >"$open_launcher" <<EOF
#!/usr/bin/env bash
set -euo pipefail

URL="http://127.0.0.1:${FLOWISE_PORT}"

if ! curl -fsS --max-time 3 "$URL" >/dev/null 2>&1; then
  if command -v pm2 >/dev/null 2>&1; then
    pm2 resurrect >/dev/null 2>&1 || true
  fi
  for _ in {1..30}; do
    if curl -fsS --max-time 3 "$URL" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

if command -v xdg-open >/dev/null 2>&1 && { [[ -n "\${DISPLAY:-}" ]] || [[ -n "\${WAYLAND_DISPLAY:-}" ]]; }; then
  xdg-open "$URL" >/dev/null 2>&1 &
else
  printf 'Open this URL: %s\n' "$URL"
fi
EOF
  chmod 755 "$open_launcher"

  cat >"$install_launcher" <<EOF
#!/usr/bin/env bash
set -euo pipefail

INSTALLER_URL="$INSTALLER_URL"
SCRIPT_PATH="$SCRIPT_PATH"
if [[ -n "$SCRIPT_PATH" ]]; then
  exec "$SCRIPT_PATH" "\$@"
fi

export INSTALLER_URL
exec bash -c 'curl -fsSL "$INSTALLER_URL" | bash -s -- "$@"' bash "\$@"
EOF
  chmod 755 "$install_launcher"

  app_dir="$HOME/.local/share/applications"
  flowise_desktop="$app_dir/Flowise.desktop"
  install_desktop="$app_dir/Install AI Stack.desktop"
  mkdir -p "$app_dir"

  cat >"$flowise_desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Flowise
Comment=Open the local Flowise dashboard
Exec=$open_launcher
Terminal=false
Categories=Network;Development;
Icon=web-browser
EOF
  chmod 755 "$flowise_desktop"

  cat >"$install_desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Install AI Stack
Comment=Run the AI stack installer
Exec=$install_launcher
Terminal=true
Categories=Utility;Development;
Icon=system-run
EOF
  chmod 755 "$install_desktop"

  if [[ -d "$desktop_dir" ]]; then
    cp -f "$flowise_desktop" "$desktop_dir/Flowise.desktop" 2>/dev/null || true
    chmod 755 "$desktop_dir/Flowise.desktop" 2>/dev/null || true
    cp -f "$install_desktop" "$desktop_dir/Install AI Stack.desktop" 2>/dev/null || true
    chmod 755 "$desktop_dir/Install AI Stack.desktop" 2>/dev/null || true
  fi
  log "GUI launchers installed under ~/.local/share/applications and, if available, the Desktop."
}

health_checks() {
  local pm2_bin

  log "Running post-install health checks..."

  wait_for_http "Ollama" "http://127.0.0.1:11434/api/tags"
  wait_for_http "Flowise" "http://127.0.0.1:${FLOWISE_PORT}"

  if command -v ollama >/dev/null 2>&1; then
    if ! ollama list | awk 'NR > 1 {print $1}' | grep -Fxq "$MODEL"; then
      warn "Model ${MODEL} was not found in ollama list. The pull may still be finishing or may need to be retried."
    fi
  fi

  if command -v pm2 >/dev/null 2>&1; then
    pm2_bin="$(command -v pm2)"
    if ! "$pm2_bin" describe flowise >/dev/null 2>&1; then
      warn "PM2 does not currently report a flowise process. Check 'pm2 status' if the app does not appear."
    fi
  fi

  log "Flowise HTTP endpoint is up at http://127.0.0.1:${FLOWISE_PORT}"
  log "Ollama HTTP endpoint is up at http://127.0.0.1:11434"
}

status_report() {
  require_service_manager

  printf 'System: %s %s\n' "$(uname -s)" "$(uname -r)"
  printf 'Linux distro: %s (%s)\n' "${LINUX_FAMILY:-unknown}" "${ID:-unknown}"

  if command -v node >/dev/null 2>&1; then
    printf 'Node: %s\n' "$(node -v)"
  else
    printf 'Node: not installed\n'
  fi

  if command -v npm >/dev/null 2>&1; then
    printf 'npm: %s\n' "$(npm -v)"
  else
    printf 'npm: not installed\n'
  fi

  if command -v ollama >/dev/null 2>&1; then
    printf 'Ollama: %s\n' "$(ollama --version 2>/dev/null || ollama version 2>/dev/null || echo installed)"
    ollama list || true
  else
    printf 'Ollama: not installed\n'
  fi

  if command -v pm2 >/dev/null 2>&1; then
    printf 'PM2: %s\n' "$(pm2 -v 2>/dev/null || echo installed)"
    pm2 status || true
  else
    printf 'PM2: not installed\n'
  fi

  if command -v flowise >/dev/null 2>&1; then
    printf 'Flowise binary: %s\n' "$(command -v flowise)"
  else
    printf 'Flowise binary: not installed\n'
  fi

  if http_ready "http://127.0.0.1:11434/api/tags" 1; then
    printf 'Ollama API: up\n'
  else
    printf 'Ollama API: down\n'
  fi

  if http_ready "http://127.0.0.1:${FLOWISE_PORT}" 1; then
    printf 'Flowise UI: up at http://127.0.0.1:%s\n' "$FLOWISE_PORT"
  else
    printf 'Flowise UI: down at http://127.0.0.1:%s\n' "$FLOWISE_PORT"
  fi
}

open_flowise() {
  local url="http://127.0.0.1:${FLOWISE_PORT}"

  require_service_manager
  if http_ready "$url" 15; then
    :
  else
    if command -v pm2 >/dev/null 2>&1; then
      pm2 resurrect >/dev/null 2>&1 || true
    fi
    if ! http_ready "$url" 15; then
      warn "Flowise is not ready yet. Open this URL manually when the service comes up: ${url}"
    fi
  fi

  open_url "$url"
}

print_summary() {
  printf '\nReady now:\n'
  printf '  Flowise: http://127.0.0.1:%s\n' "$FLOWISE_PORT"
  printf '  Ollama:  http://127.0.0.1:11434\n'
  printf '  PM2:     pm2 status\n'
  printf '  Status:   %s --status\n' "$(installer_invocation)"
  printf '  Open UI:  %s --open-flowise\n' "$(installer_invocation)"
  printf '  Launchers: ~/.local/share/applications and Desktop\n'
}

main() {
  detect_script_path
  parse_args "$@"
  detect_platform

  require_service_manager

  case "$ACTION" in
    status)
      status_report
      return 0
      ;;
    open)
      open_flowise
      return 0
      ;;
    install)
      ;;
  esac

  require_non_root

  log "Starting setup for Ollama + ${MODEL} + Node.js + Flowise + PM2 on ${LINUX_FAMILY} Linux..."
  sudo -v
  ( while true; do sudo -n true; sleep 60; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap cleanup EXIT

  INSTALL_PROGRESS_TOTAL=8

  INSTALL_PROGRESS_STEP=1
  log "Preflight checks"
  check_preflight

  INSTALL_PROGRESS_STEP=2
  install_prereqs

  INSTALL_PROGRESS_STEP=3
  maybe_setup_swap

  INSTALL_PROGRESS_STEP=4
  install_ollama

  INSTALL_PROGRESS_STEP=5
  install_node_and_global_tools

  INSTALL_PROGRESS_STEP=6
  configure_flowise_pm2

  INSTALL_PROGRESS_STEP=7
  configure_pm2_logrotate
  create_gui_launchers

  INSTALL_PROGRESS_STEP=8
  health_checks

  if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    open_flowise
  fi

  log "Installation complete."
  print_summary
}

main "$@"
