# Go Version Manager Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the single-purpose Go installer into an intelligent version manager supporting multiple installed versions, interactive prompts, and automation-friendly operation.

**Architecture:** Side-by-side version installation (`/usr/local/go-1.21.0`) with active symlink (`/usr/local/go` → version directory). Smart state discovery checks PATH, symlinks, and standard locations. Interactive prompts with fallback to silent mode for automation.

**Tech Stack:** Bash 4.0+, standard Linux utilities (curl, tar, grep with PCRE), dialog/whiptail (optional for enhanced UX)

---

## Pre-Implementation: Baseline Verification

**Files:**
- Read: `install_go.sh` (existing script)

**Step 1: Verify current script behavior**

```bash
# Make script executable
chmod +x install_go.sh

# Check current version (if Go installed)
go version 2>/dev/null || echo "No Go installed"

# Run script to see current behavior
./install_go.sh
```

Expected: Script installs latest Go to `/usr/local/go` (directory, not symlink)

**Step 2: Create backup of working script**

```bash
cp install_go.sh install_go.sh.backup
```

**Step 3: Commit baseline**

```bash
git add install_go.sh.backup
git commit -m "chore: backup original script before refactoring"
```

---

## Task 1: Extract Core Utility Functions

**Files:**
- Modify: `install_go.sh:1-21` (extract and refactor)
- Test: Manual verification

**Step 1: Extract and enhance detect_architecture()**

The function already exists, just verify it's at the top of the file for clarity:

```bash
# Function to detect the system architecture
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
```

**Step 2: Add detect_profile_file() function**

Add after `detect_architecture()`:

```bash
# Detect appropriate shell profile file
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
        echo "$HOME/.zshrc"
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
```

**Step 3: Add fetch_latest_version() function**

Extract version fetching logic:

```bash
# Fetch latest Go version from go.dev
fetch_latest_version() {
  local latest_version=$(curl -s https://go.dev/dl/ | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)

  if [ -z "$latest_version" ]; then
    echo "Failed to fetch latest Go version" >&2
    return 1
  fi

  echo "$latest_version"
}
```

**Step 4: Test the functions**

```bash
# Source the script to load functions
source install_go.sh

# Test architecture detection
detect_architecture
# Expected output: amd64, arm64, or armv6l

# Test profile file detection
detect_profile_file
# Expected output: path to your shell profile

# Test version fetching
fetch_latest_version
# Expected output: go1.22.1 (or current latest)
```

**Step 5: Commit utility functions**

```bash
git add install_go.sh
git commit -m "refactor: extract core utility functions

Extract detect_architecture, add detect_profile_file for
shell-aware config detection, add fetch_latest_version."
```

---

## Task 2: Add State Discovery Functions

**Files:**
- Modify: `install_go.sh` (add new functions)
- Test: Manual verification with different Go states

**Step 1: Add get_active_version() function**

```bash
# Get currently active Go version and location
get_active_version() {
  local version=""
  local location=""
  local goroot=""

  # Method 1: Check if 'go' command exists in PATH
  if command -v go &>/dev/null; then
    version=$(go version | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?')
    location=$(which go)
    goroot=$(go env GOROOT 2>/dev/null || echo "")
    echo "$version|$location|$goroot"
    return 0
  fi

  # Method 2: Check standard symlink location
  if [ -L "/usr/local/go" ]; then
    local target=$(readlink -f /usr/local/go)
    version=$(echo "$target" | grep -oP 'go-[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^go-//')
    location="/usr/local/go/bin/go"
    goroot="$target"
    echo "$version|$location|$goroot"
    return 0
  fi

  # Method 3: Check legacy directory install
  if [ -d "/usr/local/go/bin" ]; then
    version=$(/usr/local/go/bin/go version 2>/dev/null | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?')
    if [ -n "$version" ]; then
      location="/usr/local/go/bin/go"
      goroot="/usr/local/go"
      echo "$version|$location|$goroot"
      return 0
    fi
  fi

  # No Go found
  echo "||"
  return 1
}
```

**Step 2: Add list_installed_versions() function**

```bash
# List all installed Go versions
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
```

**Step 3: Add normalize_version() helper**

```bash
# Normalize version string (remove 'go' prefix if present)
normalize_version() {
  local version="$1"
  echo "$version" | sed 's/^go//'
}
```

**Step 4: Test state discovery**

```bash
# Source the script
source install_go.sh

# Test get_active_version
get_active_version | IFS='|' read -r version location goroot
echo "Version: $version"
echo "Location: $location"
echo "GOROOT: $goroot"

# Test list_installed_versions
list_installed_versions
# Expected: List of versions in /usr/local/go-* or empty if none

# Test normalize_version
normalize_version "go1.21.0"
# Expected: 1.21.0
```

**Step 5: Commit state discovery**

```bash
git add install_go.sh
git commit -m "feat: add state discovery functions

Add get_active_version to detect Go installation via PATH,
symlink, or directory scan. Add list_installed_versions to
enumerate versioned installations. Add normalize_version helper."
```

---

## Task 3: Add Download and Installation Functions

**Files:**
- Modify: `install_go.sh` (refactor existing logic)
- Test: Download and install test version

**Step 1: Add download_go_version() function**

```bash
# Download Go tarball with validation
download_go_version() {
  local version="$1"
  version=$(normalize_version "$version")
  local arch=$(detect_architecture)
  local tar_file="${version}.linux-${arch}.tar.gz"
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
```

**Step 2: Add install_go_version() function**

```bash
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
```

**Step 3: Add switch_go_version() function**

```bash
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
```

**Step 4: Test installation and switching**

```bash
# Source the script
source install_go.sh

# Test downloading a specific version (without installing)
download_go_version "1.21.0"
# Expected: Downloads to /tmp/go1.21.0.linux-{arch}.tar.gz

# If you have a test system, try actual install:
# install_go_version "1.20.5"
# Expected: Installs to /usr/local/go-1.20.5

# Test switching (if multiple versions installed)
# switch_go_version "1.20.5"
# Expected: Updates symlink, runs 'go version'
```

**Step 5: Commit installation functions**

```bash
git add install_go.sh
git commit -m "feat: add download, install, and version switch functions

Add download_go_version with integrity validation and disk space
check. Add install_go_version to extract and install to versioned
directories. Add switch_go_version to update active symlink."
```

---

## Task 4: Add Legacy Migration Function

**Files:**
- Modify: `install_go.sh` (add migration function)
- Test: Simulate legacy install and migrate

**Step 1: Add migrate_legacy_install() function**

```bash
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
        $sudo_cmd rm -rf /usr/local/go "/usr/local/go-$version"
        $sudo_cmd mv /usr/local/go.backup /usr/local/go
        return 1
      fi
    fi
  fi

  return 0
}
```

**Step 2: Test migration**

WARNING: This test requires a system with Go you can safely modify:

```bash
# Create a mock legacy install for testing (DO NOT run on production system)
# sudo mkdir -p /tmp/test_legacy_go/bin
# sudo cp -r /usr/local/go/* /tmp/test_legacy_go/  # if you have Go installed

# Test the migration function logic
source install_go.sh

# If you have a real legacy install, run:
# migrate_legacy_install
# Expected: Detects, prompts, migrates to /usr/local/go-X.Y.Z with symlink
```

**Step 3: Commit migration function**

```bash
git add install_go.sh
git commit -m "feat: add legacy installation migration

Detects old-style /usr/local/go directory installs and migrates
to versioned format with symlink. Includes backup and rollback
on failure."
```

---

## Task 5: Add Environment Configuration Function

**Files:**
- Modify: `install_go.sh` (extract and enhance existing logic)
- Test: Verify environment setup in different shells

**Step 1: Add configure_environment() function**

```bash
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
```

**Step 2: Test environment configuration**

```bash
# Source the script
source install_go.sh

# Test profile detection
detect_profile_file
# Expected: Your shell's profile file path

# Test configuration (review file after running)
configure_environment
# Expected: Adds exports to profile, sets for current session

# Verify the changes
grep -E "(GOPATH|GOBIN|PATH.*go)" ~/.bashrc  # or your profile
# Expected: See the export lines added
```

**Step 3: Commit environment configuration**

```bash
git add install_go.sh
git commit -m "feat: add environment configuration function

Extract and enhance GOPATH/GOBIN/PATH setup with shell-aware
profile detection. Handles user and root contexts appropriately."
```

---

## Task 6: Add Cleanup Function

**Files:**
- Modify: `install_go.sh` (add cleanup function)
- Test: Install multiple versions and test cleanup

**Step 1: Add cleanup_versions() function**

```bash
# Remove old Go versions interactively
cleanup_versions() {
  local sudo_cmd=""
  [ "$(id -u)" -ne 0 ] && sudo_cmd="sudo"

  local versions=($(list_installed_versions))
  local active_version=$(get_active_version | IFS='|' read -r v _ _; echo "$v" | sed 's/^go//')

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
```

**Step 2: Test cleanup functionality**

```bash
# Source the script
source install_go.sh

# List versions to see what's installed
list_installed_versions
# Expected: List of versions in /usr/local/go-*

# Run cleanup (if you have multiple versions)
cleanup_versions
# Expected: Shows menu, allows selection
```

**Step 3: Commit cleanup function**

```bash
git add install_go.sh
git commit -m "feat: add interactive cleanup functionality

List installed versions, show active, prompt for removal.
Supports silent mode (--cleanup -y) for automation.
Never removes active version."
```

---

## Task 7: Add Smart Prompt Function

**Files:**
- Modify: `install_go.sh` (add interactive prompts)
- Test: Test each prompt scenario

**Step 1: Add prompt_smart() function**

```bash
# Smart interactive prompts based on current state
prompt_smart() {
  local current_info=$(get_active_version)
  local current_version=$(echo "$current_info" | IFS='|' read -r v _ _; echo "$v" | sed 's/^go//')
  local latest_version=$(fetch_latest_version | sed 's/^go//')

  echo ""
  echo "=== Go Version Manager ==="
  echo ""

  # Scenario 1: No Go installed
  if [ -z "$current_version" ]; then
    echo "No Go installation detected."
    echo "Latest available: go$latest_version"
    echo ""

    if [ "$SILENT_MODE" == "true" ]; then
      install_go_version "$latest_version"
      switch_go_version "$latest_version"
      configure_environment
      return $?
    fi

    read -p "Install go$latest_version? (y/n) " -n 1 -r
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
    echo "Current installation: go$current_version"
    local current_location=$(echo "$current_info" | IFS='|' read -r _ l _; echo "$l")
    echo "Location: $current_location"
    echo "Latest available: go$latest_version"

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
    echo "  y - Upgrade to go$latest_version"
    echo "  s - Switch to different installed version"
    echo "  n - Cancel"
    read -p "Choice [y/s/n] " -n 1 -r
    echo

    case $REPLY in
      y)
        install_go_version "$latest_version"
        switch_go_version "$latest_version"
        configure_environment
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
  echo "Current installation: go$current_version (latest)"
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
```

**Step 2: Add show_version_menu() helper**

```bash
# Show menu of installed versions for switching
show_version_menu() {
  local versions=($(list_installed_versions))
  local current_version=$(get_active_version | IFS='|' read -r v _ _; echo "$v" | sed 's/^go//')

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
```

**Step 3: Test smart prompts**

```bash
# Source the script
source install_go.sh

# Set SILENT_MODE=false for testing
export SILENT_MODE=false

# Test the smart prompt (will interact based on your state)
prompt_smart
# Expected: Shows appropriate prompt based on current Go state
```

**Step 4: Commit smart prompts**

```bash
git add install_go.sh
git commit -m "feat: add smart interactive prompts

Detects Go state and shows context-aware prompts:
- No Go: offer latest install
- Outdated: offer upgrade or switch
- Current: offer additional install

Supports silent mode for automation."
```

---

## Task 8: Add Argument Parsing and Main Function

**Files:**
- Modify: `install_go.sh` (add parse_arguments and main)
- Test: Test all command-line options

**Step 1: Add parse_arguments() function**

```bash
# Parse command-line arguments
parse_arguments() {
  SILENT_MODE=false
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
        TARGET_VERSION="$2"
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
```

**Step 2: Add show_help() function**

```bash
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
```

**Step 3: Add main() function**

```bash
# Main orchestration function
main() {
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
    cleanup_versions
    exit $?
  fi

  # Handle version-specific mode
  if [ -n "$TARGET_VERSION" ]; then
    # Check if version already installed
    if [ -d "/usr/local/go-$(normalize_version $TARGET_VERSION)" ]; then
      switch_go_version "$TARGET_VERSION"
      configure_environment
    else
      install_go_version "$TARGET_VERSION"
      switch_go_version "$TARGET_VERSION"
      configure_environment
    fi

    # Prompt for cleanup after version install
    if [ "$SILENT_MODE" != "true" ]; then
      echo ""
      cleanup_versions
    fi

    exit $?
  fi

  # Migrate legacy install if present
  migrate_legacy_install

  # Default mode: smart prompts
  prompt_smart

  # Prompt for cleanup after install
  if [ "$SILENT_MODE" != "true" ]; then
    echo ""
    cleanup_versions
  fi
}
```

**Step 4: Replace old script entry point**

Find the line at the end of the script that calls `install_latest_go` and replace with:

```bash
# Run main function with all arguments
main "$@"
```

Remove or comment out the old `install_latest_go` call (likely at the very end).

**Step 5: Test all command-line options**

```bash
# Test help
./install_go.sh --help
# Expected: Show usage information

# Test list
./install_go.sh --list
# Expected: Show installed versions and latest

# Test silent mode (if on test system)
# ./install_go.sh -y
# Expected: Install/upgrade without prompts

# Test version-specific
# ./install_go.sh --version 1.20.5
# Expected: Install or switch to 1.20.5
```

**Step 6: Commit argument parsing and main**

```bash
git add install_go.sh
git commit -m "feat: add argument parsing and main orchestration

Add full command-line interface with -y/--yes, --version,
--cleanup, --list, and --help options. Replace old
install_latest_go entry point with main() function."
```

---

## Task 9: Add Error Handling and Safety Improvements

**Files:**
- Modify: `install_go.sh` (add error traps, validation)
- Test: Test error scenarios

**Step 1: Add error trap for cleanup**

Add this near the top of the script, after function definitions start:

```bash
# Global variables for error handling
INSTALLING_VERSION=""
PREV_SYMLINK_TARGET=""

# Trap errors and clean up
trap cleanup_on_error EXIT

cleanup_on_error() {
  local exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    echo ""
    echo "❌ Installation failed, cleaning up..."

    # Clean up partial installation
    if [ -n "$INSTALLING_VERSION" ] && [ -d "/usr/local/go-$INSTALLING_VERSION" ]; then
      echo "  Removing partial installation..."
      sudo rm -rf "/usr/local/go-$INSTALLING_VERSION"
    fi

    # Clean up downloaded files
    [ -n "$INSTALLING_VERSION" ] && rm -f "/tmp/$INSTALLING_VERSION"*.tar.gz

    # Restore previous symlink if it existed
    if [ -n "$PREV_SYMLINK_TARGET" ]; then
      echo "  Restoring previous symlink..."
      sudo ln -sfn "$PREV_SYMLINK_TARGET" /usr/local/go
    fi
  fi
}
```

**Step 2: Add permission checks**

Add to the beginning of main():

```bash
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
```

**Step 3: Update install_go_version to set error handling vars**

Modify the function to save state for rollback:

```bash
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

  # ... rest of function remains the same ...
}
```

**Step 4: Add version format validation**

```bash
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
```

Use this in download_go_version() and install_go_version().

**Step 5: Test error handling**

```bash
# Test invalid version
./install_go.sh --version "invalid"
# Expected: Error about invalid format

# Test permission check (if you can temporarily test without sudo)
# Expected: Graceful error message
```

**Step 6: Commit error handling**

```bash
git add install_go.sh
git commit -m "feat: add comprehensive error handling

Add trap for cleanup on errors. Save symlink state for rollback.
Add permission checks. Add version format validation.
Improves robustness and user experience."
```

---

## Task 10: Refactor and Cleanup

**Files:**
- Modify: `install_go.sh` (remove old code, organize)
- Test: Verify script still works

**Step 1: Remove old install_latest_go function**

The old monolithic function should be completely removed now that we have all the new modular functions. Search for:

```bash
# Function to install or update Go
install_latest_go() {
```

Remove the entire function (it should be the last big function before main).

**Step 2: Organize function order**

Arrange functions in logical order:

1. Utility functions (detect_architecture, normalize_version, validate_version)
2. State discovery (fetch_latest_version, get_active_version, list_installed_versions)
3. Installation (download_go_version, install_go_version, switch_go_version)
4. Configuration (detect_profile_file, configure_environment)
5. Migration (migrate_legacy_install)
6. Interactive (prompt_smart, show_version_menu, cleanup_versions)
7. Help (show_help)
8. Error handling (cleanup_on_error)
9. Parsing (parse_arguments)
10. Main (main)

**Step 3: Add script header**

Add at the top of the file after the shebang:

```bash
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
```

**Step 4: Verify script syntax**

```bash
# Check for syntax errors
bash -n install_go.sh
# Expected: No output (means no syntax errors)

# Check script is executable
ls -l install_go.sh
# Expected: -rwxr-xr-x (executable)
```

**Step 5: Test complete workflow**

```bash
# Test help
./install_go.sh --help

# Test list
./install_go.sh --list

# If on test system, test full install
# ./install_go.sh -y
```

**Step 6: Commit refactoring**

```bash
git add install_go.sh
git commit -m "refactor: clean up script organization

Remove old monolithic install_latest_go function.
Organize functions in logical order.
Add comprehensive script header.
Verify syntax and functionality."
```

---

## Task 11: Update Documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Step 1: Update README.md**

Update to reflect new features. Key changes:

- Update usage examples to show new features
- Add examples for version switching
- Document new command-line options
- Update example output for new format

**Step 2: Update CLAUDE.md**

Add information about:
- New multi-version architecture
- Command-line interface options
- Function organization
- Testing approach for new features

**Step 3: Commit documentation updates**

```bash
git add README.md CLAUDE.md
git commit -m "docs: update for version manager features

Document new multi-version support, command-line options,
version switching, and cleanup functionality."
```

---

## Task 12: Final Testing and Verification

**Files:**
- Test: `install_go.sh` (comprehensive testing)
- Create: Verification checklist

**Step 1: Create test verification script**

Create `docs/verify-implementation.sh`:

```bash
#!/bin/bash

echo "=== Go Version Manager Implementation Verification ==="
echo ""

# Test 1: Syntax check
echo "[1/8] Checking syntax..."
if bash -n install_go.sh; then
  echo "✓ Syntax valid"
else
  echo "✗ Syntax errors found"
  exit 1
fi

# Test 2: Help works
echo "[2/8] Testing help..."
if ./install_go.sh --help &>/dev/null; then
  echo "✓ Help works"
else
  echo "✗ Help failed"
  exit 1
fi

# Test 3: List works
echo "[3/8] Testing list..."
if ./install_go.sh --list &>/dev/null; then
  echo "✓ List works"
else
  echo "✗ List failed"
  exit 1
fi

# Test 4: Architecture detection
echo "[4/8] Testing architecture detection..."
source install_go.sh
arch=$(detect_architecture)
if [[ "$arch" =~ ^(amd64|arm64|armv6l)$ ]]; then
  echo "✓ Architecture detected: $arch"
else
  echo "✗ Invalid architecture: $arch"
  exit 1
fi

# Test 5: Version fetching
echo "[5/8] Testing version fetching..."
latest=$(fetch_latest_version)
if [[ "$latest" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "✓ Latest version: $latest"
else
  echo "✗ Failed to fetch version"
  exit 1
fi

# Test 6: Profile detection
echo "[6/8] Testing profile detection..."
profile=$(detect_profile_file)
if [ -n "$profile" ]; then
  echo "✓ Profile detected: $profile"
else
  echo "✗ Failed to detect profile"
  exit 1
fi

# Test 7: State discovery
echo "[7/8] Testing state discovery..."
state=$(get_active_version)
if [ -n "$state" ]; then
  echo "✓ State discovery works"
else
  echo "✗ State discovery failed"
  # This is OK if no Go installed
fi

# Test 8: Version normalization
echo "[8/8] Testing version normalization..."
v1=$(normalize_version "go1.21.0")
v2=$(normalize_version "1.21.0")
if [ "$v1" == "$v2" ] && [ "$v1" == "1.21.0" ]; then
  echo "✓ Version normalization works"
else
  echo "✗ Version normalization failed"
  exit 1
fi

echo ""
echo "=== All tests passed ==="
```

**Step 2: Run verification**

```bash
chmod +x docs/verify-implementation.sh
./docs/verify-implementation.sh
```

**Step 3: Create manual testing checklist**

Create `docs/testing-checklist.md`:

```markdown
# Manual Testing Checklist

## Prerequisites
- Linux test system (can be VM)
- sudo access
- curl installed

## Test Scenarios

### Fresh Install (No Go)
- [ ] Run `./install_go.sh`
- [ ] Verify prompt shows latest version
- [ ] Accept installation
- [ ] Verify `/usr/local/go` is symlink
- [ ] Verify version directory exists: `/usr/local/go-X.Y.Z`
- [ ] Run `go version` - shows correct version
- [ ] Check `echo $GOPATH $GOBIN` - set correctly
- [ ] New shell session has Go in PATH

### Upgrade Existing Install
- [ ] Start with older Go version
- [ ] Run `./install_go.sh`
- [ ] Verify upgrade prompt appears
- [ ] Accept upgrade
- [ ] Verify both version directories exist
- [ ] Verify symlink points to new version
- [ ] Old version still available for switching

### Version Switching
- [ ] Install two different versions
- [ ] Run `./install_go.sh` → choose "s" for switch
- [ ] Select different version
- [ ] Verify symlink updated
- [ ] Run `go version` - shows switched version
- [ ] Use `--version X.Y.Z` flag
- [ ] Verify direct switch works

### Cleanup
- [ ] Install 3+ versions
- [ ] Run cleanup after install
- [ ] Test "all" option
- [ ] Test "specific" option
- [ ] Test "none" option
- [ ] Verify active version never removed
- [ ] Run `./install_go.sh --cleanup -y`
- [ ] Verify silent cleanup works

### Silent Mode
- [ ] Run `./install_go.sh -y`
- [ ] Verify no prompts appear
- [ ] Verify automatic install/upgrade
- [ ] Combine with `--version`
- [ ] Combine with `--cleanup`

### Legacy Migration
- [ ] Create legacy install at `/usr/local/go` (directory, not symlink)
- [ ] Run script
- [ ] Verify migration prompt appears
- [ ] Accept migration
- [ ] Verify renamed to `/usr/local/go-X.Y.Z`
- [ ] Verify symlink created
- [ ] Verify Go still works

### Error Handling
- [ ] Run without sudo - graceful error
- [ ] Try invalid version format - clear error
- [ ] Disconnect network - download fails gracefully
- [ ] Try switching to non-existent version - helpful error

## Architecture Tests
- [ ] amd64 (x86_64)
- [ ] arm64 (aarch64) if available
- [ ] armv6l if available
```

**Step 4: Run through checklist**

On a test system, go through the manual testing checklist.

**Step 5: Commit verification tools**

```bash
git add docs/verify-implementation.sh docs/testing-checklist.md
git commit -m "test: add verification and testing tools

Add automated verification script for syntax and basic function
tests. Add manual testing checklist for comprehensive QA."
```

---

## Task 13: Final Review and Integration

**Files:**
- Review: All modified files
- Test: Complete end-to-end test

**Step 1: Review all changes**

```bash
# Show all commits in this branch
git log --oneline master..HEAD

# Show diff from master
git diff master..HEAD
```

**Step 2: Ensure script is executable**

```bash
chmod +x install_go.sh
ls -l install_go.sh
```

**Step 3: Final end-to-end test**

On a test system (or VM):

```bash
# Clone the worktree or copy script
./install_go.sh --help
./install_go.sh --list

# If you can safely test:
./install_go.sh -y
./install_go.sh --version 1.20.5
./install_go.sh --cleanup
```

**Step 4: Update README.md with new workflow**

Ensure README reflects:
- New command-line options
- Multi-version capability
- Version switching examples
- Cleanup instructions

**Step 5: Final commit**

```bash
git add .
git commit -m "chore: final review and polish

Complete implementation of Go version manager.
All features tested and documented.
Ready for merge."
```

---

## Post-Implementation Tasks

### Merge Preparation

**Step 1: Squash to meaningful commits (optional)**

```bash
# Review commits
git log --oneline

# If desired, squash into logical chunks:
# - Core utility functions
# - State discovery
# - Installation and switching
# - Interactive features
# - Error handling
# - Documentation
```

**Step 2: Update version/changelog (if applicable)**

**Step 3: Prepare for PR**

```bash
# Push to remote
git push -u origin feature/go-version-manager

# Create PR with description referencing design doc:
# See: docs/plans/2026-01-20-go-version-manager-design.md
```

### Cleanup

**Step 1: Remove worktree after merge**

```bash
git worktree remove .worktrees/go-version-manager
git branch -d feature/go-version-manager
```

---

## Success Criteria

✓ All functions implemented as per design
✓ Command-line interface matches specification
✓ Error handling covers edge cases
✓ Documentation updated
✓ Manual testing checklist completed
✓ Script runs without syntax errors
✓ Backward compatible (migrates legacy installs)

---

## Notes

- This script has no automated test suite - manual verification is required
- Test on disposable system or VM if possible
- Always backup before running on production systems
- Legacy migration is one-way - test thoroughly before deploying
