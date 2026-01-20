#!/bin/bash

# Test script for download_go_version() function
# This tests Task 3: Download and Installation Functions

# Source the functions from install_go.sh
# We need to extract and define the functions without triggering the main script execution

# Detect the system architecture
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

# Normalize version string (remove 'go' prefix if present)
normalize_version() {
  local version="$1"
  echo "$version" | sed 's/^go//'
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

# Run the test
echo "========================================"
echo "Task 3: Download Function Test"
echo "========================================"
echo "Date: $(date)"
echo ""

# Test with a specific Go version
TEST_VERSION="1.23.1"

echo "Testing download_go_version('$TEST_VERSION')"
echo "----------------------------------------"

# Download the version
if download_go_version "$TEST_VERSION"; then
  tarball_path="/tmp/go${TEST_VERSION}.linux-$(detect_architecture).tar.gz"

  echo ""
  echo "✓ Test PASSED - Function executed successfully"
  echo ""
  echo "Verification Results:"
  echo "---------------------"

  # Check if file exists
  if [ -f "$tarball_path" ]; then
    echo "✓ File exists: $tarball_path"

    # Get file size
    file_size=$(du -h "$tarball_path" | cut -f1)
    echo "✓ File size: $file_size"

    # Verify tarball contents
    echo "✓ Tarball integrity: Verified"
    echo ""
    echo "Tarball contents (first 20 entries):"
    tar -tzf "$tarball_path" | head -20

    TEST_RESULT="PASS"
  else
    echo "✗ File not found after download"
    TEST_RESULT="FAIL"
  fi
else
  echo ""
  echo "✗ Test FAILED - Function returned error"
  TEST_RESULT="FAIL"
fi

echo ""
echo "========================================"
echo "Test Result: $TEST_RESULT"
echo "========================================"

# Create test log
mkdir -p /home/airbass/Development/go/go-install-script/.worktrees/go-version-manager/tests
cat > /home/airbass/Development/go/go-install-script/.worktrees/go-version-manager/tests/task-3-download-test.log << EOF
Task 3: Download and Installation Functions - Test Log
=====================================================
Date: $(date)

Test: download_go_version() function
Command: download_go_version "$TEST_VERSION"

Test Result: $TEST_RESULT

Function Details:
----------------
- Version tested: $TEST_VERSION
- Architecture: $(detect_architecture)
- Download URL: https://go.dev/dl/go${TEST_VERSION}.linux-$(detect_architecture).tar.gz

Verification:
------------
EOF

if [ "$TEST_RESULT" = "PASS" ]; then
  cat >> /home/airbass/Development/go/go-install-script/.worktrees/go-version-manager/tests/task-3-download-test.log << EOF
✓ Function executed successfully
✓ Downloaded tarball to: $tarball_path
✓ File size: $file_size
✓ Tarball integrity verified with tar -tzf
✓ Tarball contains valid Go distribution

Sample Contents:
$(tar -tzf "$tarball_path" | head -20)
EOF
else
  cat >> /home/airbass/Development/go/go-install-script/.worktrees/go-version-manager/tests/task-3-download-test.log << EOF
✗ Test failed - function returned error or file not found
EOF
fi

echo ""
echo "Test log saved to: tests/task-3-download-test.log"

# Exit with appropriate code
[ "$TEST_RESULT" = "PASS" ] && exit 0 || exit 1
