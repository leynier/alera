part of 'codex_runtime_home_service_test.dart';

void _registerCodexRuntimeHomeServiceAdvancedTests() {
  test('removes mirrored auth when system auth disappears', () async {
    final systemAuth = File(p.join(home.path, '.codex', 'auth.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{"token":"system"}\n');

    final preparation = await service.prepareForTerminalLaunch();
    final runtimeAuth = File(p.join(preparation.runtimeHomePath, 'auth.json'));

    expect(runtimeAuth.existsSync(), isTrue);
    expect(runtimeAuth.readAsStringSync(), systemAuth.readAsStringSync());

    systemAuth.deleteSync();
    await service.prepareForTerminalLaunch();

    expect(
      FileSystemEntity.typeSync(runtimeAuth.path, followLinks: false),
      FileSystemEntityType.notFound,
    );
  });

  test('mirrors trusted user hook state into the runtime config', () async {
    final systemHooksPath = p.join(home.path, '.codex', 'hooks.json');
    const userCommand = 'echo trusted-user-hook';
    _writeJson(systemHooksPath, <String, Object?>{
      'hooks': <String, Object?>{
        'PreToolUse': <Object?>[_userHook(userCommand)],
      },
    });
    final canonicalSystemHooksPath = File(
      systemHooksPath,
    ).resolveSymbolicLinksSync();
    final systemTrustKey = '$canonicalSystemHooksPath:pre_tool_use:0:0';
    final systemTrustedHash = computeCodexTrustedHashForTesting(
      sourcePath: systemHooksPath,
      eventLabel: 'pre_tool_use',
      groupIndex: 0,
      handlerIndex: 0,
      command: userCommand,
    );
    File(p.join(home.path, '.codex', 'config.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '[hooks.state."${_escapeTomlString(systemTrustKey)}"]\n'
        'enabled = false\n'
        'trusted_hash = "$systemTrustedHash"\n',
      );

    final preparation = await service.prepareForTerminalLaunch();

    final runtimeHooksPath = p.join(preparation.runtimeHomePath, 'hooks.json');
    final canonicalRuntimeHooksPath = File(
      runtimeHooksPath,
    ).resolveSymbolicLinksSync();
    final runtimeTrustKey = '$canonicalRuntimeHooksPath:pre_tool_use:0:0';
    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(
      runtimeToml,
      contains('[hooks.state."${_escapeTomlString(runtimeTrustKey)}"]'),
    );
    expect(runtimeToml, contains('enabled = false'));
    expect(runtimeToml, contains('trusted_hash = "$systemTrustedHash"'));
  });

  test('preserves hook-like text inside multiline TOML strings', () async {
    final systemConfig = File(p.join(home.path, '.codex', 'config.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'note = """\n'
        '[hooks.state."fake-system"]\n'
        'trusted_hash = "not-a-section"\n'
        '"""\n'
        '\n'
        '[features]\n'
        'codex_hooks = true\n',
      );
    final runtimeTomlPath = p.join(
      support.path,
      'agent-runtime-homes',
      'codex',
      'home',
      'config.toml',
    );
    File(runtimeTomlPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '[hooks.state."runtime-hooks:stop:0:0"]\n'
        'enabled = true\n'
        'trusted_hash = "sha256:runtime"\n',
      );

    final preparation = await service.prepareForTerminalLaunch();

    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(runtimeToml, contains('[hooks.state."fake-system"]'));
    expect(runtimeToml, contains('trusted_hash = "not-a-section"'));
    expect(runtimeToml, contains('[hooks.state."runtime-hooks:stop:0:0"]'));
    expect(runtimeToml, contains('hooks = true'));
    expect(runtimeToml, isNot(contains('codex_hooks')));
    expect(systemConfig.readAsStringSync(), contains('codex_hooks = true'));
  });

  test('ignores fake trust blocks inside multiline TOML strings', () async {
    final systemHooksPath = p.join(home.path, '.codex', 'hooks.json');
    const userCommand = 'echo fake-trusted-user-hook';
    _writeJson(systemHooksPath, <String, Object?>{
      'hooks': <String, Object?>{
        'PreToolUse': <Object?>[_userHook(userCommand)],
      },
    });
    final canonicalSystemHooksPath = File(
      systemHooksPath,
    ).resolveSymbolicLinksSync();
    final systemTrustKey = '$canonicalSystemHooksPath:pre_tool_use:0:0';
    final systemTrustedHash = computeCodexTrustedHashForTesting(
      sourcePath: systemHooksPath,
      eventLabel: 'pre_tool_use',
      groupIndex: 0,
      handlerIndex: 0,
      command: userCommand,
    );
    File(p.join(home.path, '.codex', 'config.toml'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'note = """\n'
        '[hooks.state."${_escapeTomlString(systemTrustKey)}"]\n'
        'enabled = false\n'
        'trusted_hash = "$systemTrustedHash"\n'
        '"""\n',
      );

    final preparation = await service.prepareForTerminalLaunch();

    final runtimeHooksPath = p.join(preparation.runtimeHomePath, 'hooks.json');
    final canonicalRuntimeHooksPath = File(
      runtimeHooksPath,
    ).resolveSymbolicLinksSync();
    final runtimeTrustKey = '$canonicalRuntimeHooksPath:pre_tool_use:0:0';
    final runtimeToml = File(
      p.join(preparation.runtimeHomePath, 'config.toml'),
    ).readAsStringSync();
    expect(
      runtimeToml,
      isNot(contains('[hooks.state."${_escapeTomlString(runtimeTrustKey)}"]')),
    );
  });

  test('links or copies Codex resources into the runtime home', () async {
    final skillFile = File(p.join(home.path, '.codex', 'skills', 'demo.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('skill contents');

    final preparation = await service.prepareForTerminalLaunch();

    final runtimeSkillFile = File(
      p.join(preparation.runtimeHomePath, 'skills', 'demo.md'),
    );
    expect(runtimeSkillFile.existsSync(), isTrue);
    expect(runtimeSkillFile.readAsStringSync(), skillFile.readAsStringSync());
  });

  test(
    'reuses fallback copied resources while the source is unchanged',
    () async {
      final skillFile = File(p.join(home.path, '.codex', 'skills', 'demo.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('skill contents');
      final fallbackService = _serviceWithFailingResourceLinks(
        home: home,
        support: support,
      );

      final preparation = await fallbackService.prepareForTerminalLaunch();
      final runtimeSkillFile = File(
        p.join(preparation.runtimeHomePath, 'skills', 'demo.md'),
      );
      final runtimeOnlyFile = File(
        p.join(preparation.runtimeHomePath, 'skills', 'runtime-only.md'),
      )..writeAsStringSync('runtime-side change');
      final marker = File(
        p.join(preparation.runtimeHomePath, '.alera-copied-skills.json'),
      );
      final markerBefore = marker.readAsStringSync();

      await fallbackService.prepareForTerminalLaunch();

      expect(runtimeSkillFile.readAsStringSync(), skillFile.readAsStringSync());
      expect(runtimeOnlyFile.existsSync(), isTrue);
      expect(runtimeOnlyFile.readAsStringSync(), 'runtime-side change');
      expect(marker.readAsStringSync(), markerBefore);
    },
  );

  test(
    'refreshes fallback copied resources after the source changes',
    () async {
      final sourceSkillsPath = p.join(home.path, '.codex', 'skills');
      File(p.join(sourceSkillsPath, 'demo.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('skill contents');
      final fallbackService = _serviceWithFailingResourceLinks(
        home: home,
        support: support,
      );

      final preparation = await fallbackService.prepareForTerminalLaunch();
      final runtimeOnlyFile = File(
        p.join(preparation.runtimeHomePath, 'skills', 'runtime-only.md'),
      )..writeAsStringSync('runtime-side change');
      final marker = File(
        p.join(preparation.runtimeHomePath, '.alera-copied-skills.json'),
      );
      final fingerprintBefore = _markerFingerprint(marker);

      File(p.join(sourceSkillsPath, 'new.md')).writeAsStringSync('new source');
      await fallbackService.prepareForTerminalLaunch();

      expect(runtimeOnlyFile.existsSync(), isFalse);
      expect(
        File(
          p.join(preparation.runtimeHomePath, 'skills', 'new.md'),
        ).existsSync(),
        isTrue,
      );
      expect(_markerFingerprint(marker), isNot(fingerprintBefore));
    },
  );
}
