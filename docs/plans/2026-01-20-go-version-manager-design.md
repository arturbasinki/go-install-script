# Go Version Manager - Design Document

**Date:** 2026-01-20
**Status:** Design Phase
**Author:** Claude Code + arturbasinki

## Overview

Transform the single-purpose Go installer script into an intelligent version manager supporting multiple installed versions, interactive workflows, and automation-friendly operation while maintaining complete Linux distribution portability.

## Purpose

Create a universal Go installation and version management tool that:
- Works on any Linux distribution without distro-specific logic
- Manages multiple Go versions side-by-side
- Provides intelligent interactive prompts with automation support
- Handles edge cases gracefully (legacy installs, package conflicts, errors)
- Migrates existing single-install setups seamlessly

## Architecture

### Version Storage Model

**Side-by-side installation with active symlink:**

```
/usr/local/go-1.21.0/          # Go 1.21.0 installation
/usr/local/go-1.20.5/          # Go 1.20.5 installation
/usr/local/go-1.19.0/          # Go 1.19.0 installation
/usr/local/go -> go-1.21.0     # Symlink to active version
```

**Benefits:**
- Instant version switching by updating symlink
- All versions available for rollback
- Clean separation between versions
- Transparent to PATH configuration

### Command-Line Interface

```
install_go.sh [OPTIONS]

Options:
  -y, --yes              Silent mode - accept all defaults (no prompts)
  --version VERSION      Install or switch to specific version (e.g., 1.20.5)
  --cleanup              Run cleanup mode without installing
  --list                 List installed and available versions
  -h, --help             Show help message
```

### Operational Modes

1. **Smart Interactive (default)**
   - Detects current state and prompts appropriately
   - Context-aware menus based on installed versions
   - Cleanup prompts after successful operations

2. **Silent Mode (`-y` or `--yes`)**
   - No prompts, automatic actions
   - Ideal for CI/CD and automation
   - Sensible defaults for all decisions

3. **Version-Specific Mode (`--version X.Y.Z`)**
   - If version exists: switch symlink to that version
   - If version missing: download, install, then switch
   - Compatible with `-y` for automation

4. **Cleanup Mode**
   - Interactive menu for removing old versions
   - Triggered automatically after install, or via `--cleanup` flag
   - Spacebar-toggled checkboxes for selection

## State Discovery

### Comprehensive Go Detection

**Priority order:**
1. Check if `go` command exists in PATH → extract version via `go version`
2. Check standard symlink location `/usr/local/go` → parse target
3. Check legacy directory `/usr/local/go` → run binary directly
4. No Go found

**Implementation:**
```bash
get_active_version() {
  # Method 1: Check PATH
  if command -v go &>/dev/null; then
    version=$(go version | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?')
    location=$(which go)
    GOROOT=$(go env GOROOT 2>/dev/null || echo "")
    echo "$version|$location|$GOROOT"
    return 0
  fi

  # Method 2: Check symlink
  if [ -L "/usr/local/go" ]; then
    local target=$(readlink -f /usr/local/go)
    version=$(echo $target | grep -oP 'go-[0-9]+\.[0-9]+(\.[0-9]+)?')
    echo "$version|/usr/local/go/bin/go|$target"
    return 0
  fi

  # Method 3: Check legacy directory
  if [ -d "/usr/local/go/bin" ]; then
    version=$(/usr/local/go/bin/go version 2>/dev/null | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?')
    if [ -n "$version" ]; then
      echo "$version|/usr/local/go/bin/go|/usr/local/go"
      return 0
    fi
  fi

  echo "||"
  return 1
}
```

### List Installed Versions

**Scan filesystem for version directories:**
```bash
list_installed_versions() {
  # Find all /usr/local/go-* directories
  # Extract versions from directory names
  # Sort semantically (newest first)
  # Return as array
}
```

### Fetch Latest Version

**Scrape go.dev/dl/ (existing method):**
```bash
fetch_latest_version() {
  LATEST_GO_VERSION=$(curl -s https://go.dev/dl/ | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
  echo "$LATEST_GO_VERSION"
}
```

## Smart Prompt Logic

### Decision Tree

```
IF no Go installed:
    prompt: "Latest: $LATEST_GO_VERSION. Install now? (y/n)"

ELSE IF current < latest:
    prompt: "Current: $current, Latest: $latest. Upgrade? (y/n/s/exit)"
    y → upgrade to latest
    s → show installed versions submenu
    n → cancel

ELSE IF current == latest:
    prompt: "$current is latest. Install another version? (y/n/exit)"
    y → prompt for specific version or show available
```

### Example Prompts

**Fresh install:**
```
No Go installation detected.
Latest available: go1.21.0
Install now? (y/n)
```

**Upgrade available:**
```
Current installation: go1.20.5 (at /usr/local/go)
Latest available: go1.21.0
Installed versions: go1.20.5, go1.19.0

Options:
  y - Upgrade to go1.21.0
  s - Switch to different installed version
  n - Cancel

Choice [y/s/n]:
```

**Already latest:**
```
Current installation: go1.21.0 (latest)
No upgrade available.

Options:
  y - Install additional version
  n - Exit

Choice [y/n]:
```

## Installation and Switching Process

### Installation Workflow

1. **Download** - Fetch tarball to `/tmp/go-{version}.linux-{arch}.tar.gz`
2. **Extract** - `tar -C /usr/local -xzf /tmp/{tarball}` → creates `/usr/local/go`
3. **Rename** - `mv /usr/local/go /usr/local/go-{version}`
4. **Update symlink** - `ln -sfn /usr/local/go-{version} /usr/local/go`
5. **Configure environment** - Add GOPATH/GOBIN/PATH to appropriate shell profile
6. **Verify** - Run `go version` to confirm success

### Version Switch Workflow

1. **Verify requested version exists** - Check `/usr/local/go-{version}` directory
2. **Update symlink** - `ln -sfn /usr/local/go-{version} /usr/local/go`
3. **Verify** - Run `go version` to confirm switch

## Shell Configuration

### Shell-Aware Profile Detection

**Auto-detect user's shell and appropriate config file:**

```bash
detect_profile_file() {
  case "$SHELL" in
    */bash)
      # Prefer ~/.bashrc, fallback to ~/.bash_profile, then ~/.profile
      if [ -f "$HOME/.bashrc" ]; then
        echo "$HOME/.bashrc"
      elif [ -f "$HOME/.bash_profile" ]; then
        echo "$HOME/.bash_profile"
      else
        echo "$HOME/.profile"  # Will create if missing
      fi
      ;;
    */zsh)
      # Zsh uses ~/.zshrc or ~/.zprofile
      if [ -f "$HOME/.zshrc" ]; then
        echo "$HOME/.zshrc"
      elif [ -f "$HOME/.zprofile" ]; then
        echo "$HOME/.zprofile"
      else
        echo "$HOME/.zshrc"  # Will create if missing
      fi
      ;;
    */fish)
      echo "$HOME/.config/fish/config.fish"
      ;;
    *)
      # Fallback for dash, ash, sh, etc. - POSIX standard
      echo "$HOME/.profile"
      ;;
  esac
}
```

**Universal fallback:**
- If detected file doesn't exist, create it (except fish which needs directory)
- For unknown shells: always use `~/.profile` (POSIX standard)
- For fish: create `~/.config/fish/` directory if needed

**Environment variables set:**
```bash
export GOPATH=$HOME/go
export GOBIN=$GOPATH/bin
export PATH=$PATH:/usr/local/go/bin:$GOBIN
```

## Cleanup Functionality

### Cleanup Menu (Interactive)

```
Installed versions:
  ✓ go1.21.0 (active)
    go1.20.5
    go1.19.0

Remove old versions? (all/specific/none/exit)
> all      - Remove all except active
> specific - Choose which versions to remove
> none     - Keep all versions
> exit     - Cancel
```

### Specific Version Selection

**Spacebar-toggled checklist (using dialog/whiptail):**

```bash
if command -v dialog &>/dev/null; then
  # Use dialog --checklist for spacebar-toggled selection
elif command -v whiptail &>/dev/null; then
  # Use whiptail --checklist
else
  # Fallback to simple numbered list with space-separated input
fi
```

**Safety checks:**
- Active version is NEVER in removal list
- Verify symlink points to valid directory before deletion
- Confirm directory contains valid Go installation (`bin/go` executable)
- Dry-run option: `--cleanup --dry-run`

### Silent Mode Cleanup

- `install_go.sh -y --cleanup` → removes all versions except active without prompts
- Requires explicit `--cleanup` flag (not automatic in silent mode)

## Error Handling

### Download Failures

```bash
download_go_version() {
  local version=$1
  local arch=$(detect_architecture)
  local tar_file="${version}.linux-${arch}.tar.gz"
  local download_url="https://go.dev/dl/${tar_file}"

  # Download with timeout and retry
  if ! curl -fsSL --max-time 300 --retry 3 "$download_url" -o "/tmp/$tar_file"; then
    echo "❌ Failed to download Go $version"
    echo "   Check your internet connection or verify version exists"
    return 1
  fi

  # Verify tarball integrity
  if ! tar -tzf "/tmp/$tar_file" &>/dev/null; then
    echo "❌ Downloaded file is corrupted"
    rm -f "/tmp/$tar_file"
    return 1
  fi
}
```

### Disk Space Check

```bash
# Verify sufficient disk space before extraction
required_space=$(du -k "/tmp/$tar_file" | cut -f1)
available_space=$(df -k /usr/local | tail -1 | awk '{print $4}')
if [ "$available_space" -lt "$((required_space * 2))" ]; then
  echo "❌ Insufficient disk space in /usr/local"
  return 1
fi
```

### Permission Handling

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
    echo "❌ This script requires sudo privileges"
    exit 1
  fi
fi
```

### Rollback on Failure

```bash
# Trap errors and clean up partial installations
trap cleanup_on_error EXIT

cleanup_on_error() {
  local exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    echo "❌ Installation failed, cleaning up..."
    [ -d "/usr/local/go-$INSTALLING_VERSION" ] && sudo rm -rf "/usr/local/go-$INSTALLING_VERSION"
    [ -f "/tmp/$INSTALLING_VERSION"*.tar.gz ] && rm -f "/tmp/$INSTALLING_VERSION"*.tar.gz"

    # Restore previous symlink if it existed
    if [ -n "$PREV_SYMLINK_TARGET" ]; then
      ln -sfn "$PREV_SYMLINK_TARGET" /usr/local/go
    fi
  fi
}
```

## Migration Path

### Legacy Installation Handling

**Detection:**
```bash
if [ -d "/usr/local/go" ] && [ ! -L "/usr/local/go" ]; then
  if [ -x "/usr/local/go/bin/go" ]; then
    version=$(/usr/local/go/bin/go version | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?')
    echo "⚠️  Legacy installation detected: $version"
    echo ""
    echo "   This script now manages multiple Go versions side-by-side."
    echo "   Your existing installation will be migrated to the new format."
    echo ""
    read -p "   Continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      # Migrate
      sudo mv /usr/local/go /usr/local/go-$version
      sudo ln -s /usr/local/go-$version /usr/local/go
      echo "✓ Migrated to: /usr/local/go-$version"
    else
      exit 0
    fi
  fi
fi
```

**Migration behavior:**
- Automatically detects old-style directory installs
- Prompts user before migrating (skipped with `-y` flag)
- Renames directory to versioned format
- Creates symlink in its place
- Existing PATH/GOPATH/GOBIN configuration remains valid

**Safety during migration:**
- Verify Go is working before migration
- Backup directory: `cp -r /usr/local/go /usr/local/go.backup`
- Rollback on error: restore from backup

## Package Manager Warning

**If Go detected in `/usr/bin` or `/usr/lib`:**

```
⚠️  Go appears to be installed via package manager.
   This script manages Go in /usr/local/go-* (side-by-side versions).
   Consider removing package-installed Go to avoid conflicts:

   Debian/Ubuntu: sudo apt remove golang-go
   Fedora:        sudo dnf remove golang
   Arch:          sudo pacman -R go
   Alpine:        sudo apk del go

   Continue anyway? (y/n)
```

## Code Structure

### Main Functions

```bash
detect_architecture()          # Existing - detect amd64/arm64/armv6l
detect_profile_file()          # NEW - shell-aware profile detection
get_active_version()           # NEW - extract from symlink, binary, or PATH
list_installed_versions()      # NEW - scan /usr/local/go-* directories
fetch_latest_version()         # Enhanced from existing - scrape go.dev/dl
download_go_version()          # NEW - download with validation
install_go_version()           # Enhanced - download, extract, rename, symlink
switch_go_version()            # NEW - update symlink to existing version
cleanup_versions()             # NEW - remove old versions with interactive menu
show_version_menu()            # NEW - display and select from installed versions
prompt_smart()                 # NEW - intelligent prompts based on state
configure_environment()        # Extracted from existing - GOPATH/GOBIN/PATH
verify_installation()          # Extracted from existing - go version check
migrate_legacy_install()       # NEW - convert old installs to new format
parse_arguments()              # NEW - handle command-line flags
main()                         # NEW - orchestrate the flow
```

### Refactoring Strategy

1. Extract existing monolithic `install_latest_go()` into smaller functions
2. Add state discovery functions
3. Add interactive menu functions
4. Keep single-purpose functions focused
5. Maintain backward compatibility with existing behavior

## Supported Architectures

- `amd64` (x86_64) - Standard 64-bit Intel/AMD
- `arm64` (aarch64) - 64-bit ARM (Apple Silicon, ARM servers)
- `armv6l` - 32-bit ARM (Raspberry Pi and similar)

Auto-detected via `uname -m`, no manual configuration needed.

## Testing Strategy

**Note:** This repository has no automated test suite. Verification is manual.

### Core Test Scenarios

1. **Fresh install on empty system**
   - No existing Go
   - Verify latest version downloads and installs
   - Check symlink created: `ls -la /usr/local/go`
   - Verify PATH and `go version` works

2. **Upgrade from previous version**
   - Start with Go 1.20.5 installed
   - Run script, upgrade to 1.21.0
   - Verify both versions exist
   - Verify symlink points to new version

3. **Version switching**
   - With multiple versions, use `--version 1.20.5`
   - Verify symlink updates
   - Run `go version` to confirm

4. **Cleanup functionality**
   - Install 3 versions
   - Run cleanup, remove 2 oldest
   - Verify active version remains

5. **Legacy migration**
   - Set up old-style `/usr/local/go` directory
   - Run script, verify migration prompt
   - Confirm renamed to versioned format with symlink

6. **Silent mode automation**
   - `./install_go.sh -y` - no prompts
   - `./install_go.sh -y --version 1.20.5` - specific version
   - Verify no interactive prompts

7. **Different shells**
   - Test with bash, zsh, dash
   - Verify profile detection works
   - Check environment variables

8. **Error scenarios**
   - No sudo/internet (graceful failure)
   - Invalid version format (error message)
   - Corrupted download (detect and retry/fail)

### Verification Commands

```bash
# After install
go version                    # Should show installed version
ls -la /usr/local/go          # Should be symlink
ls -la /usr/local/go-*        # Should show all versions
echo $GOPATH $GOBIN           # Should be set
which go                      # Should point to /usr/local/go/bin/go
```

## Implementation Notes

### Dependencies

**Required:**
- `curl` - downloading Go tarballs
- `tar` - extracting archives
- `grep` with `-P` (Perl regex) - version parsing
- `sudo` - for non-root installations

**Optional (for better UX):**
- `dialog` - interactive checkboxes for cleanup
- `whiptail` - fallback for checkboxes

### Version Format Handling

Accept both formats:
- `1.21.0` - plain version
- `go1.21.0` - with "go" prefix

Normalize internally to plain version without prefix.

### Key Design Principles

1. **Distro-agnostic** - No distro-specific logic, works on any Linux
2. **Backward compatible** - Migrates existing installs seamlessly
3. **Interactive first, automation ready** - Smart prompts by default, silent mode available
4. **Safe by default** - Validates actions, rollback on errors, never removes active version
5. **Transparent** - Shows what's happening, confirms before destructive actions
6. **Portable** - Minimal dependencies, works on minimal systems

## Future Enhancements (Out of Scope)

- HTTP proxy support for downloads
- Custom download directory/mirror support
- Integration with version managers like `asdf` or `mise`
- Windows/macOS support (current design: Linux only)
- Automated test suite
- Configuration file for default behaviors
- Version pinning files (e.g., `.go-version` in project directory)
