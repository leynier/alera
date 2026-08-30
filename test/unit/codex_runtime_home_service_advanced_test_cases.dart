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
    final canonicalSystemHooksPath = File(systemHooksPath)
        .resolveSymbolicLinksSync();
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
    final canonicalRuntimeHooksPath = File(runtimeHooksPath)
        .resolveSymbolicLinksSync();
    final runtimeTrustKey = '$canonicalRuntimeHooksPath:pre_tool_use:0:0';
    final runtimeToml = File(p.join(preparation.runtimeHomePath, 'config.toml'))
        .readAsStringSync();
    expect(
      runtimeToml,
      contains('[hooks.state."${_escapeTomlString(runtimeTrustKey)}"]'),
    );
    expect(runtimeToml, contains('enabled = false'));
    expect(runtimeToml, contains('trusted_hash = "$systemTrustedHash"'));
  });

  test(
    'parses escaped TOML trust strings while checking runtime status',
    () async {
      final preparation = await service.prepareForTerminalLaunch();
      final runtimeTomlPath = p.join(
        preparation.runtimeHomePath,
        'config.toml',
      );
      File(runtimeTomlPath).writeAsStringSync(r'''
[hooks.state."escaped\n\r\t\b\f\"\\z:stop:0:0"]
enabled = true
trusted_hash = "sha256:escaped\n\r\t\b\f\"\\z"
''', mode: FileMode.append);

      final status = await service.status();

      expect(status.state, ManagedAgentHookInstallState.installed);
    },
  );

  test('parses unknown TOML escapes and EOF trust blocks', () async {
    final preparation = await service.prepareForTerminalLaunch();
    final runtimeTomlPath = p.join(preparation.runtimeHomePath, 'config.toml');
    File(runtimeTomlPath).writeAsStringSync(
      '\n[hooks.state."unknown\\q:stop:0:0"]\n'
      'enabled = true',
      mode: FileMode.append,
    );

    final status = await service.status();

    expect(status.state, ManagedAgentHookInstallState.installed);
  });

  test('removes stale runtime trust entries when hooks change', () async {
    final preparation = await service.prepareForTerminalLaunch();
    final runtimeHooksPath = p.join(preparation.runtimeHomePath, 'hooks.json');
    final canonicalRuntimeHooksPath = File(runtimeHooksPath)
        .resolveSymbolicLinksSync();
    final runtimeTomlPath = p.join(preparation.runtimeHomePath, 'config.toml');
    File(runtimeTomlPath).writeAsStringSync(
      _trustBlock(
        key: '$canonicalRuntimeHooksPath:stop:99:99',
        enabled: true,
        trustedHash: 'sha256:stale',
      ),
      mode: FileMode.append,
    );

    await service.prepareForTerminalLaunch();

    expect(
      File(runtimeTomlPath).readAsStringSync(),
      isNot(contains('sha256:stale')),
    );
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

    final runtimeToml = File(p.join(preparation.runtimeHomePath, 'config.toml'))
        .readAsStringSync();
    expect(runtimeToml, contains('[hooks.state."fake-system"]'));
    expect(runtimeToml, contains('trusted_hash = "not-a-section"'));
    expect(runtimeToml, contains('[hooks.state."runtime-hooks:stop:0:0"]'));
    expect(runtimeToml, contains('hooks = true'));
    expect(runtimeToml, isNot(contains('codex_hooks')));
    expect(systemConfig.readAsStringSync(), contains('codex_hooks = true'));
  });

  test(
    'normalizes complex TOML headers without treating strings as tables',
    () async {
      File(p.join(home.path, '.codex', 'config.toml'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '\ufefftitle = "demo"\n'
          '\n'
          '[features]\n'
          'basic_note = """line with escaped \\\\" quote\n'
          '[not.a.table]\n'
          '"""\n'
          "literal_note = '''\n"
          '[also.not.a.table]\n'
          "'''\n"
          'codex_hooks = false\n'
          'hooks = false\n'
          '\n'
          '[projects."escaped\\\\"project"]\n'
          'trust_level = "trusted"\n'
          '\n'
          "[projects.'literal]project']\n"
          'trust_level = "trusted"\n'
          '\n'
          '[[profiles."array]profile"]] # valid array table\n'
          'name = "demo"\n'
          '\n'
          '[[broken.array] trailing text\n',
        );

      final preparation = await service.prepareForTerminalLaunch();

      final runtimeToml = File(
        p.join(preparation.runtimeHomePath, 'config.toml'),
      ).readAsStringSync();
      expect(runtimeToml.codeUnitAt(0), isNot(0xfeff));
      expect(runtimeToml, contains('hooks = true'));
      expect(runtimeToml, isNot(contains('codex_hooks')));
      expect(runtimeToml, contains('[not.a.table]'));
      expect(runtimeToml, contains('[also.not.a.table]'));
      expect(runtimeToml, contains('[projects."escaped\\\\"project"]'));
      expect(runtimeToml, contains("[projects.'literal]project']"));
      expect(runtimeToml, contains('[[profiles."array]profile"]]'));
      expect(runtimeToml, contains('[[broken.array] trailing text'));
    },
  );

  test('ignores fake trust blocks inside multiline TOML strings', () async {
    final systemHooksPath = p.join(home.path, '.codex', 'hooks.json');
    const userCommand = 'echo fake-trusted-user-hook';
    _writeJson(systemHooksPath, <String, Object?>{
      'hooks': <String, Object?>{
        'PreToolUse': <Object?>[_userHook(userCommand)],
      },
    });
    final canonicalSystemHooksPath = File(systemHooksPath)
        .resolveSymbolicLinksSync();
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
    final canonicalRuntimeHooksPath = File(runtimeHooksPath)
        .resolveSymbolicLinksSync();
    final runtimeTrustKey = '$canonicalRuntimeHooksPath:pre_tool_use:0:0';
    final runtimeToml = File(p.join(preparation.runtimeHomePath, 'config.toml'))
        .readAsStringSync();
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
      final nestedSkillsPath = p.join(sourceSkillsPath, 'nested');
      File(p.join(nestedSkillsPath, 'demo.md'))
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

      File(p.join(nestedSkillsPath, 'new.md')).writeAsStringSync('new source');
      await fallbackService.prepareForTerminalLaunch();

      expect(runtimeOnlyFile.existsSync(), isFalse);
      expect(
        File(p.join(preparation.runtimeHomePath, 'skills', 'nested', 'new.md'))
            .existsSync(),
        isTrue,
      );
      expect(_markerFingerprint(marker), isNot(fingerprintBefore));
    },
  );

  test(
    'clears markers for linked resources and removes stale owned entries',
    () async {
      final sourceSkills = Directory(p.join(home.path, '.codex', 'skills'))
        ..createSync(recursive: true);
      File(p.join(sourceSkills.path, 'demo.md')).writeAsStringSync('skill');
      final preparation = await service.prepareForTerminalLaunch();
      final marker = File(
        p.join(preparation.runtimeHomePath, '.alera-copied-skills.json'),
      )..writeAsStringSync('{}\n');

      await service.prepareForTerminalLaunch();

      expect(marker.existsSync(), isFalse);

      final sourcePrompts = Directory(p.join(home.path, '.codex', 'prompts'))
        ..createSync(recursive: true);
      File(p.join(sourcePrompts.path, 'demo.md')).writeAsStringSync('prompt');
      await service.prepareForTerminalLaunch();
      sourcePrompts.deleteSync(recursive: true);
      await service.prepareForTerminalLaunch();

      expect(
        FileSystemEntity.typeSync(
          p.join(preparation.runtimeHomePath, 'prompts'),
          followLinks: false,
        ),
        FileSystemEntityType.notFound,
      );
    },
  );

  test(
    'accepts relative runtime links that already point to the source',
    () async {
      final runtimeHome = Directory(
        p.join(support.path, 'agent-runtime-homes', 'codex', 'home'),
      )..createSync(recursive: true);
      final sourceSkills = Directory(p.join(home.path, '.codex', 'skills'))
        ..createSync(recursive: true);
      File(p.join(sourceSkills.path, 'demo.md')).writeAsStringSync('skill');
      final relativeTarget = p.relative(
        sourceSkills.path,
        from: runtimeHome.path,
      );
      Link(p.join(runtimeHome.path, 'skills')).createSync(relativeTarget);
      final marker = File(p.join(runtimeHome.path, '.alera-copied-skills.json'))
        ..writeAsStringSync('{}\n');

      await service.prepareForTerminalLaunch();

      expect(marker.existsSync(), isFalse);
      expect(
        Link(p.join(runtimeHome.path, 'skills')).targetSync(),
        relativeTarget,
      );
    },
  );

  test(
    'resolves Codex home from USERPROFILE and current directory fallbacks',
    () {
      final profileService = CodexRuntimeHomeService(
        applicationSupportDirectory: () async => support,
        platform: ManagedAgentHookPlatform.posix,
        environment: <String, String>{'HOME': '', 'USERPROFILE': home.path},
      );
      final currentFallbackService = CodexRuntimeHomeService(
        applicationSupportDirectory: () async => support,
        platform: ManagedAgentHookPlatform.posix,
        environment: const <String, String>{},
      );

      expect(profileService, isA<CodexRuntimeHomeService>());
      expect(currentFallbackService, isA<CodexRuntimeHomeService>());
    },
  );

  test(
    'copies linked resources and ignores malformed fallback markers',
    () async {
      final targetPath = p.join(home.path, 'missing-theme-target.toml');
      final sourceThemes = Directory(p.join(home.path, '.codex', 'themes'))
        ..createSync(recursive: true);
      Link(p.join(sourceThemes.path, 'linked-theme.toml'))
          .createSync(targetPath);
      final fallbackService = _serviceWithFailingResourceLinks(
        home: home,
        support: support,
      );

      final preparation = await fallbackService.prepareForTerminalLaunch();
      final marker = File(
        p.join(preparation.runtimeHomePath, '.alera-copied-themes.json'),
      )..writeAsStringSync('{bad');
      sourceThemes.deleteSync(recursive: true);
      await fallbackService.prepareForTerminalLaunch();

      expect(marker.existsSync(), isTrue);
      expect(
        FileSystemEntity.typeSync(
          p.join(preparation.runtimeHomePath, 'themes'),
          followLinks: false,
        ),
        isNot(FileSystemEntityType.notFound),
      );
    },
  );
}
