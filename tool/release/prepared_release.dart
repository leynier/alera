import 'dart:convert';
import 'dart:io';

import 'release_plan.dart';

const preparedReleasePath = 'tool/release/prepared_release.json';

final class const PreparedProductRelease({
  required final bool shouldRelease,
  required final String artifactVersion,
  required final String releaseVersion,
  required final int buildNumber,
  required final String tag,
  required final String previousTag,
}) {
  factory fromJson(Object? value) {
    final json = _jsonObject(value, 'product');
    return PreparedProductRelease(
      shouldRelease: _jsonBool(json, 'shouldRelease'),
      artifactVersion: _jsonString(json, 'artifactVersion'),
      releaseVersion: _jsonString(json, 'releaseVersion'),
      buildNumber: _jsonInt(json, 'buildNumber'),
      tag: _jsonString(json, 'tag'),
      previousTag: _jsonString(json, 'previousTag'),
    );
  }

  Map<String, Object> toJson() => {
    'shouldRelease': shouldRelease,
    'artifactVersion': artifactVersion,
    'releaseVersion': releaseVersion,
    'buildNumber': buildNumber,
    'tag': tag,
    'previousTag': previousTag,
  };
}

final class const PreparedRelease({
  required final String sourceSha,
  required final ReleaseChannel channel,
  required final PreparedProductRelease desktop,
  required final PreparedProductRelease mobile,
}) {
  factory fromJson(Object? value) {
    final json = _jsonObject(value, 'prepared release');
    if (_jsonInt(json, 'schemaVersion') != 1) {
      throw const FormatException('Unsupported prepared release schema.');
    }
    final release = PreparedRelease(
      sourceSha: _jsonString(json, 'sourceSha'),
      channel: switch (_jsonString(json, 'channel')) {
        'stable' => ReleaseChannel.stable,
        'rc' => ReleaseChannel.rc,
        _ => throw const FormatException('Invalid prepared release channel.'),
      },
      desktop: .fromJson(json['desktop']),
      mobile: .fromJson(json['mobile']),
    );
    release.validate();
    return release;
  }

  Iterable<PreparedProductRelease> get products => [desktop, mobile];

  List<String> get tags => products
      .where((product) => product.shouldRelease)
      .map((product) => product.tag)
      .toList(growable: false);

  String get title => 'release: ${tags.join(' ')}';

  String get branchName => 'release/version-${tags.join('-and-')}';

  Set<String> get requiredChangedPaths => {
    preparedReleasePath,
    if (desktop.shouldRelease) 'pubspec.yaml',
    if (mobile.shouldRelease) 'mobile/pubspec.yaml',
  };

  Set<String> get expectedChangedPaths => {
    ...requiredChangedPaths,
    if (channel == ReleaseChannel.stable) 'landing/src/data/releases.json',
  };

  Set<String> get optionalUnchangedPaths => {
    if (channel == ReleaseChannel.stable) 'landing/src/data/releases.json',
  };

  Map<String, Object> toJson() => {
    'schemaVersion': 1,
    'sourceSha': sourceSha,
    'channel': channel.name,
    'desktop': desktop.toJson(),
    'mobile': mobile.toJson(),
  };

  void validate() {
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(sourceSha)) {
      throw const FormatException('sourceSha must be a full commit SHA.');
    }
    if (tags.isEmpty) {
      throw const FormatException('A prepared release needs at least one tag.');
    }
    _validateProduct(channel, .desktop, desktop);
    _validateProduct(channel, .mobile, mobile);
  }

  void validateIdentity({
    required String expectedSourceSha,
    required ReleaseChannel expectedChannel,
    required String expectedDesktopTag,
    required String expectedMobileTag,
  }) {
    if (sourceSha != expectedSourceSha || channel != expectedChannel) {
      throw StateError('The existing version branch belongs to another cut.');
    }
    final actualDesktopTag = desktop.shouldRelease ? desktop.tag : '';
    final actualMobileTag = mobile.shouldRelease ? mobile.tag : '';
    if (actualDesktopTag != expectedDesktopTag ||
        actualMobileTag != expectedMobileTag) {
      throw StateError('The existing version branch has different tags.');
    }
  }

  void validateVersionFiles() {
    _validatePubspec('pubspec.yaml', desktop);
    _validatePubspec('mobile/pubspec.yaml', mobile);
  }

  void validateReplannedOutputs(Map<String, String> outputs) {
    if (outputs['channel'] != channel.name) {
      throw StateError('The merged release channel no longer matches.');
    }
    for (final entry in {'desktop': desktop, 'mobile': mobile}.entries) {
      final replanned = outputs['${entry.key}_should_release'] == 'true';
      if (replanned != entry.value.shouldRelease ||
          (replanned && outputs['${entry.key}_tag'] != entry.value.tag)) {
        throw StateError(
          'The ${entry.key} plan became stale before the version PR merged.',
        );
      }
    }
  }
}

void _validateProduct(
  ReleaseChannel channel,
  ReleaseProduct product,
  PreparedProductRelease prepared,
) {
  if (!prepared.shouldRelease) {
    if (prepared.artifactVersion.isNotEmpty ||
        prepared.releaseVersion.isNotEmpty ||
        prepared.buildNumber != 0 ||
        prepared.tag.isNotEmpty ||
        prepared.previousTag.isNotEmpty) {
      throw FormatException('Inactive ${product.name} plan must be empty.');
    }
    return;
  }
  final parsed = parseReleaseTag(prepared.tag);
  if (parsed == null || parsed.product != product) {
    throw FormatException('Invalid ${product.name} release tag.');
  }
  if ((channel == ReleaseChannel.stable) != parsed.isStable) {
    throw FormatException('${product.name} tag does not match the channel.');
  }
  if (parsed.core.toString() != prepared.artifactVersion ||
      prepared.buildNumber < 1) {
    throw FormatException('Invalid ${product.name} version metadata.');
  }
  final expectedRelease = parsed.rc == null
      ? parsed.core.toString()
      : '${parsed.core}-rc.${parsed.rc}';
  if (prepared.releaseVersion != expectedRelease) {
    throw FormatException('Invalid ${product.name} release version.');
  }
}

void _validatePubspec(String path, PreparedProductRelease product) {
  if (!product.shouldRelease) return;
  final expected = 'version: ${product.artifactVersion}+${product.buildNumber}';
  if (!File(path).readAsStringSync().split('\n').contains(expected)) {
    throw StateError('$path does not contain $expected.');
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    throw ArgumentError('Expected write, inspect, or compare.');
  }
  final command = arguments.first;
  final values = _parseFlags(arguments.skip(1).toList());
  switch (command) {
    case 'write':
      final release = _releaseFromFlags(values);
      File(_required(values, 'output')).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(release.toJson())}\n',
      );
      _appendOutputs(_required(values, 'github-output'), {
        'version_branch': release.branchName,
        'version_title': release.title,
      });
      return;
    case 'compare':
      final release = _readPrepared(_required(values, 'file'));
      release.validateIdentity(
        expectedSourceSha: _required(values, 'source-sha'),
        expectedChannel: _parseChannel(_required(values, 'channel')),
        expectedDesktopTag: values['desktop-tag'] ?? '',
        expectedMobileTag: values['mobile-tag'] ?? '',
      );
      await _validatePreparedTree(release, _required(values, 'treeish'));
      _appendOutputs(_required(values, 'github-output'), {
        'version_branch': release.branchName,
        'version_title': release.title,
      });
      return;
    case 'inspect':
      await _inspectMergedRelease(values);
      return;
    case 'compare-plan':
      final release = _readPrepared(_required(values, 'file'));
      release.validateReplannedOutputs(
        _readGitHubOutputs(_required(values, 'plan-output')),
      );
      return;
    default:
      throw ArgumentError('Unknown prepared release command: $command');
  }
}

Future<void> _validatePreparedTree(
  PreparedRelease release,
  String treeish,
) async {
  final parent = (await _run('git', ['rev-parse', '$treeish^'])).trim();
  final title = (await _run('git', [
    'show',
    '-s',
    '--format=%s',
    treeish,
  ])).trim();
  if (parent != release.sourceSha || title != release.title) {
    throw StateError('The existing version branch has unexpected history.');
  }
  final changedPaths = const LineSplitter()
      .convert(
        await _run('git', ['diff', '--name-only', release.sourceSha, treeish]),
      )
      .toSet();
  if (!_setEquals(changedPaths, release.expectedChangedPaths)) {
    throw StateError('The existing version branch changed unexpected paths.');
  }
  for (final entry in {
    'pubspec.yaml': release.desktop,
    'mobile/pubspec.yaml': release.mobile,
  }.entries) {
    if (!entry.value.shouldRelease) continue;
    final contents = await _run('git', ['show', '$treeish:${entry.key}']);
    final expected =
        'version: ${entry.value.artifactVersion}+${entry.value.buildNumber}';
    if (!contents.split('\n').contains(expected)) {
      throw StateError('${entry.key} does not contain $expected.');
    }
  }
}

PreparedRelease _releaseFromFlags(Map<String, String> values) {
  PreparedProductRelease product(String prefix) {
    final shouldRelease = _required(values, '$prefix-should-release') == 'true';
    if (!shouldRelease) {
      return const PreparedProductRelease(
        shouldRelease: false,
        artifactVersion: '',
        releaseVersion: '',
        buildNumber: 0,
        tag: '',
        previousTag: '',
      );
    }
    return PreparedProductRelease(
      shouldRelease: true,
      artifactVersion: _required(values, '$prefix-artifact-version'),
      releaseVersion: _required(values, '$prefix-release-version'),
      buildNumber: int.parse(_required(values, '$prefix-build-number')),
      tag: _required(values, '$prefix-tag'),
      previousTag: values['$prefix-previous-tag'] ?? '',
    );
  }

  final release = PreparedRelease(
    sourceSha: _required(values, 'source-sha'),
    channel: _parseChannel(_required(values, 'channel')),
    desktop: product('desktop'),
    mobile: product('mobile'),
  );
  release.validate();
  return release;
}

Future<void> _inspectMergedRelease(Map<String, String> values) async {
  final release = _readPrepared(_required(values, 'file'));
  final targetSha = _required(values, 'target-sha');
  final repository = _required(values, 'repository');
  if ((await _run('git', ['rev-parse', 'HEAD'])).trim() != targetSha) {
    throw StateError('Checkout is not the exact merged version commit.');
  }
  if (_required(values, 'pr-title') != release.title) {
    throw StateError('Version PR title does not match its prepared plan.');
  }
  await _run('git', ['fetch', 'origin', 'main', '--tags', '--quiet']);
  await _run('git', ['merge-base', '--is-ancestor', targetSha, 'origin/main']);
  final changedPaths = const LineSplitter()
      .convert(
        await _run('git', ['diff', '--name-only', '$targetSha^', targetSha]),
      )
      .toSet();
  final unexpected = changedPaths.difference(release.expectedChangedPaths);
  final missing = release.requiredChangedPaths.difference(changedPaths);
  if (unexpected.isNotEmpty || missing.isNotEmpty) {
    throw StateError(
      'Merged version commit changed unexpected paths: '
      'missing=${missing.toList()..sort()} '
      'unexpected=${unexpected.toList()..sort()}.',
    );
  }
  release.validateVersionFiles();

  Future<bool> pending(PreparedProductRelease product) async {
    if (!product.shouldRelease) return false;
    final tagResult = await Process.run('git', [
      'rev-parse',
      'refs/tags/${product.tag}^{commit}',
    ]);
    if (tagResult.exitCode == 0 &&
        tagResult.stdout.toString().trim() != targetSha) {
      throw StateError('Tag ${product.tag} points at another commit.');
    }
    final releaseResult = await Process.run('gh', [
      'release',
      'view',
      product.tag,
      '--repo',
      repository,
      '--json',
      'isDraft',
    ]);
    if (releaseResult.exitCode != 0) return true;
    final json = _jsonObject(
      jsonDecode(releaseResult.stdout.toString()),
      'release',
    );
    return _jsonBool(json, 'isDraft');
  }

  final desktopPending = await pending(release.desktop);
  final mobilePending = await pending(release.mobile);
  _appendOutputs(_required(values, 'github-output'), {
    'target_sha': targetSha,
    'channel': release.channel.name,
    'ready_to_publish': 'true',
    'version_pr_needed': 'false',
    'any_should_release': '${desktopPending || mobilePending}',
    ..._productOutputs('desktop', release.desktop, desktopPending),
    ..._productOutputs('mobile', release.mobile, mobilePending),
  });
  File(_required(values, 'summary')).writeAsStringSync(
    'Validated merged version commit `$targetSha` from `${release.branchName}`.\n',
    mode: .append,
  );
}

Map<String, String> _productOutputs(
  String prefix,
  PreparedProductRelease product,
  bool pending,
) => {
  '${prefix}_has_changes': '${product.shouldRelease}',
  '${prefix}_should_release': '$pending',
  '${prefix}_bump': 'prepared',
  '${prefix}_artifact_version': product.artifactVersion,
  '${prefix}_release_version': product.releaseVersion,
  '${prefix}_build_number': '${product.buildNumber}',
  '${prefix}_tag': product.tag,
  '${prefix}_previous_tag': product.previousTag,
};

PreparedRelease _readPrepared(String path) =>
    PreparedRelease.fromJson(jsonDecode(File(path).readAsStringSync()));

Map<String, String> _readGitHubOutputs(String path) {
  final values = <String, String>{};
  for (final line in File(path).readAsLinesSync()) {
    final separator = line.indexOf('=');
    if (separator > 0) {
      values[line.substring(0, separator)] = line.substring(separator + 1);
    }
  }
  return values;
}

Map<String, String> _parseFlags(List<String> arguments) {
  if (arguments.length.isOdd) throw ArgumentError('Flags require values.');
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final flag = arguments[index];
    if (!flag.startsWith('--')) throw ArgumentError('Unexpected $flag.');
    values[flag.substring(2)] = arguments[index + 1];
  }
  return values;
}

ReleaseChannel _parseChannel(String value) => switch (value) {
  'stable' => ReleaseChannel.stable,
  'rc' => ReleaseChannel.rc,
  _ => throw ArgumentError('Channel must be stable or rc.'),
};

String _required(Map<String, String> values, String key) {
  final value = values[key];
  if (value == null || value.isEmpty) {
    throw ArgumentError('--$key is required.');
  }
  return value;
}

Map<String, dynamic> _jsonObject(Object? value, String name) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$name must be an object.');
  }
  return value;
}

String _jsonString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string.');
  return value;
}

int _jsonInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

bool _jsonBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean.');
  return value;
}

void _appendOutputs(String path, Map<String, String> outputs) {
  File(path).writeAsStringSync(
    '${outputs.entries.map((entry) => '${entry.key}=${entry.value}').join('\n')}\n',
    mode: .append,
  );
}

bool _setEquals(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

Future<String> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return result.stdout.toString();
}
