#!/bin/bash

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

  echo "Downloading Go $version for $arch..."

  # Download with timeout and retry
  if ! curl -fsSL --max-time 300 --retry 3 "$download_url" -o "$tmp_path"; then
    echo "❌ Failed to download Go $version"
    echo "   Check your internet connection or verify version exists"
    return 1
  fi

  # Verify tarball integrity
  if ! tar -tzf "$tmp_path" &>/dev/null; then
    echo "❌ Downloaded file is corrupted"
    rm -f "$tmp_path"
    return 1
  fi

  echo "✓ Downloaded to $tmp_path"
  echo "$tmp_path"
}

# Install Go version to versioned directory
install_go_version() {
  local version="$1"
  version=$(normalize_version "$version")
  local arch=$(detect_architecture)
  local sudo_cmd=""

  [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

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
  $sudo_cmd ln -sfn "$versioned_dir" /usr/local/go

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
  local active_version=$(get_active_version | IFS='|' read -r v _ _; echo "$v")

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

# Install or update Go to the latest version
# Detects system architecture, downloads the latest Go version,
# installs it to /usr/local/go, and configures environment variables.
install_latest_go() {
  # Determine if sudo is needed
  SUDO_CMD=""
  if [ "$(id -u)" -ne 0 ]; then
    SUDO_CMD="sudo"
    echo "Running with user privileges. Using sudo for root commands."
  else
    echo "Running as root. sudo will not be used."
  fi

  # URL of the official Go downloads page
  GO_DOWNLOAD_URL="https://go.dev/dl/"

  # Detect the system architecture
  ARCH=$(detect_architecture)
  echo "Detected architecture: $ARCH"

  # Fetch the latest Go version
  echo "Fetching the latest Go version..."
  LATEST_GO_VERSION=$(fetch_latest_version)
  if [ -z "$LATEST_GO_VERSION" ]; then
    return 1
  fi

  echo "The latest Go version is: $LATEST_GO_VERSION"

  # Define the download URL for the latest Go version based on architecture
  GO_TAR_FILE="${LATEST_GO_VERSION}.linux-${ARCH}.tar.gz"
  GO_DOWNLOAD_LINK="https://go.dev/dl/${GO_TAR_FILE}"

  # Remove any previous Go installation
  echo "Removing previous Go installation (if any)..."
  $SUDO_CMD rm -rf /usr/local/go

  # Download and extract the latest Go version
  echo "Downloading Go version $LATEST_GO_VERSION for $ARCH..."
  if ! curl -LO "$GO_DOWNLOAD_LINK"; then
    echo "Failed to download Go. Please check the URL or your internet connection."
    # Clean up downloaded file if it exists and is incomplete
    [ -f "$GO_TAR_FILE" ] && rm "$GO_TAR_FILE"
    return 1
  fi

  echo "Installing Go..."
  if ! $SUDO_CMD tar -C /usr/local -xzf "$GO_TAR_FILE"; then
    echo "Failed to extract Go. Please check the downloaded file or permissions."
    rm "$GO_TAR_FILE" # Clean up downloaded tar file
    return 1
  fi
  rm "$GO_TAR_FILE" # Clean up downloaded tar file after successful extraction

  # Configure Go environment
  configure_environment


  # Verify the installation
  echo "Verifying the installation..."
  # Check if go binary exists and is executable
  if [ ! -x "/usr/local/go/bin/go" ]; then
      echo "Go binary not found or not executable at /usr/local/go/bin/go."
      return 1
  fi

  # Re-check PATH or call go with full path for verification
  if command -v go &>/dev/null; then
    go version
  elif [ -x "/usr/local/go/bin/go" ]; then
    /usr/local/go/bin/go version
  else
    echo "Could not find go command. Please ensure /usr/local/go/bin is in your PATH."
    return 1
  fi

  # The go version command was successful if we reached this point
  echo "Go $LATEST_GO_VERSION has been successfully installed/updated!"
}

# Only run installation if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Migrate legacy installation before running install
  migrate_legacy_install

  # Call the function to execute the installation
  install_latest_go
fi
