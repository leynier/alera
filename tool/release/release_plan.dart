import 'dart:convert';
import 'dart:io';

enum ReleaseProduct { desktop, mobile }

enum ReleaseChannel { stable, rc }

enum VersionBump { patch, minor, major }

final class const SemanticVersion(
  final int major,
  final int minor,
  final int patch,
) implements Comparable<SemanticVersion> {
  SemanticVersion bump(VersionBump bump) => switch (bump) {
    VersionBump.major => SemanticVersion(major + 1, 0, 0),
    VersionBump.minor => SemanticVersion(major, minor + 1, 0),
    VersionBump.patch => SemanticVersion(major, minor, patch + 1),
  };

  @override
  int compareTo(SemanticVersion other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) return majorOrder;
    final minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) return minorOrder;
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is SemanticVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

final class const ReleaseTag({
  required final String name,
  required final ReleaseProduct product,
  required final SemanticVersion core,
  final int? rc,
}) implements Comparable<ReleaseTag> {
  bool get isStable => rc == null;

  @override
  int compareTo(ReleaseTag other) {
    final coreOrder = core.compareTo(other.core);
    if (coreOrder != 0) return coreOrder;
    if (rc == null && other.rc == null) return 0;
    if (rc == null) return 1;
    if (other.rc == null) return -1;
    return rc!.compareTo(other.rc!);
  }
}

ReleaseTag? parseReleaseTag(String name) {
  final match = RegExp(r'^v(\d+)\.(\d+)\.(\d+)(?:-rc\.(\d+))?(-mobile)?$')
      .firstMatch(name);
  if (match == null) return null;
  return ReleaseTag(
    name: name,
    product: match.group(5) == null
        ? ReleaseProduct.desktop
        : ReleaseProduct.mobile,
    core: SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ),
    rc: match.group(4) == null ? null : int.parse(match.group(4)!),
  );
}

bool isReleaseBookkeepingSubject(String subject) {
  if (!subject.startsWith('release: ')) return false;
  final remainder = subject
      .substring('release: '.length)
      .replaceFirst(RegExp(r'\s+\(#\d+\)$'), '')
      .trim();
  if (remainder.isEmpty) return false;
  return remainder
      .split(RegExp(r'\s+'))
      .every(
        (token) =>
            parseReleaseTag(token) != null ||
            RegExp(r'^mobile-v\d+\.\d+\.\d+(?:-rc\.\d+)?$').hasMatch(token),
      );
}

bool pathsMatchProduct(ReleaseProduct product, Iterable<String> paths) {
  return switch (product) {
    ReleaseProduct.mobile => paths.any((path) => path.startsWith('mobile/')),
    ReleaseProduct.desktop => paths.any(
      (path) => !path.startsWith('mobile/') && !path.startsWith('landing/'),
    ),
  };
}

final class const ReleaseChange({
  required final String subject,
  required final String body,
  required final List<String> paths,
});

VersionBump? classifyChanges(
  ReleaseProduct product,
  Iterable<ReleaseChange> changes,
) {
  VersionBump? result;
  for (final change in changes) {
    if (isReleaseBookkeepingSubject(change.subject) ||
        !pathsMatchProduct(product, change.paths)) {
      continue;
    }
    final breaking =
        RegExp(r'^[a-zA-Z][\w-]*(?:\([^)]*\))?!:').hasMatch(change.subject) ||
        RegExp(
          r'(^|\n)BREAKING(?: CHANGE|-CHANGE):',
          caseSensitive: false,
        ).hasMatch(change.body);
    final bump = breaking
        ? VersionBump.major
        : RegExp(r'^feat(?:\([^)]*\))?:').hasMatch(change.subject)
        ? VersionBump.minor
        : VersionBump.patch;
    if (result == null || bump.index > result.index) result = bump;
  }
  return result;
}

final class const ProductReleasePlan({
  required final ReleaseProduct product,
  required final SemanticVersion stableBase,
  required final bool hasChanges,
  required final bool shouldRelease,
  required final VersionBump? bump,
  required final String artifactVersion,
  required final String releaseVersion,
  required final int buildNumber,
  required final String tag,
  required final String previousTag,
});

ProductReleasePlan planProductRelease({
  required ReleaseProduct product,
  required ReleaseChannel channel,
  required Iterable<ReleaseTag> tags,
  required Iterable<ReleaseChange> stableChanges,
  required Iterable<ReleaseChange> channelChanges,
  required int currentBuildNumber,
  required int runNumber,
  required bool dryRun,
}) {
  final productTags = tags.where((tag) => tag.product == product).toList();
  final stableTags = productTags.where((tag) => tag.isStable).toList()..sort();
  final latestStable = stableTags.isEmpty ? null : stableTags.last;
  final stableBase =
      latestStable?.core ??
      (product == ReleaseProduct.desktop
          ? const SemanticVersion(0, 1, 0)
          : const SemanticVersion(0, 0, 0));
  final scopedChannelChanges = channelChanges.where(
    (change) =>
        !isReleaseBookkeepingSubject(change.subject) &&
        pathsMatchProduct(product, change.paths),
  );
  final hasChanges = scopedChannelChanges.isNotEmpty;
  final bump = classifyChanges(product, stableChanges);
  final buildNumber = currentBuildNumber + 1 > runNumber
      ? currentBuildNumber + 1
      : runNumber;
  if (!hasChanges || bump == null) {
    return ProductReleasePlan(
      product: product,
      stableBase: stableBase,
      hasChanges: hasChanges,
      shouldRelease: false,
      bump: bump,
      artifactVersion: '',
      releaseVersion: '',
      buildNumber: buildNumber,
      tag: '',
      previousTag: '',
    );
  }

  var core = stableBase.bump(bump);
  final rcTags = productTags.where((tag) => !tag.isStable).toList();
  for (final rcTag in rcTags) {
    if (rcTag.core.compareTo(stableBase) > 0 &&
        rcTag.core.compareTo(core) > 0) {
      core = rcTag.core;
    }
  }
  var releaseVersion = core.toString();
  var previousTag = latestStable?.name ?? '';
  if (channel == ReleaseChannel.rc) {
    final sameCore = rcTags.where((tag) => tag.core == core).toList()..sort();
    final nextRc = sameCore.isEmpty ? 0 : sameCore.last.rc! + 1;
    releaseVersion = '$core-rc.$nextRc';
    if (sameCore.isNotEmpty) previousTag = sameCore.last.name;
  }
  final mobileSuffix = product == ReleaseProduct.mobile ? '-mobile' : '';
  return ProductReleasePlan(
    product: product,
    stableBase: stableBase,
    hasChanges: true,
    shouldRelease: !dryRun,
    bump: bump,
    artifactVersion: core.toString(),
    releaseVersion: releaseVersion,
    buildNumber: buildNumber,
    tag: 'v$releaseVersion$mobileSuffix',
    previousTag: previousTag,
  );
}

Future<void> main(List<String> arguments) async {
  final options = _parseCli(arguments);
  final targetSha = (await _run('git', [
    'rev-parse',
    '${options.target}^{commit}',
  ])).trim();
  final tags = const LineSplitter()
      .convert(await _run('git', ['tag', '--list']))
      .map(parseReleaseTag)
      .whereType<ReleaseTag>()
      .toList();
  final plans = <ProductReleasePlan>[];
  for (final product in ReleaseProduct.values) {
    final productTags = tags.where((tag) => tag.product == product).toList();
    final stableTags = productTags.where((tag) => tag.isStable).toList()
      ..sort();
    final allTags = [...productTags]..sort();
    final stableStart = stableTags.isEmpty ? null : stableTags.last.name;
    final channelStart = options.channel == ReleaseChannel.stable
        ? stableStart
        : (allTags.isEmpty ? null : allTags.last.name);
    final ranges = <String?>{stableStart, channelStart};
    final changesByStart = <String?, List<ReleaseChange>>{};
    for (final start in ranges) {
      changesByStart[start] = await _readChanges(
        start == null ? targetSha : '$start..$targetSha',
        options.repository,
      );
    }
    plans.add(
      planProductRelease(
        product: product,
        channel: options.channel,
        tags: tags,
        stableChanges: changesByStart[stableStart]!,
        channelChanges: changesByStart[channelStart]!,
        currentBuildNumber: _pubspecBuildNumber(
          product == ReleaseProduct.desktop
              ? 'pubspec.yaml'
              : 'mobile/pubspec.yaml',
        ),
        runNumber: options.runNumber,
        dryRun: options.dryRun,
      ),
    );
  }
  _writeOutputs(options.githubOutput, targetSha, options.channel, plans);
  _writeSummary(options.summary, plans);
}

final class const _CliOptions({
  required final String target,
  required final ReleaseChannel channel,
  required final String repository,
  required final int runNumber,
  required final bool dryRun,
  required final String githubOutput,
  required final String summary,
});

_CliOptions _parseCli(List<String> arguments) {
  if (arguments.length.isOdd) {
    throw ArgumentError('Flags require values');
  }
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final flag = arguments[index];
    if (!flag.startsWith('--')) {
      throw ArgumentError('Unexpected argument: $flag');
    }
    values[flag.substring(2)] = arguments[index + 1];
  }
  String required(String key) {
    final value = values[key];
    if (value == null || value.isEmpty) {
      throw ArgumentError('--$key is required');
    }
    return value;
  }

  final channel = switch (required('channel')) {
    'stable' => ReleaseChannel.stable,
    'rc' => ReleaseChannel.rc,
    _ => throw ArgumentError('--channel must be stable or rc'),
  };
  final dryRun = switch (required('dry-run')) {
    'true' => true,
    'false' => false,
    _ => throw ArgumentError('--dry-run must be true or false'),
  };
  return _CliOptions(
    target: required('target'),
    channel: channel,
    repository:
        values['repository'] ??
        Platform.environment['GITHUB_REPOSITORY'] ??
        (throw ArgumentError('--repository is required')),
    runNumber: int.parse(required('run-number')),
    dryRun: dryRun,
    githubOutput: required('github-output'),
    summary: required('summary'),
  );
}

Future<List<ReleaseChange>> _readChanges(
  String range,
  String repository,
) async {
  final log = await _run('git', [
    'log',
    '--first-parent',
    '--format=%H%x1f%s%x1f%b%x1e',
    range,
  ]);
  final changes = <ReleaseChange>[];
  for (final record in log.split('\x1e')) {
    final fields = record.trim().split('\x1f');
    if (fields.length < 3) continue;
    final sha = fields[0];
    var subject = fields[1].trim();
    var body = fields.sublist(2).join('\x1f').trim();
    final merge = RegExp(r'^Merge pull request #(\d+)\b').firstMatch(subject);
    if (merge != null) {
      final pull = jsonDecode(
        await _run('gh', ['api', 'repos/$repository/pulls/${merge.group(1)}']),
      ) as Map<String, dynamic>;
      subject = pull['title'] as String;
      body = pull['body'] as String? ?? '';
    }
    List<String> paths;
    try {
      paths = const LineSplitter().convert(
        await _run('git', ['diff', '--name-only', '$sha^1', sha]),
      );
    } on ProcessException {
      paths = const LineSplitter().convert(
        await _run('git', ['show', '--name-only', '--format=', sha]),
      );
    }
    changes.add(ReleaseChange(subject: subject, body: body, paths: paths));
  }
  return changes;
}

int _pubspecBuildNumber(String path) {
  final match = RegExp(
    r'^version:\s*[^+\s]+\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(File(path).readAsStringSync());
  if (match == null) throw FormatException('Missing build suffix in $path');
  return int.parse(match.group(1)!);
}

void _writeOutputs(
  String path,
  String targetSha,
  ReleaseChannel channel,
  List<ProductReleasePlan> plans,
) {
  final lines = <String>[
    'target_sha=$targetSha',
    'channel=${channel.name}',
    'any_should_release=${plans.any((plan) => plan.shouldRelease)}',
    'ready_to_publish=false',
    'version_pr_needed=${plans.any((plan) => plan.shouldRelease)}',
  ];
  for (final plan in plans) {
    final prefix = plan.product.name;
    lines.addAll([
      '${prefix}_has_changes=${plan.hasChanges}',
      '${prefix}_should_release=${plan.shouldRelease}',
      '${prefix}_bump=${plan.bump?.name ?? 'none'}',
      '${prefix}_artifact_version=${plan.artifactVersion}',
      '${prefix}_release_version=${plan.releaseVersion}',
      '${prefix}_build_number=${plan.buildNumber}',
      '${prefix}_tag=${plan.tag}',
      '${prefix}_previous_tag=${plan.previousTag}',
    ]);
  }
  File(path).writeAsStringSync('${lines.join('\n')}\n', mode: .append);
}

void _writeSummary(String path, List<ProductReleasePlan> plans) {
  final buffer = StringBuffer()
    ..writeln(
      '| Product | Stable Base | Changes | Bump | Next Tag | Build Number |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  for (final plan in plans) {
    buffer.writeln(
      '| ${plan.product.name} | ${plan.stableBase} | '
      '${plan.hasChanges} | ${plan.bump?.name ?? 'none'} | '
      '${plan.tag.isEmpty ? '-' : plan.tag} | ${plan.buildNumber} |',
    );
  }
  File(path).writeAsStringSync(buffer.toString(), mode: .append);
}

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
