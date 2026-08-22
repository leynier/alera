#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint alera_native.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'alera_native'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # First argument is relative path to the `rust` folder, second is name of rust library
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../rust alera_native',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    # Let XCode know that the static library referenced in -force_load below is
    # created by this build step.
    :output_files => ["${BUILT_PRODUCTS_DIR}/libalera_native.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # Cargokit only produces the Rust static library, so native dependencies
    # used inside it must be repeated when CocoaPods links the plugin framework.
    # libgit2 needs zlib/iconv, while whisper.cpp needs libc++, Accelerate,
    # Foundation, Core ML, Metal, and MetalKit. Cargokit only produces the
    # Rust static library, so these framework dependencies must be repeated
    # when CocoaPods links the plugin framework.
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libalera_native.a -lz -liconv -lc++ -framework Accelerate -framework Foundation -framework CoreML -framework Metal -framework MetalKit',
  }
end
