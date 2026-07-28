import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/native_helpers/native_helper_manifest.dart';
import '../../tool/native_helpers/native_helper_materializer.dart';
import '../../tool/native_helpers/video_runtime_verifier.dart';

void main() {
  group('native helper manifest', () {
    test('pins the V1 helper versions, hashes, paths, and platforms', () {
      final manifest = NativeHelperManifest.read(
        File('tool/native_helpers/native_helper_assets.json'),
      );
      final byId = <String, NativeHelperAsset>{
        for (final asset in manifest.assets) asset.id: asset,
      };

      expect(byId.keys, containsAll(<String>['scrcpy-server', 'serve-sim']));
      expect(byId['scrcpy-server']!.version, '4.0');
      expect(
        byId['scrcpy-server']!.sourceSha256,
        '84924bd564a1eb6089c872c7521f968058977f91f5ff02514a8c74aff3210f3a',
      );
      expect(
        byId['scrcpy-server']!.relativePath,
        'android/scrcpy/4.0/scrcpy-server',
      );
      expect(byId['scrcpy-server']!.platforms, supportedNativeHelperPlatforms);
      expect(byId['serve-sim']!.version, '0.1.40');
      expect(
        byId['serve-sim']!.sourceSha256,
        '48f443481deefd4ea2a378950a19c5d160e49c0b7cb365a40eff746777d3fe2f',
      );
      expect(byId['serve-sim']!.payloadSha256, isNull);
      expect(
        byId['serve-sim']!.relativePath,
        'ios/serve-sim/0.1.40/serve-sim-bin',
      );
      expect(byId['serve-sim']!.platforms, <String>{'macos'});
      expect(byId['serve-sim']!.archiveMember, isNull);
      expect(byId['serve-sim']!.executable, isTrue);

      final derivation = byId['serve-sim']!.derivation!;
      expect(
        derivation.patchSha256,
        '05d9e9eb8f0b7319a35455a1e08fe1f88d9f4409a6c1baab38dc1950d3044e05',
      );
      expect(
        derivation.dependencyLockSha256,
        'ba95ccfd76f628fcf173102770f9e2fbeee0320823b9f1b508a0b8ff51f890ca',
      );
      expect(derivation.architectures, <String>['arm64', 'x86_64']);
      expect(derivation.dependencies, hasLength(1));
      expect(
        derivation.dependencies.single.sourceSha256,
        'e80a41ebba308359ab875925c06e38adfbd6d56d8de3a25a9d1839b6178a85da',
      );
      expect(
        derivation.dependencies.single.sourceCommit,
        '9483a5d459b45c3ffd059f7b55f9638e268632fd',
      );
      expect(
        derivation.dependencies.single.licensePath,
        'licenses/swifter-BSD-3-Clause.txt',
      );

      final patch = File(derivation.patchPath);
      expect(
        sha256.convert(patch.readAsBytesSync()).toString(),
        derivation.patchSha256,
      );
      final patchText = patch.readAsStringSync();
      expect(patchText, contains('server.listenAddressIPv6 = "::1"'));
      expect(patchText, contains('.package(path: "../swifter")'));
      final loopbackVerifier = File(
        'tool/native_helpers/verify_serve_sim_loopback.dart',
      ).readAsStringSync();
      expect(loopbackVerifier, contains("contains('[::1]:\$port')"));
      expect(loopbackVerifier, contains('InternetAddress.loopbackIPv4'));
      expect(loopbackVerifier, contains('_discoverLanAddresses()'));
      final notice = File(
        'third_party/native_helpers/NOTICE.md',
      ).readAsStringSync();
      expect(notice, contains('derived from the source revision'));
      expect(notice, contains('IPv6 loopback'));
      expect(notice, contains('Swifter'));

      final rawManifest =
          jsonDecode(
                File(
                  'tool/native_helpers/native_helper_assets.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final rawServeSim = (rawManifest['assets']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((asset) => asset['id'] == 'serve-sim');
      final upstream = rawServeSim['upstreamArtifact']! as Map<String, Object?>;
      expect(
        upstream['sourceSha256'],
        '8ecc93dd74223b51faf28783b5b697775b5f53853a4310fdf8e40b646400bdf0',
      );
      expect(
        upstream['payloadSha256'],
        '1257a9ed5e4bc300d9da7318a226e7bee7b9eaa7038716349a492b59cb1d1cc3',
      );
    });

    test('rejects paths that escape the bundle', () {
      final temp = Directory.systemTemp.createTempSync(
        'alera-native-helper-manifest-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final manifest = File(p.join(temp.path, 'manifest.json'))
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'noticeDirectory': '../outside',
            'assets': <Object?>[],
          }),
        );

      expect(
        () => NativeHelperManifest.read(manifest),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test(
    'materializes, verifies, and reuses a hash-pinned cache offline',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'alera-native-helpers-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final repository = Directory(p.join(temp.path, 'repository'))
        ..createSync(recursive: true);
      final notices = Directory(p.join(repository.path, 'notices', 'licenses'))
        ..createSync(recursive: true);
      File(
        p.join(repository.path, 'notices', 'NOTICE.md'),
      ).writeAsStringSync('Test notices.\n');
      File(
        p.join(notices.path, 'Apache-2.0.txt'),
      ).writeAsStringSync('Test license.\n');

      final directPayload = utf8.encode('scrcpy payload');
      final archivedPayload = utf8.encode('serve-sim payload');
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes('package/bin/serve-sim-bin', archivedPayload),
        );
      final archiveSource = const GZipEncoder().encodeBytes(
        TarEncoder().encodeBytes(archive),
      );
      final sources = <Uri, List<int>>{
        Uri.parse('https://example.invalid/scrcpy'): directPayload,
        Uri.parse('https://example.invalid/serve-sim.tgz'): archiveSource,
      };
      final manifestFile = File(p.join(repository.path, 'manifest.json'))
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'noticeDirectory': 'notices',
            'assets': <Object?>[
              _assetJson(
                id: 'scrcpy-server',
                version: '4.0',
                sourceUrl: 'https://example.invalid/scrcpy',
                sourceBytes: directPayload,
                payloadBytes: directPayload,
                relativePath: 'android/scrcpy/4.0/scrcpy-server',
              ),
              _assetJson(
                id: 'serve-sim',
                version: '0.1.40',
                sourceUrl: 'https://example.invalid/serve-sim.tgz',
                sourceBytes: archiveSource,
                payloadBytes: archivedPayload,
                relativePath: 'ios/serve-sim/0.1.40/serve-sim-bin',
                archiveMember: 'package/bin/serve-sim-bin',
                executable: true,
              ),
            ],
          }),
        );
      final manifest = NativeHelperManifest.read(manifestFile);
      var downloads = 0;
      final materializer = NativeHelperMaterializer(
        repositoryRoot: repository,
        manifest: manifest,
        downloader: (source, output) async {
          downloads += 1;
          await output.writeAsBytes(sources[source]!, flush: true);
        },
      );
      final output = Directory(p.join(temp.path, 'prepared'));
      final cache = Directory(p.join(temp.path, 'cache'));

      await materializer.prepare(
        platform: 'macos',
        output: output,
        cache: cache,
      );
      await verifyNativeHelperBundle(
        platform: 'macos',
        emulatorRoot: output,
        expected: manifest,
      );
      expect(downloads, 2);
      expect(
        File(
          p.join(output.path, 'android', 'scrcpy', '4.0', 'scrcpy-server'),
        ).readAsBytesSync(),
        directPayload,
      );
      final serveSim = File(
        p.join(output.path, 'ios', 'serve-sim', '0.1.40', 'serve-sim-bin'),
      );
      expect(serveSim.readAsBytesSync(), archivedPayload);
      if (!Platform.isWindows) {
        expect(serveSim.statSync().mode & 0x49, isNot(0));
      }

      await materializer.prepare(
        platform: 'macos',
        output: output,
        cache: cache,
        offline: true,
      );
      expect(downloads, 2);

      serveSim.writeAsStringSync('tampered');
      await expectLater(
        verifyNativeHelperBundle(
          platform: 'macos',
          emulatorRoot: output,
          expected: manifest,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('resolves installed helper roots for every desktop bundle layout', () {
    final temp = Directory.systemTemp.createTempSync(
      'alera-native-helper-roots-',
    );
    addTearDown(() => temp.deleteSync(recursive: true));
    Directory(p.join(temp.path, 'Alera.app')).createSync();

    expect(
      nativeHelperRootForBundle(platform: 'linux', bundle: temp).path,
      p.join(temp.path, 'resources', 'alera', 'emulator'),
    );
    expect(
      nativeHelperRootForBundle(platform: 'windows', bundle: temp).path,
      p.join(temp.path, 'resources', 'alera', 'emulator'),
    );
    expect(
      nativeHelperRootForBundle(platform: 'macos', bundle: temp).path,
      p.join(
        temp.path,
        'Alera.app',
        'Contents',
        'Resources',
        'alera',
        'emulator',
      ),
    );
  });

  group('video runtime packaging', () {
    test('pins non-GPL media runtimes and platform build dependencies', () {
      final manifest =
          jsonDecode(
                File(
                  'tool/native_helpers/video_runtime_assets.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final macos = manifest['macos']! as Map<String, Object?>;
      final windows = manifest['windows']! as Map<String, Object?>;

      expect(macos['flavor'], 'video-default');
      expect(macos['gplEnabled'], isFalse);
      expect(
        macos['sourceSha256'],
        '84d2ad98e046e82c6dc34d8547d76c2afeaee89c0f53032773be8985c95536d6',
      );
      expect(windows['gplEnabled'], isFalse);
      final windowsFiles = (windows['requiredFiles']! as List)
          .cast<Map<String, Object?>>();
      expect(
        windowsFiles.singleWhere(
          (file) => file['relativePath'] == 'libmpv-2.dll',
        )['sha256'],
        'd5f0694b08c124e785d858d00082f3e3b158dd9138bfc48c0382bf1eb443a5fc',
      );

      final linuxCmake = File('linux/CMakeLists.txt').readAsStringSync();
      expect(
        linuxCmake,
        contains('set(MIMALLOC_USE_STATIC_LIBS OFF CACHE BOOL'),
      );
      final setup = File(
        '.github/actions/setup-flutter-workspace/action.yml',
      ).readAsStringSync();
      expect(setup, contains('libepoxy-dev libmpv-dev'));
      final linuxPackage = File(
        'tool/release/package_linux.sh',
      ).readAsStringSync();
      expect(linuxPackage, contains('libmpv2'));
      expect(linuxPackage, contains('mpv-libs'));
    });

    test('verifies hash-pinned Windows video files', () async {
      final temp = await Directory.systemTemp.createTemp(
        'alera-video-runtime-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final payload = utf8.encode('video runtime');
      File(p.join(temp.path, 'libmpv-2.dll')).writeAsBytesSync(payload);
      final manifest = File(p.join(temp.path, 'video.json'))
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            'schemaVersion': 1,
            'dartPackages': <String, Object?>{'media_kit': '1.2.6'},
            'windows': <String, Object?>{
              'gplEnabled': false,
              'sources': <Object?>[
                <String, Object?>{
                  'url': 'https://example.invalid/libmpv',
                  'sha256': List<String>.filled(64, '1').join(),
                },
                <String, Object?>{
                  'url': 'https://example.invalid/angle',
                  'sha256': List<String>.filled(64, '2').join(),
                },
              ],
              'requiredFiles': <Object?>[
                <String, Object?>{
                  'relativePath': 'libmpv-2.dll',
                  'sha256': sha256.convert(payload).toString(),
                },
              ],
            },
          }),
        );

      await verifyVideoRuntimeBundle(
        platform: 'windows',
        bundle: temp,
        manifestFile: manifest,
      );

      File(p.join(temp.path, 'libmpv-2.dll')).writeAsStringSync('tampered');
      await expectLater(
        verifyVideoRuntimeBundle(
          platform: 'windows',
          bundle: temp,
          manifestFile: manifest,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  test(
    'desktop build and release hooks install and verify native runtimes',
    () {
      final linux = File('linux/CMakeLists.txt').readAsStringSync();
      final windows = File('windows/CMakeLists.txt').readAsStringSync();
      final macos = File(
        'macos/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      for (final buildFile in <String>[linux, windows]) {
        expect(
          buildFile,
          contains('tool/native_helpers/prepare_native_helpers.dart'),
        );
        expect(buildFile, contains('resources/alera/emulator'));
        final fallbackReset = buildFile.indexOf(
          'unset(ALERA_DART_EXECUTABLE CACHE)',
        );
        final fallbackLookup = buildFile.indexOf(
          'find_program(ALERA_DART_EXECUTABLE',
        );
        expect(fallbackReset, greaterThanOrEqualTo(0));
        expect(fallbackLookup, greaterThan(fallbackReset));
      }
      expect(
        macos,
        contains('tool/native_helpers/prepare_native_helpers.dart'),
      );
      expect(macos, contains(r'$OUTPUT_DIR/emulator'));

      final desktopBuild = File(
        '.github/workflows/desktop-build.yml',
      ).readAsStringSync();
      final release = File(
        '.github/workflows/release-cut.yml',
      ).readAsStringSync();
      expect(desktopBuild, contains('verify_desktop_runtime_bundle.dart'));
      expect(release, contains('verify_desktop_runtime_bundle.dart'));
      expect(
        release,
        contains('tool/native_helpers/verify_native_helper_bundle.dart'),
      );
      expect(release, contains(r'cp -R "$helper_dir" "$package_dir/emulator"'));
      expect(release, contains('"emulatorHelpers": "emulator/manifest.json"'));

      final macosSigning = File(
        'tool/release/sign_macos.sh',
      ).readAsStringSync();
      expect(macosSigning, contains('-name "*.framework"'));
      expect(macosSigning, isNot(contains('codesign --force --deep')));
      expect(macosSigning, contains('codesign --verify --strict --deep'));
    },
  );

  test(
    'canonical local CLI builds stage native helpers beside the sidecar',
    () {
      final debugContext = File(
        'tool/debug/alera_debug_context.dart',
      ).readAsStringSync();

      expect(
        debugContext,
        contains('tool/native_helpers/prepare_native_helpers.dart'),
      );
      expect(debugContext, contains("_join(destinationDir.path, 'emulator')"));
      final helperPreparation = debugContext.indexOf(
        'await _prepareCliNativeHelpers(destinationDir)',
      );
      final sidecarCopy = debugContext.indexOf(
        'await source.copy(destination.path)',
      );
      expect(helperPreparation, greaterThanOrEqualTo(0));
      expect(sidecarCopy, greaterThan(helperPreparation));
      expect(
        debugContext,
        contains('final helperExit = await _prepareCliNativeHelpers'),
      );
      expect(debugContext, contains('final buildExit = await buildCli();'));
      expect(
        debugContext,
        contains(
          'final buildExit = await buildCli(outputDir: buildOutputDir);',
        ),
      );
    },
  );
}

Map<String, Object?> _assetJson({
  required String id,
  required String version,
  required String sourceUrl,
  required List<int> sourceBytes,
  required List<int> payloadBytes,
  required String relativePath,
  String? archiveMember,
  bool executable = false,
}) {
  return <String, Object?>{
    'id': id,
    'version': version,
    'platforms': <String>['macos'],
    'sourceUrl': sourceUrl,
    'sourceSha256': sha256.convert(sourceBytes).toString(),
    'sourceCommit': '0123456789abcdef0123456789abcdef01234567',
    'payloadSha256': sha256.convert(payloadBytes).toString(),
    'relativePath': relativePath,
    'archiveMember': archiveMember,
    'executable': executable,
    'license': 'Apache-2.0',
    'licensePath': 'licenses/Apache-2.0.txt',
  };
}
