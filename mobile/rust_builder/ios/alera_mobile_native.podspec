Pod::Spec.new do |s|
  s.name             = 'alera_mobile_native'
  s.version          = '0.0.1'
  s.summary          = 'Native Whisper inference for Alera mobile.'
  s.description      = 'Builds the Alera mobile Whisper Rust library.'
  s.homepage         = 'https://github.com/leynier/alera'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Alera' => 'support@alera.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
  # Cargokit emits a static archive; its native dependencies must reach Xcode.
  s.libraries = 'c++'
  s.frameworks = 'Accelerate'

  s.script_phase = {
    :name => 'Build Rust library',
    # CocoaPods supplies a symlink path. Resolve it before traversing parents
    # so the shell does not interpret .. relative to .symlinks/plugins.
    :script => <<-'SCRIPT',
set -e
export PODS_TARGET_SRCROOT="$(cd "$PODS_TARGET_SRCROOT" && pwd -P)"
sh "$PODS_TARGET_SRCROOT/../../../rust_builder/cargokit/build_pod.sh" ../../../rust/alera-mobile-native alera_mobile_native
SCRIPT
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${BUILT_PRODUCTS_DIR}/libalera_mobile_native.a'],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libalera_mobile_native.a',
  }
end
