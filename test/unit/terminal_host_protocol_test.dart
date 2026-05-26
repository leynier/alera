import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes and decodes terminal host byte payloads', () {
    final encoded = encodeTerminalHostBytes(<int>[1, 2, 3]);

    expect(decodeTerminalHostBytes(encoded), <int>[1, 2, 3]);
    expect(decodeTerminalHostBytes(''), isEmpty);
    expect(decodeTerminalHostBytes(42), isEmpty);
  });

  test('normalizes terminal host maps and rejects invalid values', () {
    final typed = <String, Object?>{'a': 1};
    final generic = <Object?, Object?>{'b': 2};

    expect(asTerminalHostMap(typed, 'typed'), same(typed));
    expect(asTerminalHostMap(generic, 'generic'), <String, Object?>{'b': 2});
    expect(
      () => asTerminalHostMap('bad', 'payload'),
      throwsA(isA<FormatException>()),
    );
  });

  test('normalizes terminal host string lists and maps', () {
    expect(asTerminalHostStringList(null), isEmpty);
    expect(asTerminalHostStringList(<Object?>['a', 1, 'b']), <String>[
      'a',
      'b',
    ]);

    expect(asTerminalHostStringMap(null), isEmpty);
    expect(
      asTerminalHostStringMap(<Object?, Object?>{
        'TERM': 'xterm-256color',
        'ignored': 1,
        2: 'ignored',
      }),
      <String, String>{'TERM': 'xterm-256color'},
    );
  });

  test('parses terminal launch payloads', () {
    final launch = TerminalHostLaunch.fromJson(<String, Object?>{
      'shell': '/bin/zsh',
      'arguments': <Object?>['-l', 1, '-i'],
      'environment': <Object?, Object?>{'TERM': 'xterm-256color', 1: 'bad'},
      'setupCommand': 'ignored by the host protocol',
    });

    expect(launch.label, 'shell');
    expect(launch.shell, '/bin/zsh');
    expect(launch.arguments, <String>['-l', '-i']);
    expect(launch.environment, <String, String>{'TERM': 'xterm-256color'});
    expect(launch.toJson(), <String, Object?>{
      'label': 'shell',
      'shell': '/bin/zsh',
      'arguments': <String>['-l', '-i'],
      'environment': <String, String>{'TERM': 'xterm-256color'},
    });

    expect(
      () => TerminalHostLaunch.fromJson(const <String, Object?>{}),
      throwsA(isA<FormatException>()),
    );
  });

  group('TerminalHostConfig', () {
    test('defaults round-trip through json', () {
      final restored = TerminalHostConfig.fromJson(
        TerminalHostConfig.defaults.toJson(),
      );

      expect(restored.emptyShutdownDelaySeconds, 30);
      expect(restored.detachedSessionShutdownDelaySeconds, 60 * 60);
      expect(restored.scrollbackBytes, 10 * 1000 * 1000);
    });

    test('rejects non-positive values', () {
      expect(
        () => TerminalHostConfig.fromJson(<String, Object?>{
          'emptyShutdownDelaySeconds': 0,
          'detachedSessionShutdownDelaySeconds': 1,
          'scrollbackBytes': 1,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
