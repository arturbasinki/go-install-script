# Go Installer Script

This repository contains a Bash script to automatically detect your system's architecture, fetch the latest version of Go, and install or update it on your Linux machine.

## Features

- Automatically detects system architecture (`amd64`, `arm64`, or `armv6l`).
- Downloads and installs the correct Go version for your system.
- Updates the `PATH` environment variable to include Go binaries.
- Verifies the installation by running `go version`.

## Prerequisites

- A Linux-based operating system.
- `curl` installed (usually pre-installed on most Linux distributions).
- `sudo` privileges (for installing Go system-wide).

## Usage

### Option 1: Run the Script Directly from GitHub

You can fetch and execute the script directly from GitHub using the following command:

```bash
curl -sSL https://raw.githubusercontent.com/arturbasinki/go-install-script/refs/heads/master/go_version.sh | bash
```

### Option 2: Clone the Repository and Run the Script Locally

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
   ./install_go.sh
   ```

### Option 3: Add an Alias for Easy Execution

You can add an alias to your shell configuration file (e.g., `~/.bashrc` or `~/.zshrc`) to make it easier to run the script in the future:

1. Open your shell configuration file:

   ```bash
   nano ~/.bashrc
   ```

2. Add the following line:

   ```bash
   alias install_go='curl -sSL https://raw.githubusercontent.com/arturbasinki/go-install-script/refs/heads/master/go_version.sh | bash'
   ```

3. Save the file and reload the configuration:

   ```bash
   source ~/.bashrc
   ```

4. Now you can install or update Go by simply running:
   ```bash
   install_go
   ```

## Example Output

For an `amd64` system:

```
Detected architecture: amd64
The latest Go version is: go1.21.0
Removing previous Go installation (if any)...
Downloading and installing Go version go1.21.0 for amd64...
Adding Go to the PATH...
Verifying the installation...
go version go1.21.0 linux/amd64
Go go1.21.0 has been successfully installed/updated!
```

For an `arm64` system:

```
Detected architecture: arm64
The latest Go version is: go1.21.0
Removing previous Go installation (if any)...
Downloading and installing Go version go1.21.0 for arm64...
Adding Go to the PATH...
Verifying the installation...
go version go1.21.0 linux/arm64
Go go1.21.0 has been successfully installed/updated!
```

## Supported Architectures

- `amd64` (64-bit x86)
- `arm64` (64-bit ARM)
- `armv6l` (32-bit ARM, e.g., Raspberry Pi)

## Notes

- The script requires `sudo` privileges to install Go system-wide.
- If Go is already installed, it will be updated to the latest version.
- The script updates the `PATH` in `~/.profile` and reloads it to ensure the changes take effect immediately.

## Contributing

If you find any issues or have suggestions for improvements, feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
