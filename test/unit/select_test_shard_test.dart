import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/select_test_shard.dart';

void main() {
  test('size-weighted packing keeps every file in exactly one shard', () {
    const files = <String>[
      'test/widget/large.dart',
      'test/widget/medium.dart',
      'test/unit/small.dart',
      'test/unit/tiny.dart',
      'test/unit/other.dart',
    ];
    const sizes = <String, int>{
      'test/widget/large.dart': 40000,
      'test/widget/medium.dart': 20000,
      'test/unit/small.dart': 5000,
      'test/unit/tiny.dart': 1000,
      'test/unit/other.dart': 8000,
    };

    final shards = partitionShards(
      files,
      total: 2,
      sizeOf: (path) => sizes[path]!,
    );

    expect(shards, hasLength(2));
    expect({...shards[0], ...shards[1]}, unorderedEquals(files));
    expect(shards[0].toSet().intersection(shards[1].toSet()), isEmpty);
    expect(
      selectShard(files, total: 2, index: 0, sizeOf: (path) => sizes[path]!),
      shards[0],
    );
  });

  test(
    'size-weighted packing is more balanced than round-robin on real tests',
    () {
      final files = collectTestFiles(
        const <String>['test'],
        const <String>['test/golden'],
      );
      expect(files, isNotEmpty);

      final shards = partitionShards(files, total: 4);
      final loads = [
        for (final shard in shards)
          shard.fold<int>(0, (sum, path) => sum + File(path).lengthSync()),
      ];

      final roundRobin = List<int>.filled(4, 0);
      for (var index = 0; index < files.length; index += 1) {
        roundRobin[index % 4] += File(files[index]).lengthSync();
      }

      final packedSpread =
          loads.reduce((a, b) => a > b ? a : b) -
          loads.reduce((a, b) => a < b ? a : b);
      final roundRobinSpread =
          roundRobin.reduce((a, b) => a > b ? a : b) -
          roundRobin.reduce((a, b) => a < b ? a : b);
      expect(packedSpread, lessThan(roundRobinSpread));
      expect(shards.every((shard) => shard.isNotEmpty), isTrue);
    },
  );
}
