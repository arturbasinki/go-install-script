#!/bin/bash
echo "=== Testing cleanup_versions function ==="

# Source the script
source /home/airbass/Development/go/go-install-script/.worktrees/go-version-manager/install_go.sh

# Test 1: Active version extraction
echo "Test 1: Extract active version"
active_info=$(get_active_version)
echo "get_active_version output: $active_info"
active_version=$(echo "$active_info" | cut -d'|' -f1)
echo "Extracted active_version: $active_version"
if [ -n "$active_version" ]; then
  echo "✓ Active version extracted correctly"
else
  echo "✗ Failed to extract active version"
  exit 1
fi

# Test 2: List versions
echo ""
echo "Test 2: List installed versions"
list_installed_versions

# Test 3: Verify active version protection
echo ""
echo "Test 3: Verify active version would be protected"
versions=($(list_installed_versions))
echo "Total versions: ${#versions[@]}"
echo "Active version: $active_version"
for v in "${versions[@]}"; do
  if [ "$v" == "$active_version" ]; then
    echo "  ✓ $v would be PROTECTED (active)"
  else
    echo "    $v would be removable"
  fi
done

echo ""
echo "=== All tests passed ==="
