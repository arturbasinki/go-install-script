#!/bin/bash

# URL of the official Go downloads page
GO_DOWNLOAD_URL="https://go.dev/dl/"

# Fetch the latest Go version
LATEST_GO_VERSION=$(curl -s $GO_DOWNLOAD_URL | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)

# Check if the latest version was fetched successfully
if [ -z "$LATEST_GO_VERSION" ]; then
  echo "Failed to fetch the latest Go version. Please check your internet connection."
  exit 1
fi

echo "The latest Go version is: $LATEST_GO_VERSION"

# Define the download URL for the latest Go version
GO_TAR_FILE="${LATEST_GO_VERSION}.linux-amd64.tar.gz"
GO_DOWNLOAD_LINK="https://go.dev/dl/${GO_TAR_FILE}"

# Remove any previous Go installation
echo "Removing previous Go installation (if any)..."
sudo rm -rf /usr/local/go

# Download and extract the latest Go version
echo "Downloading and installing Go version $LATEST_GO_VERSION..."
curl -LO $GO_DOWNLOAD_LINK
sudo tar -C /usr/local -xzf $GO_TAR_FILE
rm $GO_TAR_FILE

# Add Go to the PATH
echo "Adding Go to the PATH..."
export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> $HOME/.profile
source $HOME/.profile

# Verify the installation
echo "Verifying the installation..."
go version

if [ $? -eq 0 ]; then
  echo "Go $LATEST_GO_VERSION has been successfully installed/updated!"
else
  echo "Installation failed. Please check the logs and try again."
  exit 1
fi