Pod::Spec.new do |spec|
  spec.name = 'alera_browser'
  spec.version = '0.1.0'
  spec.summary = 'Alera desktop browser engine boundary.'
  spec.description = <<-DESC
A fail-closed Flutter boundary for the system WKWebView engine.
                       DESC
  spec.homepage = 'https://github.com/leynier/alera'
  spec.license = { :file => '../LICENSE' }
  spec.author = { 'Leynier' => 'devnull@example.com' }
  spec.source = { :path => '.' }
  spec.source_files = 'Classes/**/*'
  spec.dependency 'FlutterMacOS'
  spec.frameworks = 'WebKit', 'Security', 'LocalAuthentication'
  spec.libraries = 'sqlite3'
  spec.platform = :osx, '14.0'
  spec.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  spec.swift_version = '5.0'

  spec.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/**/*.swift'
  end
end
