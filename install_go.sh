#!/bin/bash

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

# Function to install or update Go
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
  LATEST_GO_VERSION=$(curl -s $GO_DOWNLOAD_URL | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)

  # Check if the latest version was fetched successfully
  if [ -z "$LATEST_GO_VERSION" ]; then
    echo "Failed to fetch the latest Go version. Please check your internet connection."
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

  # Add Go to the PATH
  # This part needs to be handled carefully for root vs user
  echo "Adding Go to the PATH..."
  PROFILE_FILE=""
  if [ "$(id -u)" -ne 0 ]; then
    # For regular user, update their own .profile or .bashrc
    if [ -f "$HOME/.bashrc" ]; then
      PROFILE_FILE="$HOME/.bashrc"
    elif [ -f "$HOME/.profile" ]; then
      PROFILE_FILE="$HOME/.profile"
    else
      # Fallback if neither exists, create .profile
      PROFILE_FILE="$HOME/.profile"
      touch "$PROFILE_FILE"
    fi
    # Ensure the Go path is not already there to avoid duplicates
    if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" "$PROFILE_FILE"; then
      echo "export PATH=\$PATH:/usr/local/go/bin" >> "$PROFILE_FILE"
      echo "Go path added to $PROFILE_FILE. Please source it or log out and log back in."
    else
      echo "Go path already exists in $PROFILE_FILE."
    fi
    # For the current session (user)
    export PATH=$PATH:/usr/local/go/bin
  else
    # For root user, consider system-wide profile or /etc/profile.d/
    # For simplicity, we'll just set it for the current root session
    # and suggest manual addition for permanent system-wide effect if needed.
    export PATH=$PATH:/usr/local/go/bin
    echo "Go path set for the current root session."
    echo "For permanent system-wide effect for all users, consider adding '/usr/local/go/bin' to /etc/profile or creating a script in /etc/profile.d/"
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
