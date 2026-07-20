DART ?= dart
CARGO ?= cargo
FLUTTER ?= flutter
APP_DEVICE_ARG = $(if $(APP_DEVICE),--device "$(APP_DEVICE)",)
ALERA_FLAVOR ?= dev
ALERA_APP_ID ?= $(if $(filter release,$(ALERA_FLAVOR)),dev.leynier.alera,dev.leynier.alera.dev)
ALERA_CLI_BUNDLE_DIR ?= .dart_tool/alera
ALERA_CLI_DEBUG_TOKEN ?= dev-token
ALERA_HOST_EMPTY_SHUTDOWN_SECONDS ?= 30
ALERA_HOST_DETACHED_SHUTDOWN_SECONDS ?= 3600
ALERA_HOST_SCROLLBACK_BYTES ?= 10000000
PERF_SCENARIO ?= idle
PERF_DURATION_SECONDS ?= 30
PERF_APP_PID ?=
PERF_APP_PID_ARG = $(if $(PERF_APP_PID),--app-pid "$(PERF_APP_PID)",)
ALERA_DEBUG_TOOL = tool/debug/alera_debug.dart

.PHONY: help init-submodules update-submodules frb-generate rust-test cli-build cli-help host-debug app-debug app-profile app-debug-bundled-cli debug-processes host-stop perf-linux perf-macos-resources

# List available make targets.
help:
	$(DART) $(ALERA_DEBUG_TOOL) help

# Initialize all git submodules at their pinned commits.
init-submodules:
	git submodule update --init --recursive

# Update all git submodules to their latest remote commits.
update-submodules:
	git submodule update --init --recursive --remote --merge

# Regenerate flutter_rust_bridge bindings after changing the Rust API surface
# (rust/src/api). The generated Dart under lib/src/rust is committed.
frb-generate:
	flutter_rust_bridge_codegen generate

# Format, lint, and test the Rust workspace (alera_native + alera-cli). The
# `--workspace` flags are required because `rust/` has a root package, so a bare
# clippy/test would only cover `alera_native` and skip the `alera-cli` member.
rust-test:
	cd rust && "$(CARGO)" fmt --check && "$(CARGO)" clippy --workspace --all-targets -- -D warnings && "$(CARGO)" test --workspace

# Build the Rust alera CLI sidecar (cargo) used by desktop app launches.
cli-build:
	$(DART) $(ALERA_DEBUG_TOOL) cli-build --cargo "$(CARGO)" --bundle-dir "$(ALERA_CLI_BUNDLE_DIR)"

# Smoke-test the locally built Rust CLI sidecar.
cli-help:
	$(DART) $(ALERA_DEBUG_TOOL) cli-help --cargo "$(CARGO)" --bundle-dir "$(ALERA_CLI_BUNDLE_DIR)"

# Run the runtime host in the foreground for direct stdout/stderr debugging.
host-debug:
	$(DART) $(ALERA_DEBUG_TOOL) host-debug --app-id "$(ALERA_APP_ID)" --debug-token "$(ALERA_CLI_DEBUG_TOKEN)" --host-empty-shutdown-seconds "$(ALERA_HOST_EMPTY_SHUTDOWN_SECONDS)" --host-detached-shutdown-seconds "$(ALERA_HOST_DETACHED_SHUTDOWN_SECONDS)" --host-scrollback-bytes "$(ALERA_HOST_SCROLLBACK_BYTES)"

# Run the Flutter app with the normal development fallback for the CLI.
app-debug:
	$(DART) $(ALERA_DEBUG_TOOL) app-debug --flutter "$(FLUTTER)" $(APP_DEVICE_ARG) --alera-flavor "$(ALERA_FLAVOR)"

# Run a profile-mode desktop app with performance timeline marks enabled.
app-profile:
	$(DART) $(ALERA_DEBUG_TOOL) app-profile --flutter "$(FLUTTER)" $(APP_DEVICE_ARG) --alera-flavor "$(ALERA_FLAVOR)"

# Run the Flutter app against the locally compiled CLI bundle.
app-debug-bundled-cli:
	$(DART) $(ALERA_DEBUG_TOOL) app-debug-bundled-cli --flutter "$(FLUTTER)" $(APP_DEVICE_ARG) --alera-flavor "$(ALERA_FLAVOR)" --bundle-dir "$(ALERA_CLI_BUNDLE_DIR)"

# Inspect running Alera app and runtime-host processes.
debug-processes:
	$(DART) $(ALERA_DEBUG_TOOL) debug-processes --app-id "$(ALERA_APP_ID)"

# Stop the current debug terminal host for this app id.
host-stop:
	$(DART) $(ALERA_DEBUG_TOOL) host-stop --app-id "$(ALERA_APP_ID)"

# Capture startup and first-frame timings from a real Linux profile build.
perf-linux:
	$(DART) tool/performance/alera_performance.dart --flutter "$(FLUTTER)"

# Capture macOS CPU and RSS by app, host, tooling, terminal, and agent process.
perf-macos-resources:
	$(DART) tool/performance/alera_resource_profile.dart --scenario "$(PERF_SCENARIO)" --output ".dart_tool/performance/resources_$(PERF_SCENARIO).json" --duration-seconds "$(PERF_DURATION_SECONDS)" --interval-ms 250 $(PERF_APP_PID_ARG) --build-mode profile
