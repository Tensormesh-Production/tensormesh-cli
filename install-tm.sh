#!/usr/bin/env bash
set -euo pipefail

REPO_SLUG="Tensormesh-Production/tensormesh-cli"
RELEASE_BASE="https://github.com/$REPO_SLUG/releases"
LATEST_JSON_URL="${LATEST_JSON_URL:-https://raw.githubusercontent.com/$REPO_SLUG/main/latest.json}"
TM_VERSION="${TM_VERSION:-latest}"
TM_INSTALL_DIR="${TM_INSTALL_DIR:-$HOME/.local/bin}"
TMP_DIR=""

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing $cmd on PATH." >&2
    exit 1
  fi
}

detect_platform() {
  local os=""
  local arch=""

  case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    *)
      echo "Unsupported operating system: $(uname -s)" >&2
      exit 1
      ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac

  printf "%s-%s\n" "$os" "$arch"
}

checksum_cmd() {
  if command -v shasum >/dev/null 2>&1; then
    printf "shasum -a 256"
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf "sha256sum"
    return 0
  fi

  echo "Missing shasum or sha256sum for checksum verification." >&2
  exit 1
}

cleanup() {
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

main() {
  require_cmd curl
  require_cmd tar
  require_cmd mktemp
  trap cleanup EXIT

  if [[ "$TM_VERSION" == "latest" ]]; then
    require_cmd python3
    TM_VERSION="$(curl -fsSL "$LATEST_JSON_URL" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
  fi

  local platform=""
  platform="$(detect_platform)"
  local asset_name="tm-${platform}.tar.gz"
  local release_path="download/$TM_VERSION"

  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tm-install.XXXXXX")"

  local asset_url="$RELEASE_BASE/$release_path/$asset_name"
  local sums_url="$RELEASE_BASE/$release_path/SHA256SUMS"
  local archive_path="$TMP_DIR/$asset_name"
  local sums_path="$TMP_DIR/SHA256SUMS"

  echo "Downloading $asset_name from $RELEASE_BASE ..."
  curl -fsSL "$asset_url" -o "$archive_path"
  curl -fsSL "$sums_url" -o "$sums_path"

  local expected=""
  expected="$(awk -v name="$asset_name" '$2 == name { print $1 }' "$sums_path")"
  if [[ -z "$expected" ]]; then
    echo "Could not find checksum for $asset_name in SHA256SUMS." >&2
    exit 1
  fi

  local actual=""
  actual="$($(checksum_cmd) "$archive_path" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Checksum verification failed for $asset_name." >&2
    exit 1
  fi

  mkdir -p "$TM_INSTALL_DIR"
  tar -xzf "$archive_path" -C "$TMP_DIR"
  install -m 0755 "$TMP_DIR/tm" "$TM_INSTALL_DIR/tm"

  echo "Installed tm to $TM_INSTALL_DIR/tm"
  case ":$PATH:" in
    *":$TM_INSTALL_DIR:"*) ;;
    *)
      echo "Add $TM_INSTALL_DIR to PATH to use tm from a new shell."
      ;;
  esac
  echo "Run: tm --version"
}

main "$@"
