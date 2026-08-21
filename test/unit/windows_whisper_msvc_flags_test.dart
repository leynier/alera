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
      expect(source, contains('"_CL_=/Z7 /FS"'));
      expect(source, contains('"CMAKE_GENERATOR=Ninja"'));
      expect(source, contains('CMAKE_GENERATOR_x86_64_pc_windows_msvc=Ninja'));
    }
    expect(cargokit, contains('ALERA_CARGOKIT_TEMP_DIR'));
    expect(cargokit, contains(r'SystemDrive}/c/${CARGOKIT_LIB_NAME}'));
    expect(
      windowsCmake,
      contains(r'CARGO_TARGET_DIR=${ALERA_CLI_CARGO_TARGET_DIR}'),
    );
  });

  test('Windows CI scratch prefix keeps ggml-vulkan PDBs under MAX_PATH', () {
    const nestedPdb =
        r'x86_64-pc-windows-msvc\release\build\whisper-rs-sys-e163708acab93780\out\build\ggml\src\ggml-vulkan\vulkan-shaders-gen-prefix\src\vulkan-shaders-gen-build\CMakeFiles\CMakeScratch\TryCompile-1fbhfa\CMakeFiles\cmTC_82bac.dir\vc140.pdb';
    expect(
      r'R:\alera-cargokit\alera_native'.length + 1 + nestedPdb.length,
      greaterThan(260),
    );
    expect(r'R:\c\alera_native'.length + 1 + nestedPdb.length, lessThan(260));
    expect(r'C:\c\alera_native'.length + 1 + nestedPdb.length, lessThan(260));

    final tune = File(
      '.github/actions/tune-windows-build/action.yml',
    ).readAsStringSync();
    expect(tune, contains(r"$scratchPath = 'R:\c'"));
  });
}
