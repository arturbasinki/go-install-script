# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a minimal, single-purpose repository containing a Bash script (`install_go.sh`) that manages multiple Go installations side-by-side with easy version switching. It automatically detects system architecture, downloads Go versions from go.dev, and provides interactive and silent modes for installation and management.

**Important:** This repository has no build system, test suite, CI/CD pipeline, or development dependencies. It's a single Bash script with documentation.

## Architecture Overview

### Version Management Design

The script uses a symlink-based architecture for multi-version support:

1. **Versioned Installations**: Each Go version is installed to a separate directory:
   - `/usr/local/go-1.23.1/`
   - `/usr/local/go-1.22.5/`
   - `/usr/local/go-1.21.0/`

2. **Active Version Symlink**: A symlink at `/usr/local/go` points to the active version:
   - `/usr/local/go -> /usr/local/go-1.23.1`

3. **Instant Switching**: Changing versions updates the symlink without reinstallation

4. **Environment Configuration**: Single PATH entry (`/usr/local/go/bin`) always points to active version

### Command-Line Interface

The script supports multiple operation modes:

**Interactive Mode** (default):
- Smart prompts based on current installation state
- Detects: no installation, outdated version, or latest version
- Offers appropriate actions for each scenario
- Shows menu of installed versions for switching

**Silent Mode** (`-y, --yes`):
- Non-interactive operation
- Accepts all defaults
- Perfect for automation and CI/CD

**Version-Specific Mode** (`--version VERSION`):
- Install specific version if not present
- Switch to version if already installed
- Validates version format before installation

**Utility Modes**:
- `--list`: Show all installed versions and latest available
- `--cleanup`: Interactive removal of old versions
- `-h, --help`: Display usage information

## Script Structure

### Core Functions (Execution Flow)

1. **`main()`** - Entry point and orchestration
   - Parses command-line arguments
   - Handles special modes (list, cleanup, version)
   - Manages legacy migration
   - Invokes smart interactive prompts by default

2. **`parse_arguments()`** - Command-line argument parsing
   - Sets global mode flags (SILENT_MODE, CLEANUP_ONLY, LIST_ONLY, TARGET_VERSION)
   - Validates version format
   - Shows help when requested

3. **`prompt_smart()`** - Interactive mode with context-aware prompts
   - Detects current state (no install, outdated, current)
   - Offers appropriate actions for each scenario
   - Falls back to silent behavior if SILENT_MODE=true

### Installation Functions

4. **`detect_architecture()`** - System architecture detection
   - Maps `uname -m` output to Go architecture names
   - Returns: `amd64`, `arm64`, or `armv6l`
   - Exits with error 1 for unsupported architectures

5. **`fetch_latest_version()`** - Get latest Go version
   - Scrapes https://go.dev/dl/ HTML
   - Returns version string (e.g., "go1.23.1")

6. **`download_go_version()`** - Download Go tarball with validation
   - Downloads with timeout and retry logic
   - Verifies tarball integrity
   - Returns path to downloaded file

7. **`install_go_version()`** - Install Go to versioned directory
   - Downloads tarball
   - Checks disk space
   - Extracts to temporary location
   - Moves to versioned directory (`/usr/local/go-VERSION`)
   - Sets global INSTALLING_VERSION for error handler

8. **`switch_go_version()`** - Update active version symlink
   - Verifies version exists and has valid binary
   - Updates `/usr/local/go` symlink
   - Displays new version

9. **`migrate_legacy_install()`** - Convert old single-version installs
   - Detects legacy `/usr/local/go` directory
   - Prompts for confirmation (unless silent mode)
   - Renames to versioned directory
   - Creates symlink with rollback on failure

### Version Management Functions

10. **`get_active_version()`** - Detect current Go installation
    - Method 1: Check `go` command in PATH
    - Method 2: Check `/usr/local/go` symlink
    - Method 3: Check legacy `/usr/local/go` directory
    - Returns: pipe-delimited "version|location|goroot"

11. **`list_installed_versions()`** - List all installed versions
    - Scans `/usr/local/go-*` directories
    - Returns sorted list (newest first)

12. **`show_version_menu()`** - Interactive version switching
    - Displays numbered list of installed versions
    - Marks current version
    - Handles user selection

13. **`cleanup_versions()`** - Remove old Go versions
    - Shows installed versions with active marked
    - Interactive: remove all, specific, or none
    - Silent mode: removes all old versions automatically
    - Never removes currently active version

### Environment Configuration

14. **`detect_profile_file()`** - Find appropriate shell profile
    - Checks SHELL environment variable
    - Returns best match for bash, zsh, fish
    - Falls back to `~/.profile`

15. **`configure_environment()`** - Set up Go environment variables
    - GOPATH: `$HOME/go`
    - GOBIN: `$GOPATH/bin`
    - PATH: Adds `/usr/local/go/bin` and `$GOBIN`
    - Updates profile file (avoids duplicates)
    - Exports for current session

### Helper Functions

16. **`normalize_version()`** - Remove 'go' prefix from version string
    - "go1.23.1" -> "1.23.1"

17. **`validate_version()`** - Validate version format
    - Checks regex: `^[0-9]+\.[0-9]+(\.[0-9]+)?$`
    - Accepts "1.23.1" or "go1.23.1"
    - Returns normalized version or error

18. **`show_help()`** - Display usage information
    - Shows all options
    - Provides examples

19. **`cleanup_on_error()`** - Error trap handler
    - Triggered on non-zero exit codes
    - Removes partial installations
    - Cleans up downloaded files
    - Restores previous symlink

### Global Variables

- `INSTALLING_VERSION`: Set during installation for error handler
- `PREV_SYMLINK_TARGET`: Saved before installation for potential rollback
- `SILENT_MODE`: Controls interactive behavior
- `CLEANUP_ONLY`: Mode flag for cleanup operation
- `LIST_ONLY`: Mode flag for list operation
- `TARGET_VERSION`: Version to install/switch to

## Error Handling

### Error Recovery

The script uses Bash's `trap ERR` mechanism for automatic cleanup:

1. **Partial Installation Cleanup**: If installation fails, removes the partially extracted directory
2. **Download Cleanup**: Removes downloaded tar files on failure
3. **Symlink Restoration**: Restores previous symlink target if installation fails
4. **Legacy Migration Rollback**: Atomic rollback with verification if migration fails

### Validation

- Version format validation before installation
- Disk space check before extraction
- Tarball integrity verification after download
- Go binary verification after installation
- Symlink verification after switching

### Exit Codes

- `0`: Success
- `1`: Error (invalid input, installation failure, permission denied, unsupported architecture)

## Testing and Verification

### Manual Testing

The script has no automated test suite. Verify functionality manually:

```bash
# Test architecture detection
uname -m

# Test latest version fetch
curl -s https://go.dev/dl/ | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1

# Test installation
./install_go.sh --version 1.21.0

# Verify installation
ls -la /usr/local/go-1.21.0/
/usr/local/go-1.21.0/bin/go version

# Test version switching
./install_go.sh --version 1.22.0
./install_go.sh --version 1.21.0

# Test list
./install_go.sh --list

# Test cleanup
./install_go.sh --cleanup

# Verify environment
echo $GOPATH
echo $GOBIN
echo $PATH | tr ':' '\n' | grep go
```

### Test Scenarios

1. **Fresh Installation**: No previous Go installation
2. **Upgrade**: Outdated Go version installed
3. **Downgrade**: Newer version installed, switching to older
4. **Legacy Migration**: Old `/usr/local/go` directory present
5. **Silent Mode**: All operations with `-y` flag
6. **Cleanup**: Multiple versions installed, remove old ones
7. **Error Recovery**: Test failure scenarios (network, disk space)

## Development Notes

### Design Principles

1. **Idempotent**: Safe to run multiple times
2. **Non-Destructive**: Keeps multiple versions, never removes without explicit action
3. **User-Friendly**: Smart prompts, clear messages, safe defaults
4. **Automation-Ready**: Silent mode for CI/CD
5. **Safe Error Handling**: Automatic cleanup on failures
6. **Backward Compatible**: Migrates legacy installations automatically

### Key Implementation Details

**Privilege Handling**:
- Checks `$(id -u)` to determine if root (0) or regular user
- Uses `sudo` prefix for installation commands when running as regular user
- Tests sudo access before attempting operations
- Provides clear error messages if sudo unavailable

**Download Strategy**:
- Uses `curl -fsSL` with 300-second timeout
- Implements retry logic (3 attempts)
- Verifies tarball integrity before extraction
- Cleans up temporary files

**Disk Space Check**:
- Calculates required space (2x tarball size)
- Compares with available space in `/usr/local`
- Fails fast with clear message if insufficient space

**Symlink Management**:
- Uses `ln -sfn` for atomic symlink updates
- Saves previous target for potential rollback
- Verifies symlink target has valid Go binary

**Profile File Updates**:
- Detects appropriate file based on shell
- Checks for existing entries before adding (no duplicates)
- Creates file/directory if missing
- Updates both profile and current session

### Recent Development History

Based on git log, the script evolved from:
- Original: Single-version installer (always installed to `/usr/local/go`)
- Current: Multi-version manager with symlink-based switching

Major improvements include:
- Multi-version support with versioned directories
- Symlink-based active version management
- Interactive mode with context-aware prompts
- Silent mode for automation
- Version-specific installation and switching
- Cleanup functionality for old versions
- Legacy migration support
- Comprehensive error handling with automatic cleanup
- Disk space validation
- Enhanced profile file detection

### Known Limitations

1. **Linux Only**: Designed for Linux systems (uses `uname -m`, assumes Linux paths)
2. **System-Wide Only**: Installs to `/usr/local`, requires root/sudo
3. **No Go Module Support**: Doesn't manage project-specific Go versions (like `.tool-versions`)
4. **Manual Testing Only**: No automated test suite
5. **Single Script**: All functionality in one file (no modularity for code reuse)

### Future Enhancement Ideas

1. **User-Only Mode**: Option to install to `$HOME/.go` without sudo
2. **Project-Specific Versions**: Integration with `.tool-versions` or direnv
3. **Download Caching**: Keep tarballs for faster reinstallation
4. **Version Aliases**: Allow naming versions (e.g., "stable", "old-project")
5. **Automated Testing**: Add test suite for validation
6. **Completion Scripts**: Bash/Zsh completion for options and versions
