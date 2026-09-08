import 'dart:io';

/// Prints the test files belonging to one CI shard, one path per line.
///
/// `flutter test --total-shards/--shard-index` is not usable here: it slices
/// the tests *inside* each suite after the suite has been loaded, so every
/// shard still compiles every test file. With roughly 1.4s per file the cost is
/// compilation, not assertion execution, so the split has to happen on the file
/// list before `flutter test` is invoked.
class const ShardArgs({
  required final int total,
  required final int index,
  required final List<String> roots,
  required final List<String> skips,
}) {
  static ShardArgs parse(List<String> args) {
    int? total;
    int? index;
    final roots = <String>[];
    final skips = <String>[];

    for (var cursor = 0; cursor < args.length; cursor += 1) {
      final arg = args[cursor];
      String requireValue() {
        if (cursor + 1 >= args.length) {
          throw FormatException('Missing value for $arg');
        }
        cursor += 1;
        return args[cursor];
      }

      if (arg == '--total') {
        total = int.parse(requireValue());
      } else if (arg == '--index') {
        index = int.parse(requireValue());
      } else if (arg == '--root') {
        roots.add(requireValue());
      } else if (arg == '--skip') {
        skips.add(requireValue());
      } else if (arg == '-h' || arg == '--help') {
        _printUsage();
        exit(0);
      } else {
        throw FormatException('Unknown argument: $arg');
      }
    }

    if (total == null || index == null) {
      throw const FormatException('Both --total and --index are required');
    }
    if (total < 1) {
      throw FormatException('--total must be at least 1, got $total');
    }
    if (index < 0 || index >= total) {
      throw FormatException('--index must be in [0, $total), got $index');
    }

    return ShardArgs(
      total: total,
      index: index,
      roots: roots.isEmpty ? const <String>['test'] : roots,
      skips: skips,
    );
  }
}

void main(List<String> args) {
  ShardArgs parsed;
  try {
    parsed = ShardArgs.parse(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _printUsage();
    exitCode = 64;
    return;
  }

  final files = selectShard(
    collectTestFiles(parsed.roots, parsed.skips),
    total: parsed.total,
    index: parsed.index,
  );

  if (files.isEmpty) {
    stderr.writeln(
      'Shard ${parsed.index} of ${parsed.total} matched no test files under '
      '${parsed.roots.join(', ')}.',
    );
    exitCode = 1;
    return;
  }

  for (final file in files) {
    stdout.writeln(file);
  }
}

/// Collects `*_test.dart` under [roots], sorted so shard membership is stable
/// across machines and operating systems.
List<String> collectTestFiles(List<String> roots, List<String> skips) {
  final files = <String>[];
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      continue;
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      if (!path.endsWith('_test.dart')) {
        continue;
      }
      if (skips.any((skip) => path.startsWith(skip.replaceAll(r'\', '/')))) {
        continue;
      }
      files.add(path);
    }
  }
  files.sort();
  return files;
}

/// Packs files into [total] shards by descending size.
///
/// Round-robin over a path-sorted list still clustered large widget and
/// provider suites onto later shards (CI shard 3 was ~70s slower than shard 1).
/// Contiguous slices are worse: they put whole directories on one runner.
/// Size is a stable compile-cost proxy that does not depend on prior timings.
List<String> selectShard(
  List<String> files, {
  required int total,
  required int index,
  int Function(String path)? sizeOf,
}) {
  return partitionShards(files, total: total, sizeOf: sizeOf)[index];
}

/// Returns every shard as a path-sorted list. [sizeOf] is injectable so tests
/// can pack fake paths without touching the filesystem.
List<List<String>> partitionShards(
  List<String> files, {
  required int total,
  int Function(String path)? sizeOf,
}) {
  final sizeFor = sizeOf ?? (String path) => File(path).lengthSync();
  final sizes = <String, int>{for (final file in files) file: sizeFor(file)};
  final ordered = [...files]
    ..sort((left, right) {
      final bySize = sizes[right]!.compareTo(sizes[left]!);
      if (bySize != 0) {
        return bySize;
      }
      return left.compareTo(right);
    });

  final shards = List<List<String>>.generate(total, (_) => <String>[]);
  final loads = List<int>.filled(total, 0);
  for (final file in ordered) {
    var best = 0;
    for (var cursor = 1; cursor < total; cursor += 1) {
      if (loads[cursor] < loads[best]) {
        best = cursor;
      }
    }
    shards[best].add(file);
    loads[best] += sizes[file]!;
  }
  for (final shard in shards) {
    shard.sort();
  }
  return shards;
}

void _printUsage() {
  stdout.writeln(
    'Usage: dart run tool/ci/select_test_shard.dart '
    '--total N --index I [--root test] [--skip test/golden]',
  );
}
