# Manual Testing Checklist

## Prerequisites
- Linux test system (can be VM)
- sudo access
- curl installed

## Test Scenarios

### Fresh Install (No Go)
- [ ] Run `./install_go.sh`
- [ ] Verify prompt shows latest version
- [ ] Accept installation
- [ ] Verify `/usr/local/go` is symlink
- [ ] Verify version directory exists: `/usr/local/go-X.Y.Z`
- [ ] Run `go version` - shows correct version
- [ ] Check `echo $GOPATH $GOBIN` - set correctly
- [ ] New shell session has Go in PATH

### Upgrade Existing Install
- [ ] Start with older Go version
- [ ] Run `./install_go.sh`
- [ ] Verify upgrade prompt appears
- [ ] Accept upgrade
- [ ] Verify both version directories exist
- [ ] Verify symlink points to new version
- [ ] Old version still available for switching

### Version Switching
- [ ] Install two different versions
- [ ] Run `./install_go.sh` → choose "s" for switch
- [ ] Select different version
- [ ] Verify symlink updated
- [ ] Run `go version` - shows switched version
- [ ] Use `--version X.Y.Z` flag
- [ ] Verify direct switch works

### Cleanup
- [ ] Install 3+ versions
- [ ] Run cleanup after install
- [ ] Test "all" option
- [ ] Test "specific" option
- [ ] Test "none" option
- [ ] Verify active version never removed
- [ ] Run `./install_go.sh -y --cleanup`
- [ ] Verify silent cleanup works

### Silent Mode
- [ ] Run `./install_go.sh -y`
- [ ] Verify no prompts appear
- [ ] Verify automatic install/upgrade
- [ ] Combine with `--version`
- [ ] Combine with `--cleanup`

### Legacy Migration
- [ ] Create legacy install at `/usr/local/go` (directory, not symlink)
- [ ] Run script
- [ ] Verify migration prompt appears
- [ ] Accept migration
- [ ] Verify renamed to `/usr/local/go-X.Y.Z`
- [ ] Verify symlink created
- [ ] Verify Go still works

### Error Handling
- [ ] Run without sudo - graceful error
- [ ] Try invalid version format - clear error
- [ ] Disconnect network - download fails gracefully
- [ ] Try switching to non-existent version - helpful error

## Architecture Tests
- [ ] amd64 (x86_64)
- [ ] arm64 (aarch64) if available
- [ ] armv6l if available
