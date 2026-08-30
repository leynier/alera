import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows Whisper cargo env passes /FS to cl.exe', () {
    final cargokit = File('rust_builder/cargokit/cmake/cargokit.cmake')
        .readAsStringSync();
    final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();

    for (final source in <String>[cargokit, windowsCmake]) {
      expect(source, contains('"CFLAGS=/FS"'));
      expect(source, contains('"CXXFLAGS=/FS"'));
      expect(source, contains('"CL=/FS"'));
      expect(source, contains('"_CL_=/Z7 /FS"'));
      expect(source, contains('"CMAKE_GENERATOR=Ninja"'));
      expect(source, contains('CMAKE_GENERATOR_x86_64_pc_windows_msvc=Ninja'));
      expect(source, contains('"GGML_CCACHE=OFF"'));
    }
    expect(cargokit, contains('ALERA_CARGOKIT_TEMP_DIR'));
    expect(cargokit, contains(r'ALERA_CARGOKIT_TEMP_DIR}/n'));
    expect(cargokit, contains(r'SystemDrive}/c/n'));
    expect(cargokit, isNot(contains(r'/${CARGOKIT_LIB_NAME}')));
    expect(
      windowsCmake,
      contains(r'CARGO_TARGET_DIR=${ALERA_CLI_CARGO_TARGET_DIR}'),
    );
    expect(windowsCmake, contains(r'ALERA_CARGOKIT_TEMP_DIR}/cli'));
    expect(windowsCmake, contains('stage_alera_sidecar.cmake'));
    expect(windowsCmake, contains('ALERA_CLI_STAGED'));
    expect(windowsCmake, contains(r'install(PROGRAMS "${ALERA_CLI_STAGED}"'));
    expect(File('windows/stage_alera_sidecar.cmake').existsSync(), isTrue);
  });

  test('Windows native cargo target keeps vulkan TryCompile objects under MAX_PATH', () {
    // Source path from Warm CI 32543025980, plus CMake's inner
    // CMakeFiles/cmTC_XXXXXXXX.dir/testCCompiler.c.obj. cl.exe reports
    // C1083 with an empty generated-file name when this object exceeds
    // MAX_PATH. The previous test measured vc140.pdb with a short cmTC
    // id and accepted R:\c\alera_native, which still fails in CI.
    const nestedObj =
        r'x86_64-pc-windows-msvc\release\build\whisper-rs-sys-e163708acab93780\out\build\ggml\src\ggml-vulkan\vulkan-shaders-gen-prefix\src\vulkan-shaders-gen-build\CMakeFiles\CMakeScratch\TryCompile-v0i3yp\CMakeFiles\cmTC_12345678.dir\testCCompiler.c.obj';
    expect(
      r'R:\c\alera_native'.length + 1 + nestedObj.length,
      greaterThan(260),
    );
    expect(
      r'C:\c\alera_native'.length + 1 + nestedObj.length,
      greaterThan(260),
    );
    expect(r'R:\c\n'.length + 1 + nestedObj.length, lessThan(260));
    expect(r'C:\c\n'.length + 1 + nestedObj.length, lessThan(260));
    expect(r'R:\c\cli'.length + 1 + nestedObj.length, lessThan(260));

    final tune = File('.github/actions/tune-windows-build/action.yml')
        .readAsStringSync();
    expect(tune, contains(r"$scratchPath = 'R:\c'"));
    expect(tune, contains(r'R:\c\n'));
  });
}
