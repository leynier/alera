DART ?= dart
FLUTTER ?= flutter
APP_DEVICE ?= macos
ALERA_APP_ID ?= dev.leynier.alera
ALERA_CLI_BUNDLE_DIR ?= .dart_tool/alera
ALERA_CLI_DEBUG_PORT ?= 8181
ALERA_CLI_DEBUG_TOKEN ?= dev-token
ALERA_DEBUG_TOOL = tool/debug/alera_debug.dart

.PHONY: help update-refs cli-build cli-help host-debug host-debug-observe host-debug-wrapper app-debug app-debug-bundled-cli app-debug-host-observe debug-processes host-stop

# List available make targets.
help:
	$(DART) $(ALERA_DEBUG_TOOL) help

# Update all reference projects (git submodules) to their latest remote commits
update-refs:
	git submodule update --init --recursive --remote --merge

# Build the bundled Dart CLI sidecar used by desktop app launches.
cli-build:
	$(DART) $(ALERA_DEBUG_TOOL) cli-build --dart "$(DART)" --bundle-dir "$(ALERA_CLI_BUNDLE_DIR)"

# Smoke-test the locally built CLI sidecar.
cli-help:
	$(DART) $(ALERA_DEBUG_TOOL) cli-help --dart "$(DART)" --bundle-dir "$(ALERA_CLI_BUNDLE_DIR)"

# Run the terminal host in the foreground for direct stdout/stderr debugging.
host-debug:
	$(DART) $(ALERA_DEBUG_TOOL) host-debug --dart "$(DART)" --app-id "$(ALERA_APP_ID)" --debug-token "$(ALERA_CLI_DEBUG_TOKEN)"

# Run the foreground terminal host with a Dart VM service for debugger attach.
host-debug-observe:
	$(DART) $(ALERA_DEBUG_TOOL) host-debug-observe --dart "$(DART)" --app-id "$(ALERA_APP_ID)" --debug-port "$(ALERA_CLI_DEBUG_PORT)" --debug-token "$(ALERA_CLI_DEBUG_TOKEN)"

# Build a wrapper executable so the Flutter app launches the host with a Dart VM service.
host-debug-wrapper:
	$(DART) $(ALERA_DEBUG_TOOL) host-debug-wrapper --dart "$(DART)"

# Run the Flutter app with the normal development fallback for the CLI.
app-debug:
	$(DART) $(ALERA_DEBUG_TOOL) app-debug --flutter "$(FLUTTER)" --device "$(APP_DEVICE)"

# Run the Flutter app against the locally compiled CLI bundle.
app-debug-bundled-cli:
	$(DART) $(ALERA_DEBUG_TOOL) app-debug-bundled-cli --dart "$(DART)" --flutter "$(FLUTTER)" --device "$(APP_DEVICE)" --bundle-dir "$(ALERA_CLI_BUNDLE_DIR)"

# Run the Flutter app while forcing its launched terminal host to expose a VM service.
app-debug-host-observe:
	$(DART) $(ALERA_DEBUG_TOOL) app-debug-host-observe --dart "$(DART)" --flutter "$(FLUTTER)" --device "$(APP_DEVICE)" --debug-port "$(ALERA_CLI_DEBUG_PORT)"

# Inspect running Alera app and terminal-host processes.
debug-processes:
	$(DART) $(ALERA_DEBUG_TOOL) debug-processes --app-id "$(ALERA_APP_ID)"

# Stop the current debug terminal host for this app id.
host-stop:
	$(DART) $(ALERA_DEBUG_TOOL) host-stop --app-id "$(ALERA_APP_ID)"
