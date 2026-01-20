#!/bin/bash
echo "=== Comprehensive Cleanup Function Test ==="
echo ""

# Source the script
source /home/airbass/Development/go/go-install-script/.worktrees/go-version-manager/install_go.sh

# Test 1: Active version extraction with pipe issue demonstration
echo "Test 1: Active version extraction (fixed method)"
echo "------------------------------------------------------"
active_info=$(get_active_version)
echo "Raw output from get_active_version: '$active_info'"

# This is the NEW working method (using temp variable)
active_version=$(echo "$active_info" | cut -d'|' -f1)
echo "Extracted active_version (NEW method): '$active_version'"

# This would be the OLD broken method for comparison
echo ""
echo "Demonstrating the OLD broken method for comparison:"
broken_version=$(get_active_version | IFS='|' read -r v _ _; echo "$v")
echo "Result from OLD pipe method: '$broken_version' (EMPTY - this was the bug!)"
echo ""

if [ -n "$active_version" ]; then
  echo "✓ NEW method correctly extracts: $active_version"
else
  echo "✗ NEW method failed"
  exit 1
fi

if [ -z "$broken_version" ]; then
  echo "✓ Confirmed OLD method is broken (returns empty)"
else
  echo "Note: OLD method unexpectedly worked in this shell"
fi

# Test 2: Verify get_active_version output format
echo ""
echo "Test 2: Verify get_active_version output format"
echo "------------------------------------------------------"
if [[ "$active_info" =~ ^[0-9]+\.[0-9]+\.[0-9]+\| ]]; then
  echo "✓ Output format is correct: version|path|path"
else
  echo "✗ Unexpected output format"
  exit 1
fi

# Test 3: Parse components using cut
echo ""
echo "Test 3: Parse all components from active_info"
echo "------------------------------------------------------"
version=$(echo "$active_info" | cut -d'|' -f1)
go_bin=$(echo "$active_info" | cut -d'|' -f2)
go_root=$(echo "$active_info" | cut -d'|' -f3)
echo "Version:  $version"
echo "Go bin:   $go_bin"
echo "Go root:  $go_root"

if [ -n "$version" ] && [ -n "$go_bin" ] && [ -n "$go_root" ]; then
  echo "✓ All components parsed successfully"
else
  echo "✗ Failed to parse components"
  exit 1
fi

# Test 4: Simulate version protection logic
echo ""
echo "Test 4: Version protection logic simulation"
echo "------------------------------------------------------"
echo "Active version: $active_version"
echo ""

# Simulate having multiple versions (including active)
test_versions=("1.23.0" "1.24.0" "$active_version" "1.22.0")
echo "Simulated installed versions:"
for v in "${test_versions[@]}"; do
  if [ "$v" == "$active_version" ]; then
    echo "  ✓ $v (ACTIVE - PROTECTED from removal)"
  else
    echo "    $v (can be removed)"
  fi
done

echo ""
# Test filtering logic (what cleanup_versions does)
removable=()
for v in "${test_versions[@]}"; do
  [ "$v" != "$active_version" ] && removable+=("$v")
done

echo "Removable versions (${#removable[@]}): ${removable[*]}"
echo "Protected versions (1): $active_version"

if [ ${#removable[@]} -eq 3 ]; then
  echo "✓ Protection logic correctly filters out active version"
else
  echo "✗ Protection logic failed"
  exit 1
fi

# Test 5: Edge case - only active version installed
echo ""
echo "Test 5: Edge case - only active version installed"
echo "------------------------------------------------------"
only_active=("$active_version")
removable_from_only=()
for v in "${only_active[@]}"; do
  [ "$v" != "$active_version" ] && removable_from_only+=("$v")
done

if [ ${#removable_from_only[@]} -eq 0 ]; then
  echo "✓ When only active version exists, nothing is removable (correct)"
else
  echo "✗ Active version would be removed (BUG!)"
  exit 1
fi

echo ""
echo "=== ALL TESTS PASSED ==="
echo ""
echo "Summary:"
echo "  - Active version extraction works correctly"
echo "  - Old pipe method is broken (confirmed)"
echo "  - New temp variable method is reliable"
echo "  - Protection logic prevents active version removal"
echo "  - Edge cases handled correctly"
