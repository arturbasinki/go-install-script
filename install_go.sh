#!/bin/bash

# Go Version Manager
# Automatically detects system architecture, downloads Go versions,
# and manages multiple installations side-by-side.
#
# Usage: install_go.sh [OPTIONS]
#   -y, --yes         Silent mode
#   --version VER     Install specific version
#   --cleanup         Remove old versions
#   --list            List versions
#   -h, --help        Show help
#
# Author: arturbasinki
# Repository: https://github.com/arturbasinki/go-install-script
#
# Environment Variables:
#   SILENT_MODE       Set to "true" for non-interactive operation
#
# Exit Codes:
#   0 - Success
#   1 - Error (invalid input, installation failure, permission denied)

# Global variables for error handling
INSTALLING_VERSION=""
PREV_SYMLINK_TARGET=""

# Trap errors and clean up
trap cleanup_on_error ERR

cleanup_on_error() {
  local exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    echo ""
    echo "❌ Installation failed, cleaning up..."

    local sudo_cmd=""
    [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

    # Clean up partial installation
    if [ -n "$INSTALLING_VERSION" ] && [ -d "/usr/local/go-$INSTALLING_VERSION" ]; then
      echo "  Removing partial installation..."
      $sudo_cmd rm -rf "/usr/local/go-$INSTALLING_VERSION"
    fi

    # Clean up downloaded files
    [ -n "$INSTALLING_VERSION" ] && rm -f "/tmp/$INSTALLING_VERSION"*.tar.gz

    # Restore previous symlink if it existed
    if [ -n "$PREV_SYMLINK_TARGET" ]; then
      echo "  Restoring previous symlink..."
      # Remove directory if exists before creating symlink
      [ -d "/usr/local/go" ] && $sudo_cmd rm -rf /usr/local/go
      $sudo_cmd ln -sfn "$PREV_SYMLINK_TARGET" /usr/local/go
    fi
  fi
}

# Detect the system architecture
# Returns: amd64, arm64, or armv6l
# Exits with error 1 for unsupported architectures
detect_architecture() {
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)
      echo "amd64"
      ;;
    aarch64)
      echo "arm64"
      ;;
    armv6l)
      echo "armv6l"
      ;;
    *)
      echo "Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac
}

# Detect the appropriate shell profile file for the current user
# Checks the user's SHELL environment variable and returns the most
# appropriate profile file path for environment variable configuration.
# Returns: Path to profile file (e.g., ~/.bashrc, ~/.zshrc, ~/.profile)
detect_profile_file() {
  case "$SHELL" in
    */bash)
      if [ -f "$HOME/.bashrc" ]; then
        echo "$HOME/.bashrc"
      elif [ -f "$HOME/.bash_profile" ]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.profile"
      fi
      ;;
    */zsh)
      if [ -f "$HOME/.zshrc" ]; then
        echo "$HOME/.zshrc"
      elif [ -f "$HOME/.zprofile" ]; then
        echo "$HOME/.zprofile"
      else
        echo "$HOME/.profile"
      fi
      ;;
    */fish)
      echo "$HOME/.config/fish/config.fish"
      ;;
    *)
      echo "$HOME/.profile"
      ;;
  esac
}

# Fetch the latest Go version from go.dev
# Scrapes the Go downloads page to find the latest version number.
# Returns: Version string (e.g., "go1.23.1") or empty string on failure
fetch_latest_version() {
  local latest_version=$(curl -s https://go.dev/dl/ | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)

  if [ -z "$latest_version" ]; then
    echo "Failed to fetch latest Go version" >&2
    return 1
  fi

  echo "$latest_version"
}

# Normalize version string (remove 'go' prefix if present)
# Returns: Version string without 'go' prefix (e.g., "1.21.0" from "go1.21.0")
normalize_version() {
  local version="$1"
  echo "$version" | sed 's/^go//'
}

# Validate version format
validate_version() {
  local version="$1"
  version=$(normalize_version "$version")

  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "❌ Invalid version format: $version"
    echo "   Expected format: 1.21.0 or go1.21.0"
    return 1
  fi

  echo "$version"
}

# Get currently active Go version and location
# Checks PATH, symlink location, and legacy directory installations.
# Returns: Pipe-delimited string "version|location|goroot" or "||" if not found
get_active_version() {
  local version=""
  local location=""
  local goroot=""

  # Method 1: Check if 'go' command exists in PATH
  if command -v go &>/dev/null; then
    version=$(normalize_version "$(go version | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?')")
    location=$(which go)
    goroot=$(go env GOROOT 2>/dev/null || echo "")
    echo "$version|$location|$goroot"
    return 0
  fi

  # Method 2: Check standard symlink location
  if [ -L "/usr/local/go" ]; then
    local target=$(readlink -f /usr/local/go)
    if [ -x "$target/bin/go" ]; then
      version=$(normalize_version "$("$target/bin/go" version 2>/dev/null | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?')")
    fi
    location="/usr/local/go/bin/go"
    goroot="$target"
    echo "$version|$location|$goroot"
    return 0
  fi

  # Method 3: Check legacy directory install
  if [ -d "/usr/local/go/bin" ]; then
    version=$(normalize_version "$(/usr/local/go/bin/go version 2>/dev/null | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?')")
    if [ -n "$version" ]; then
      location="/usr/local/go/bin/go"
      goroot="/usr/local/go"
      echo "$version|$location|$goroot"
      return 0
    fi
  fi

  # No Go found
  echo "Go installation not found" >&2
  echo "||"
  return 1
}

# List all installed Go versions
# Scans /usr/local/go-* directories for versioned installations.
# Returns: Sorted list of versions (newest first), one per line
list_installed_versions() {
  local versions=()

  # Find all /usr/local/go-* directories
  for dir in /usr/local/go-[0-9]*; do
    if [ -d "$dir" ]; then
      local version=$(basename "$dir" | sed 's/^go-//')
      versions+=("$version")
    fi
  done

  # Sort versions (newest first)
  printf '%s\n' "${versions[@]}" | sort -V -r
}

# Download Go tarball with validation
download_go_version() {
  local version="$1"
  version=$(normalize_version "$version")
  local arch=$(detect_architecture)
  local tar_file="go${version}.linux-${arch}.tar.gz"
  local download_url="https://go.dev/dl/${tar_file}"
  local tmp_path="/tmp/$tar_file"

  echo "Downloading Go $version for $arch..." >&2

  # Download with timeout and retry
  if ! curl -fsSL --max-time 300 --retry 3 "$download_url" -o "$tmp_path"; then
    echo "❌ Failed to download Go $version" >&2
    echo "   Check your internet connection or verify version exists" >&2
    return 1
  fi

  # Verify tarball integrity
  if ! tar -tzf "$tmp_path" &>/dev/null; then
    echo "❌ Downloaded file is corrupted" >&2
    rm -f "$tmp_path"
    return 1
  fi

  echo "✓ Downloaded to $tmp_path" >&2
  echo "$tmp_path"
}

# Install Go version to versioned directory
install_go_version() {
  local version="$1"
  version=$(normalize_version "$version")
  local arch=$(detect_architecture)
  local sudo_cmd=""

  [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

  # Save current symlink target for potential rollback
  if [ -L "/usr/local/go" ]; then
    PREV_SYMLINK_TARGET=$(readlink -f /usr/local/go)
  fi

  # Set installing version for error handler
  INSTALLING_VERSION="$version"

  # Download
  local tar_path=$(download_go_version "$version") || return 1

  # Check disk space
  local required_space=$(du -k "$tar_path" | cut -f1)
  local available_space=$(df -k /usr/local | tail -1 | awk '{print $4}')

  if [ "$available_space" -lt "$((required_space * 2))" ]; then
    echo "❌ Insufficient disk space in /usr/local"
    rm -f "$tar_path"
    return 1
  fi

  # Extract to /usr/local/go (temporary)
  echo "Extracting Go $version..."
  if ! $sudo_cmd tar -C /usr/local -xzf "$tar_path"; then
    echo "❌ Failed to extract Go"
    rm -f "$tar_path"
    return 1
  fi

  # Rename to versioned directory
  local versioned_dir="/usr/local/go-$version"
  echo "Installing to $versioned_dir..."

  # Remove existing versioned directory if present
  [ -d "$versioned_dir" ] && $sudo_cmd rm -rf "$versioned_dir"

  $sudo_cmd mv /usr/local/go "$versioned_dir"
  rm -f "$tar_path"

  echo "✓ Installed Go $version to $versioned_dir"
}

# Switch active Go version by updating symlink
switch_go_version() {
  local version="$1"
  version=$(normalize_version "$version")
  local versioned_dir="/usr/local/go-$version"
  local sudo_cmd=""

  [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

  # Verify version exists
  if [ ! -d "$versioned_dir" ]; then
    echo "❌ Go $version is not installed"
    echo "   Available versions:"
    list_installed_versions
    return 1
  fi

  # Verify Go binary exists
  if [ ! -x "$versioned_dir/bin/go" ]; then
    echo "❌ Go binary not found in $versioned_dir"
    return 1
  fi

  # Update symlink
  echo "Switching to Go $version..."
  if ! $sudo_cmd ln -sfn "$versioned_dir" /usr/local/go; then
    echo "❌ Failed to update symlink"
    return 1
  fi

  echo "✓ Switched to Go $version"
  /usr/local/go/bin/go version
}

# Migrate legacy /usr/local/go directory to versioned format
migrate_legacy_install() {
  local sudo_cmd=""
  [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

  # Check if legacy install exists
  if [ -d "/usr/local/go" ] && [ ! -L "/usr/local/go" ]; then
    if [ -x "/usr/local/go/bin/go" ]; then
      local version=$(/usr/local/go/bin/go version 2>/dev/null | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^go//')

      if [ -z "$version" ]; then
        echo "⚠️  Legacy installation detected but version could not be determined"
        return 1
      fi

      echo "⚠️  Legacy installation detected: go$version"
      echo ""
      echo "   This script now manages multiple Go versions side-by-side."
      echo "   Your existing installation will be migrated to the new format."
      echo ""

      # Check if we should prompt (non-silent mode)
      if [ "$SILENT_MODE" != "true" ]; then
        read -p "   Continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
          echo "Migration cancelled. Exiting."
          exit 0
        fi
      fi

      # Create backup
      echo "Creating backup..."
      $sudo_cmd cp -r /usr/local/go /usr/local/go.backup

      # Check for existing versioned directory
      if [ -d "/usr/local/go-$version" ]; then
        echo "⚠️  Versioned directory /usr/local/go-$version already exists"
        echo "   Removing old versioned directory before migration..."
        $sudo_cmd rm -rf "/usr/local/go-$version"
      fi

      # Rename to versioned directory
      echo "Migrating to /usr/local/go-$version..."
      $sudo_cmd mv /usr/local/go "/usr/local/go-$version"

      # Create symlink
      $sudo_cmd ln -s "/usr/local/go-$version" /usr/local/go

      # Verify migration
      if /usr/local/go/bin/go version &>/dev/null; then
        echo "✓ Migrated successfully"
        $sudo_cmd rm -rf /usr/local/go.backup
        return 0
      else
        echo "❌ Migration failed, restoring backup"

        # Atomic rollback with error checking
        if ! $sudo_cmd rm -rf /usr/local/go "/usr/local/go-$version"; then
          echo "❌ Critical: Failed to clean up failed migration"
          return 1
        fi

        if ! $sudo_cmd mv /usr/local/go.backup /usr/local/go; then
          echo "❌ Critical: Failed to restore backup. Your Go installation may be broken."
          echo "   Manual intervention required - restore from /usr/local/go.backup manually"
          return 1
        fi

        return 1
      fi
    fi
  fi

  return 0
}

# Configure Go environment variables in shell profile
configure_environment() {
  local profile_file=$(detect_profile_file)
  local sudo_cmd=""
  [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

  echo "Setting up Go environment..."

  if [ "$(id -u)" -ne 0 ]; then
    # For regular user, update their profile
    if [ ! -f "$profile_file" ]; then
      # Create profile file if it doesn't exist
      local profile_dir=$(dirname "$profile_file")
      [ ! -d "$profile_dir" ] && mkdir -p "$profile_dir"
      touch "$profile_file"
    fi

    # Set GOPATH
    local gopath_line='export GOPATH=$HOME/go'
    if ! grep -qF "$gopath_line" "$profile_file" 2>/dev/null; then
      echo "$gopath_line" >> "$profile_file"
      echo "✓ GOPATH set to \$HOME/go in $profile_file"
    else
      echo "✓ GOPATH already set in $profile_file"
    fi

    # Set GOBIN
    local gobin_line='export GOBIN=$GOPATH/bin'
    if ! grep -qF "$gobin_line" "$profile_file" 2>/dev/null; then
      echo "$gobin_line" >> "$profile_file"
      echo "✓ GOBIN set to \$GOPATH/bin in $profile_file"
    else
      echo "✓ GOBIN already set in $profile_file"
    fi

    # Add Go binary directory to PATH
    local go_path_line='export PATH=$PATH:/usr/local/go/bin'
    if ! grep -qF "$go_path_line" "$profile_file" 2>/dev/null; then
      echo "$go_path_line" >> "$profile_file"
      echo "✓ Go binary path added to PATH in $profile_file"
    else
      echo "✓ Go binary path already in PATH in $profile_file"
    fi

    # Add GOBIN to PATH
    local gobin_path_line='export PATH=$PATH:$GOBIN'
    if ! grep -qF "$gobin_path_line" "$profile_file" 2>/dev/null; then
      echo "$gobin_path_line" >> "$profile_file"
      echo "✓ GOBIN added to PATH in $profile_file"
    else
      echo "✓ GOBIN already in PATH in $profile_file"
    fi

    # Export for current session
    export GOPATH=$HOME/go
    export GOBIN=$GOPATH/bin
    export PATH=$PATH:/usr/local/go/bin:$GOBIN
  else
    # For root user
    export GOPATH=$HOME/go
    export GOBIN=$GOPATH/bin
    export PATH=$PATH:/usr/local/go/bin:$GOBIN
    echo "✓ Go environment set for current session"
    echo "  GOPATH: \$HOME/go"
    echo "  GOBIN: \$GOPATH/bin"
    echo "  For permanent system-wide effect, add to /etc/profile.d/go.sh"
  fi
}

# Remove old Go versions interactively
cleanup_versions() {
  local sudo_cmd=""
  [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

  local versions=($(list_installed_versions))
  # Extract active version using temp variable
  local active_info=$(get_active_version)
  local active_version=$(echo "$active_info" | cut -d'|' -f1)

  if [ ${#versions[@]} -eq 0 ]; then
    echo "No Go versions installed to clean up."
    return 0
  fi

  echo "Installed versions:"
  for v in "${versions[@]}"; do
    if [ "$v" == "$active_version" ]; then
      echo "  ✓ $v (active)"
    else
      echo "    $v"
    fi
  done
  echo ""

  # Filter out active version
  local removable=()
  for v in "${versions[@]}"; do
    [ "$v" != "$active_version" ] && removable+=("$v")
  done

  if [ ${#removable[@]} -eq 0 ]; then
    echo "No old versions to remove (only active version installed)."
    return 0
  fi

  if [ "$SILENT_MODE" == "true" ]; then
    # Silent mode: remove all old versions
    echo "Removing all old versions..."
    for v in "${removable[@]}"; do
      echo "  Removing $v..."
      $sudo_cmd rm -rf "/usr/local/go-$v"
    done
    echo "✓ Cleanup complete"
    return 0
  fi

  # Interactive mode
  echo "Remove old versions? (all/specific/none/exit)"
  read -p "> " choice

  case "$choice" in
    all)
      echo "Removing all old versions..."
      for v in "${removable[@]}"; do
        echo "  Removing $v..."
        $sudo_cmd rm -rf "/usr/local/go-$v"
      done
      echo "✓ Removed ${#removable[@]} old version(s)"
      ;;
    specific)
      echo "Select versions to remove (space-separated numbers):"
      for i in "${!removable[@]}"; do
        echo "  [$i] ${removable[$i]}"
      done
      read -p "Numbers: " input

      for num in $input; do
        if [ -n "${removable[$num]}" ]; then
          v="${removable[$num]}"
          echo "  Removing $v..."
          $sudo_cmd rm -rf "/usr/local/go-$v"
          echo "  ✓ Removed $v"
        fi
      done
      ;;
    none)
      echo "Keeping all versions"
      ;;
    exit|*)
      echo "Cleanup cancelled"
      ;;
  esac
}

# Smart interactive prompts based on current state
prompt_smart() {
  # Set default for silent mode
  SILENT_MODE="${SILENT_MODE:-false}"

  local current_info=$(get_active_version)
  IFS='|' read -r v _ _ <<< "$current_info"
  local current_version="$v"
  local latest_version=$(fetch_latest_version)

  if [ -z "$latest_version" ]; then
    echo "Failed to fetch latest Go version" >&2
    return 1
  fi

  echo ""
  echo "=== Go Version Manager ==="
  echo ""

  # Scenario 1: No Go installed
  if [ -z "$current_version" ]; then
    echo "No Go installation detected."
    echo "Latest available: $latest_version"
    echo ""

    if [ "$SILENT_MODE" == "true" ]; then
      install_go_version "$latest_version"
      switch_go_version "$latest_version"
      configure_environment
      return $?
    fi

    read -p "Install $latest_version? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      install_go_version "$latest_version"
      switch_go_version "$latest_version"
      configure_environment
      return $?
    fi
    return 0
  fi

  # Scenario 2: Current version outdated
  if [ "$current_version" != "$latest_version" ]; then
    echo "Current installation: $current_version"
    IFS='|' read -r _ l _ <<< "$current_info"
    local current_location="$l"
    echo "Location: $current_location"
    echo "Latest available: $latest_version"

    local installed=($(list_installed_versions))
    echo "Installed versions: ${installed[*]}"
    echo ""

    if [ "$SILENT_MODE" == "true" ]; then
      install_go_version "$latest_version"
      switch_go_version "$latest_version"
      configure_environment
      return $?
    fi

    echo "Options:"
    echo "  y - Upgrade to $latest_version"
    echo "  s - Switch to different installed version"
    echo "  n - Cancel"
    read -p "Choice [y/s/n] " -n 1 -r
    echo

    case $REPLY in
      y)
        install_go_version "$latest_version"
        switch_go_version "$latest_version"
        configure_environment
        return $?
        ;;
      s)
        show_version_menu
        ;;
      *)
        echo "Cancelled"
        ;;
    esac
    return 0
  fi

  # Scenario 3: Already on latest
  echo "Current installation: $current_version (latest)"
  echo "No upgrade available."
  echo ""

  if [ "$SILENT_MODE" == "true" ]; then
    echo "Go is up to date."
    return 0
  fi

  read -p "Install additional version? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter version (e.g., 1.20.5): " version
    if [ -n "$version" ]; then
      install_go_version "$version"
      switch_go_version "$version"
      configure_environment
    fi
  fi
}

# Show menu of installed versions for switching
show_version_menu() {
  local versions=($(list_installed_versions))
  local current_info=$(get_active_version)
  IFS='|' read -r v _ _ <<< "$current_info"
  local current_version="$v"

  if [ ${#versions[@]} -eq 0 ]; then
    echo "No versions installed."
    return 1
  fi

  echo "Installed versions:"
  for i in "${!versions[@]}"; do
    local v="${versions[$i]}"
    if [ "$v" == "$current_version" ]; then
      echo "  [$i] $v (current)"
    else
      echo "  [$i] $v"
    fi
  done

  read -p "Select version to switch to: " selection

  if [ -n "${versions[$selection]}" ]; then
    local target_version="${versions[$selection]}"
    switch_go_version "$target_version"
    configure_environment
  else
    echo "Invalid selection"
    return 1
  fi
}

# Parse command-line arguments
parse_arguments() {
  SILENT_MODE="${SILENT_MODE:-false}"
  CLEANUP_ONLY=false
  LIST_ONLY=false
  TARGET_VERSION=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      -y|--yes)
        SILENT_MODE=true
        shift
        ;;
      --version)
        if [ -z "$2" ] || [[ "$2" == -* ]]; then
          echo "Error: --version requires a version number"
          echo ""
          show_help
          exit 1
        fi
        # Validate and normalize version
        if ! TARGET_VERSION=$(validate_version "$2"); then
          exit 1
        fi
        shift 2
        ;;
      --cleanup)
        CLEANUP_ONLY=true
        shift
        ;;
      --list)
        LIST_ONLY=true
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

# Show help message
show_help() {
  cat << EOF
Go Version Manager - Install and manage multiple Go versions

USAGE:
    install_go.sh [OPTIONS]

OPTIONS:
    -y, --yes              Silent mode - accept all defaults (no prompts)
    --version VERSION      Install or switch to specific version (e.g., 1.20.5)
    --cleanup              Run cleanup mode without installing
    --list                 List installed and available versions
    -h, --help             Show this help message

EXAMPLES:
    install_go.sh                  Interactive mode with smart prompts
    install_go.sh -y               Install/upgrade to latest silently
    install_go.sh --version 1.20.5 Install specific version
    install_go.sh -y --cleanup     Remove old versions silently
    install_go.sh --list           Show all installed versions

EOF
}

# Main orchestration function
main() {
  # Early permission check
  if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo &>/dev/null; then
      echo "❌ This script requires root privileges"
      echo "   Please run as root, or install sudo"
      exit 1
    fi

    # Test sudo access
    if ! sudo -n true 2>/dev/null; then
      if [ "$SILENT_MODE" == "true" ]; then
        echo "❌ This script requires sudo privileges"
        echo "   Please run with sudo access"
        exit 1
      fi
    fi
  fi

  # Parse arguments first
  parse_arguments "$@"

  # Handle list mode
  if [ "$LIST_ONLY" == "true" ]; then
    echo "Installed versions:"
    list_installed_versions
    local latest=$(fetch_latest_version)
    echo "Latest available: $latest"
    exit 0
  fi

  # Handle cleanup-only mode
  if [ "$CLEANUP_ONLY" == "true" ]; then
    cleanup_versions || exit $?
    exit 0  # Exit successfully after cleanup
  fi

  # Handle version-specific mode
  if [ -n "$TARGET_VERSION" ]; then
    # Check if version already installed
    if [ -d "/usr/local/go-$(normalize_version $TARGET_VERSION)" ]; then
      switch_go_version "$TARGET_VERSION" || exit $?
      configure_environment || exit $?
    else
      install_go_version "$TARGET_VERSION" || exit $?
      switch_go_version "$TARGET_VERSION" || exit $?
      configure_environment || exit $?
    fi

    # Prompt for cleanup after version install
    if [ "$SILENT_MODE" != "true" ]; then
      echo ""
      cleanup_versions || true  # Don't fail on cleanup errors
    fi

    exit 0
  fi

  # Migrate legacy install if present
  migrate_legacy_install

  # Default mode: smart prompts
  prompt_smart

  # Prompt for cleanup after install
  if [ "$SILENT_MODE" != "true" ]; then
    echo ""
    cleanup_versions || true  # Don't fail on cleanup errors
  fi

  # Exit with success
  exit 0
}

# Only run installation if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Run main function with all arguments
  main "$@"
fi
