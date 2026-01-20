# Go Version Manager

A Bash script that automatically detects your system architecture, downloads Go versions, and manages multiple installations side-by-side with easy version switching.

## Features

- **Multi-Version Support**: Install and manage multiple Go versions simultaneously
- **Smart Interactive Mode**: Context-aware prompts based on current installation state
- **Silent Mode**: Non-interactive operation for automation and CI/CD
- **Version Switching**: Instantly switch between installed Go versions
- **Automatic Updates**: Detects and installs the latest Go version
- **Architecture Detection**: Supports `amd64`, `arm64`, and `armv6l`
- **Cleanup Tools**: Remove old versions interactively or automatically
- **Legacy Migration**: Automatically migrates old single-version installs
- **Environment Setup**: Configures GOPATH, GOBIN, and PATH automatically

## Prerequisites

- A Linux-based operating system.
- `curl` installed (usually pre-installed on most Linux distributions).
- `sudo` privileges (for installing Go system-wide).

## Usage

### Command-Line Options

```bash
install_go.sh [OPTIONS]
```

**Options:**
- `-y, --yes` - Silent mode (no prompts, accepts defaults)
- `-v, --version VERSION` - Install or switch to specific version (e.g., `1.20.5`)
- `--cleanup` - Run cleanup mode to remove old versions (long-only for safety)
- `-l, --list` - List all installed Go versions (marks active version)
- `-h, --help` - Show help message

### Option 1: Run Directly from GitHub

```bash
curl -sSL https://raw.githubusercontent.com/arturbasinki/go-install-script/refs/heads/master/install_go.sh | bash
```

### Option 2: Clone and Run Locally

1. Clone the repository:
   ```bash
   git clone https://github.com/arturbasinki/go-install-script.git
   cd go-install-script
   ```

2. Make the script executable:
   ```bash
   chmod +x install_go.sh
   ```

3. Run the script:
   ```bash
   ./install_go.sh          # Interactive mode
   ./install_go.sh -y        # Silent mode (latest version)
   ./install_go.sh -v 1.20.5 # Specific version
   ./install_go.sh -l        # List installed versions
   ```

### Option 3: Add an Alias

Add to `~/.bashrc` or `~/.zshrc`:

```bash
alias gvm='bash /path/to/install_go.sh'
```

Then use:
```bash
gvm              # Interactive mode
gvm -y           # Install latest silently
gvm --list       # List installed versions
```

## Examples

### Interactive Mode (Default)

When you run `./install_go.sh` without arguments, the script intelligently detects your current state and provides appropriate options:

**Scenario 1: No Go installed**
```
=== Go Version Manager ===

No Go installation detected.
Latest available: go1.23.1

Install go1.23.1? (y/n) y
Downloading Go 1.23.1 for amd64...
✓ Downloaded to /tmp/go1.23.1.linux-amd64.tar.gz
Extracting Go 1.23.1...
Installing to /usr/local/go-1.23.1...
✓ Installed Go 1.23.1 to /usr/local/go-1.23.1
Switching to Go 1.23.1...
✓ Switched to Go 1.23.1
go version go1.23.1 linux/amd64
```

**Scenario 2: Outdated version installed**
```
=== Go Version Manager ===

Current installation: 1.21.0
Location: /usr/local/go/bin/go
Latest available: go1.23.1
Installed versions: 1.21.0

Options:
  y - Upgrade to go1.23.1
  s - Switch to different installed version
  n - Cancel
Choice [y/s/n] y
```

**Scenario 3: Already on latest**
```
=== Go Version Manager ===

Current installation: 1.23.1 (latest)
No upgrade available.

Install additional version? (y/n) n
```

### Silent Mode

Perfect for automation and CI/CD:
```bash
./install_go.sh -y
```

Output:
```
Downloading Go 1.23.1 for amd64...
✓ Downloaded to /tmp/go1.23.1.linux-amd64.tar.gz
Extracting Go 1.23.1...
Installing to /usr/local/go-1.23.1...
✓ Installed Go 1.23.1 to /usr/local/go-1.23.1
Switching to Go 1.23.1...
✓ Switched to Go 1.23.1
```

### Install Specific Version

```bash
./install_go.sh -v 1.20.5
```

Output:
```
Downloading Go 1.20.5 for amd64...
✓ Downloaded to /tmp/go1.20.5.linux-amd64.tar.gz
Extracting Go 1.20.5...
Installing to /usr/local/go-1.20.5...
✓ Installed Go 1.20.5 to /usr/local/go-1.20.5
Switching to Go 1.20.5...
✓ Switched to Go 1.20.5
```

### List Installed Versions

```bash
./install_go.sh -l
```

Output:
```
Installed versions:
  * 1.23.1 (active)
    1.22.5
    1.20.5
Latest available: go1.23.1
```

### Cleanup Old Versions

Interactive cleanup:
```bash
./install_go.sh --cleanup
```

Output:
```
Installed versions:
  ✓ 1.23.1 (active)
    1.22.5
    1.21.0

Remove old versions? (all/specific/none/exit) specific
Select versions to remove (space-separated numbers):
  [0] 1.22.5
  [1] 1.21.0
Numbers: 0 1
  Removing 1.22.5...
  ✓ Removed 1.22.5
  Removing 1.21.0...
  ✓ Removed 1.21.0
```

Silent cleanup (remove all old versions):
```bash
./install_go.sh -y --cleanup
```

## Architecture

### Version Management

The script uses a symlink-based architecture for managing multiple Go versions:

- **Versioned Installations**: Each Go version is installed to `/usr/local/go-VERSION` (e.g., `/usr/local/go-1.23.1`)
- **Active Version**: A symlink at `/usr/local/go` points to the active version
- **Instant Switching**: Changing versions is as simple as updating the symlink
- **No Reinstallation Needed**: Switch between already-installed versions instantly

### Environment Configuration

The script automatically configures:

- **GOPATH**: Set to `$HOME/go` (standard location for Go projects)
- **GOBIN**: Set to `$GOPATH/bin` (where installed Go tools place binaries)
- **PATH**: Updated to include:
  - `/usr/local/go/bin` (Go compiler and standard tools)
  - `$GOBIN` (user-installed Go tools)

Profile files are updated based on your shell:
- Bash: `~/.bashrc`, `~/.bash_profile`, or `~/.profile`
- Zsh: `~/.zshrc`, `~/.zprofile`, or `~/.profile`
- Fish: `~/.config/fish/config.fish`

### Legacy Migration

If you have an existing Go installation at `/usr/local/go` (a regular directory, not a symlink), the script will:

1. Detect the legacy installation
2. Ask for confirmation (unless in silent mode)
3. Migrate it to `/usr/local/go-VERSION`
4. Create a symlink at `/usr/local/go` pointing to the versioned directory
5. Verify the migration succeeded

## Supported Architectures

- `amd64` (64-bit x86_64)
- `arm64` (64-bit ARM - Apple Silicon, ARM servers)
- `armv6l` (32-bit ARM - Raspberry Pi)

## Notes

- **sudo Required**: The script requires root privileges to install Go system-wide to `/usr/local/`
- **Idempotent**: Can be run multiple times safely
- **Safe Cleanup**: On installation failure, automatically cleans up partial installations and restores previous state
- **Disk Space**: Check available space before installation (requires ~2x the tarball size)
- **Session vs Permanent**: Environment variables are set for both the current session and future sessions via profile updates

## Contributing

If you find any issues or have suggestions for improvements, feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
