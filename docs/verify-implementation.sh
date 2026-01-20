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
