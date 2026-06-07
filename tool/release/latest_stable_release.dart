import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final tags = args.isEmpty
      ? await stdin
            .transform(SystemEncoding().decoder)
            .transform(const LineSplitter())
            .toList()
      : args;
  stdout.writeln(latestStableRelease(tags));
}

String latestStableRelease(Iterable<String> tags) {
  final versions = <_Version>[];
  for (final tag in tags) {
    final version = _Version.tryParseTag(tag.trim());
    if (version != null) {
      versions.add(version);
    }
  }
  if (versions.isEmpty) {
    return '0.1.0';
  }
  versions.sort();
  return versions.last.toString();
}

final class _Version implements Comparable<_Version> {
  const _Version(this.major, this.minor, this.patch);

  static _Version? tryParseTag(String tag) {
    final match = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$').firstMatch(tag);
    if (match == null) {
      return null;
    }
    return _Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(_Version other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) {
      return majorOrder;
    }
    final minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) {
      return minorOrder;
    }
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}
