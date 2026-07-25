/// Rendering of resource readings, including the "no reading" case.
///
/// An absent metric is a dash, never a zero: a remote or unmeasured row reading
/// "0%" would claim it is idle, which is a different statement from "we cannot
/// see it from here".
library;

const String resourceAbsentReading = '-';

String formatResourceMemory(int? bytes) {
  if (bytes == null) {
    return resourceAbsentReading;
  }
  const kilobyte = 1024;
  const megabyte = kilobyte * 1024;
  const gigabyte = megabyte * 1024;
  if (bytes < megabyte) {
    return '${(bytes / kilobyte).round()} KB';
  }
  if (bytes < gigabyte) {
    return '${(bytes / megabyte).toStringAsFixed(1)} MB';
  }
  return '${(bytes / gigabyte).toStringAsFixed(2)} GB';
}

String formatResourceCpu(double? percent) {
  if (percent == null) {
    return resourceAbsentReading;
  }
  return '${percent.toStringAsFixed(1)}%';
}

/// Kept short on purpose: it shares one status-bar-width row with the CPU and
/// memory totals, and a longer phrase pushes that row into an overflow.
String formatResourceShareOfSystem(int? bytes, int totalBytes) {
  if (bytes == null || totalBytes <= 0) {
    return resourceAbsentReading;
  }
  return '${(bytes * 100 / totalBytes).toStringAsFixed(0)}% of RAM';
}
