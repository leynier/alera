import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows Whisper cargo env passes /FS to cl.exe', () {
    final cargokit = File(
      'rust_builder/cargokit/cmake/cargokit.cmake',
    ).readAsStringSync();
    final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();

    for (final source in <String>[cargokit, windowsCmake]) {
      expect(source, contains('"CFLAGS=/FS"'));
      expect(source, contains('"CXXFLAGS=/FS"'));
      expect(source, contains('"CL=/FS"'));
      expect(source, contains('CMAKE_GENERATOR_x86_64_pc_windows_msvc=Ninja'));
    }
    expect(cargokit, contains('ALERA_CARGOKIT_TEMP_DIR'));
  });
}
