import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Dart has no octal literals, so the POSIX modes are spelled in hex.
const int posixExecutableFileMode = 0x1ED; // 0o755
const int posixPrivateFileMode = 0x180; // 0o600

/// `mode_t` is 16 bits on Darwin and 32 on Linux. Passing 32 is safe for both:
/// the callee reads the low bits, and every mode used here fits in 16.
typedef _ChmodNative = ffi.Int32 Function(
  ffi.Pointer<Utf8> path,
  ffi.Uint32 mode,
);
typedef _ChmodDart = int Function(ffi.Pointer<Utf8> path, int mode);

/// Resolved from the running process rather than a named library, because the
/// libc file name differs between glibc, musl and macOS.
final ffi.DynamicLibrary _libc = ffi.DynamicLibrary.process();
final _ChmodDart _chmod = _libc.lookupFunction<_ChmodNative, _ChmodDart>(
  'chmod',
);

/// Applies [mode] to [path], reporting whether the call succeeded.
///
/// This is a syscall rather than a `chmod` process on purpose. A `dart:io`
/// child, however short-lived, wakes the VM's reaper thread, which waits on
/// *any* child of the process and discards the pids it does not own after
/// reaping them. The next `waitpid` from the Rust side then fails with ECHILD,
/// which surfaced as "failed to run ...: No child processes (os error 10)".
bool setPosixFileMode(String path, int mode) {
  // Checked before the lazy `final`s are touched: Windows names the symbol
  // `_chmod`, so resolving it there would throw instead of returning false.
  if (Platform.isWindows) {
    return false;
  }
  final nativePath = path.toNativeUtf8();
  try {
    return _chmod(nativePath, mode) == 0;
  } finally {
    malloc.free(nativePath);
  }
}
