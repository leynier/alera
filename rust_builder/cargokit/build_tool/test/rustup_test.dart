import 'package:build_tool/src/rustup.dart';
import 'package:test/test.dart';

void main() {
  test('recognizes named and numeric official Rust toolchains', () {
    expect(
      <String>[
        'stable-x86_64-pc-windows-msvc (default)',
        'beta-aarch64-apple-darwin',
        'nightly-2026-08-11-x86_64-unknown-linux-gnu',
        '1.96-x86_64-pc-windows-msvc',
        '1.97.1-aarch64-apple-darwin',
      ].every(isOfficialRustupToolchain),
      isTrue,
    );
  });

  test('rejects linked custom Rust toolchains', () {
    expect(isOfficialRustupToolchain('alera-local'), isFalse);
    expect(isOfficialRustupToolchain('custom-stable'), isFalse);
  });
}
