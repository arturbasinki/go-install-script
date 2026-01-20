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

  # Add Go to the PATH and set GOPATH/GOBIN
  # This part needs to be handled carefully for root vs user
  echo "Setting up Go environment..."
  if [ "$(id -u)" -ne 0 ]; then
    # For regular user, detect and update their profile file
    PROFILE_FILE=$(detect_profile_file)
    # Create profile file if it doesn't exist
    if [ ! -f "$PROFILE_FILE" ]; then
      touch "$PROFILE_FILE"
    fi
    
    # Set GOPATH to standard location
    GOPATH_LINE="export GOPATH=\$HOME/go"
    if ! grep -q "$GOPATH_LINE" "$PROFILE_FILE"; then
      echo "$GOPATH_LINE" >> "$PROFILE_FILE"
      echo "GOPATH set to \$HOME/go in $PROFILE_FILE"
    else
      echo "GOPATH already set in $PROFILE_FILE"
    fi
    
    # Set GOBIN to GOPATH/bin
    GOBIN_LINE="export GOBIN=\$GOPATH/bin"
    if ! grep -q "$GOBIN_LINE" "$PROFILE_FILE"; then
      echo "$GOBIN_LINE" >> "$PROFILE_FILE"
      echo "GOBIN set to \$GOPATH/bin in $PROFILE_FILE"
    else
      echo "GOBIN already set in $PROFILE_FILE"
    fi
    
    # Add Go binary directory to PATH
    GO_PATH_LINE="export PATH=\$PATH:/usr/local/go/bin"
    if ! grep -q "$GO_PATH_LINE" "$PROFILE_FILE"; then
      echo "$GO_PATH_LINE" >> "$PROFILE_FILE"
      echo "Go binary path added to PATH in $PROFILE_FILE"
    else
      echo "Go binary path already exists in PATH in $PROFILE_FILE"
    fi
    
    # Add GOBIN to PATH so installed binaries are recognized as commands
    GOBIN_PATH_LINE="export PATH=\$PATH:\$GOBIN"
    if ! grep -q "$GOBIN_PATH_LINE" "$PROFILE_FILE"; then
      echo "$GOBIN_PATH_LINE" >> "$PROFILE_FILE"
      echo "GOBIN added to PATH in $PROFILE_FILE. Please source it or log out and log back in."
    else
      echo "GOBIN already exists in PATH in $PROFILE_FILE."
    fi
    
    # For the current session (user)
    export GOPATH=$HOME/go
    export GOBIN=$GOPATH/bin
    export PATH=$PATH:/usr/local/go/bin:$GOBIN
  else
    # For root user, consider system-wide profile or /etc/profile.d/
    # For simplicity, we'll just set it for the current root session
    # and suggest manual addition for permanent system-wide effect if needed.
    export GOPATH=$HOME/go
    export GOBIN=$GOPATH/bin
    export PATH=$PATH:/usr/local/go/bin:$GOBIN
    echo "Go environment set for the current root session."
    echo "GOPATH set to \$HOME/go"
    echo "GOBIN set to \$GOPATH/bin"
    echo "For permanent system-wide effect for all users, consider adding these environment variables to /etc/profile or creating a script in /etc/profile.d/"
  fi


  # Verify the installation
  echo "Verifying the installation..."
  # Check if go binary exists and is executable
  if [ ! -x "/usr/local/go/bin/go" ]; then
      echo "Go binary not found or not executable at /usr/local/go/bin/go."
      # Attempt to source profile if it was just modified for the user
      if [ -n "$PROFILE_FILE" ] && [ -f "$PROFILE_FILE" ]; then
          echo "Attempting to source $PROFILE_FILE..."
          shellcheck source "$PROFILE_FILE"
      fi
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

# Call the function to execute the installation
install_latest_go
