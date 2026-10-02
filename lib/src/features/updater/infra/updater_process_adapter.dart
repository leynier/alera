import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_updater/desktop_updater.dart' as updater;

import '../../../shared/infra/files/posix_file_mode.dart';
import '../../../shared/infra/process/process_runner.dart';

/// macOS staging tools return small plist or diagnostic text. Keep their
/// capture small so decoding remains bounded while native process handles
/// provide cancellation and reaping.
class UpdaterProcessAdapter({
  required final ProcessRunner processRunner,
  final int maxOutputBytes = 1024 * 1024,
  // Archive tools can remain silent while copying large applications.
  final Duration timeout = const Duration(minutes: 15),
}) {
  this {
    if (maxOutputBytes <= 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
  }

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    updater.UpdateCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final process = await processRunner.start(executable, arguments);
    final result = Completer<ProcessResult>();
    final stdout = BytesBuilder(copy: false);
    final stderr = BytesBuilder(copy: false);
    var length = 0;
    var stdoutDone = false;
    var stderrDone = false;
    var finished = false;
    var failed = false;
    int? exitCode;

    void fail(Object error, [StackTrace? stackTrace]) {
      if (result.isCompleted) {
        return;
      }
      failed = true;
      try {
        process.kill();
      } on Object {
        // Preserve the original staging failure if the handle already exited.
      }
      result.completeError(error, stackTrace ?? StackTrace.current);
    }

    void completeIfReady() {
      if (!result.isCompleted && stdoutDone && stderrDone && exitCode != null) {
        if (cancellationToken?.isCancelled ?? false) {
          fail(const updater.UpdateCancelledException());
          return;
        }
        result.complete(
          ProcessResult(
            process.pid,
            exitCode!,
            utf8.decode(stdout.takeBytes(), allowMalformed: true),
            utf8.decode(stderr.takeBytes(), allowMalformed: true),
          ),
        );
      }
    }

    void add(BytesBuilder target, List<int> chunk) {
      if (result.isCompleted) {
        return;
      }
      if (chunk.length > maxOutputBytes - length) {
        fail(
          ProcessException(
            executable,
            arguments,
            'Update command output exceeds $maxOutputBytes bytes.',
          ),
        );
        return;
      }
      length += chunk.length;
      target.add(chunk);
    }

    final stdoutSubscription = process.stdout.listen(
      (chunk) => add(stdout, chunk),
      onError: fail,
      onDone: () {
        stdoutDone = true;
        completeIfReady();
      },
    );
    final stderrSubscription = process.stderr.listen(
      (chunk) => add(stderr, chunk),
      onError: fail,
      onDone: () {
        stderrDone = true;
        completeIfReady();
      },
    );
    unawaited(
      process.exitCode.then<void>((code) {
        exitCode = code;
        completeIfReady();
      }, onError: fail),
    );
    final timer = Timer(
      timeout,
      () => fail(TimeoutException('Update command timed out.', timeout)),
    );
    final token = cancellationToken;
    if (token != null) {
      unawaited(
        token.whenCancelled.then((_) {
          if (!finished) {
            fail(const updater.UpdateCancelledException());
          }
        }),
      );
    }
    try {
      process.stdinClose();
      token?.throwIfCancelled();
      final output = await result.future;
      token?.throwIfCancelled();
      return output;
    } on Object catch (error, stackTrace) {
      if (!result.isCompleted) {
        fail(error, stackTrace);
      }
      // Mark the error future observed even if cancellation won before await.
      unawaited(result.future.then<void>((_) {}, onError: (Object _) {}));
      rethrow;
    } finally {
      finished = true;
      timer.cancel();
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      if (failed) {
        // Staging cleanup must wait until the command can no longer mutate
        // its owned files or mountpoint.
        try {
          await process.exitCode;
        } on Object {
          // The native runner surfaces bridge failure and owns kill/reap.
        }
      }
    }
  }
}

Future<void> applyUpdaterFileModes(
  int mode,
  List<String> paths,
  updater.UpdateCancellationToken? cancellationToken,
) async {
  for (var index = 0; index < paths.length; index++) {
    cancellationToken?.throwIfCancelled();
    final path = paths[index];
    if (!setPosixFileMode(path, mode)) {
      throw FileSystemException('Failed to apply update file mode.', path);
    }
    if ((index + 1) % 64 == 0) {
      await Future.pause(Duration.zero);
    }
  }
}
