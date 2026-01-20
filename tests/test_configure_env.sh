#!/bin/bash

# Test script for configure_environment() function
# This script tests the profile detection and environment configuration

echo "======================================"
echo "Testing configure_environment()"
echo "======================================"
echo ""

# Source the main script to load functions
echo "1. Sourcing install_go.sh..."
source /home/airbass/Development/go/go-install-script/.worktrees/go-version-manager/install_go.sh

echo "✓ Script loaded successfully"
echo ""

# Test profile file detection
echo "2. Testing detect_profile_file()..."
PROFILE=$(detect_profile_file)
echo "   Detected profile: $PROFILE"

if [ -f "$PROFILE" ]; then
    echo "   ✓ Profile file exists"
else
    echo "   ⚠ Profile file does not exist (will be created)"
fi

echo ""

# Test environment configuration
echo "3. Testing configure_environment()..."
configure_environment

echo ""
echo "4. Verifying exports in profile ($PROFILE)..."
echo "   Recent Go-related entries:"

# Show the last 5 Go-related exports
grep -E "(GOPATH|GOBIN|PATH.*go)" "$PROFILE" 2>/dev/null | tail -5 || echo "   (No exports found yet)"

echo ""
echo "5. Current session environment variables:"
echo "   GOPATH: ${GOPATH:-<not set>}"
echo "   GOBIN: ${GOBIN:-<not set>}"

if echo "$PATH" | grep -q "/usr/local/go/bin"; then
    echo "   ✓ PATH contains /usr/local/go/bin"
else
    echo "   ✗ PATH does NOT contain /usr/local/go/bin"
fi

if echo "$PATH" | grep -q "$GOBIN"; then
    echo "   ✓ PATH contains GOBIN"
else
    echo "   ✗ PATH does NOT contain GOBIN"
fi

echo ""
echo "6. Verifying go command availability:"
if command -v go &>/dev/null; then
    echo "   ✓ go command found in PATH"
    go version
elif [ -x "/usr/local/go/bin/go" ]; then
    echo "   ✓ go binary exists at /usr/local/go/bin/go"
    /usr/local/go/bin/go version
else
    echo "   ⚠ go command not found"
fi

echo ""
echo "======================================"
echo "Test completed"
echo "======================================"
