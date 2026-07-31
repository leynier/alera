import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('Flutter terminal character input encoding', () {
    var outputBytes = 0;
    final terminal = Terminal(
      onOutput: (output) {
        outputBytes += output.length;
      },
    );
    for (var index = 0; index < 5000; index++) {
      terminal.textInput('a');
    }

    const batchSize = 100;
    final samples = <double>[];
    for (var sample = 0; sample < 2000; sample++) {
      final watch = Stopwatch()..start();
      for (var index = 0; index < batchSize; index++) {
        terminal.textInput('a');
      }
      watch.stop();
      samples.add(watch.elapsedMicroseconds / batchSize);
    }
    samples.sort();
    final p95Micros =
        samples[(samples.length * 95 ~/ 100).clamp(0, samples.length - 1)];

    print('=== Flutter terminal input encoding ===');
    print('  char input p95 ${p95Micros.toStringAsFixed(3)} µs');
    print('  observed output bytes $outputBytes');
    expect(outputBytes, 205000);
  });
}
