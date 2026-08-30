import 'package:alera_configuration/alera_configuration.dart';
import 'package:test/test.dart';

void main() {
  test(
    'canonical JSON sorts nested maps and preserves list order and nulls',
    () {
      final result = canonicalJson({
        'z': [
          null,
          {'b': 2, 'a': 1},
        ],
        'a': false,
      }) as Map;
      expect(result.keys, ['a', 'z']);
      expect(result['z'], [
        null,
        {'a': 1, 'b': 2},
      ]);
      expect(((result['z'] as List).last as Map).keys, ['a', 'b']);
      expect(canonicalJson('plain'), 'plain');
      expect(canonicalJson(null), isNull);
    },
  );

  test('invalid map keys keep failing instead of becoming empty JSON', () {
    expect(() => canonicalJson({1: 'invalid'}), throwsA(isA<TypeError>()));
    expect(() => jsonMap({1: 'invalid'}), throwsA(isA<TypeError>()));
    expect(jsonMap(['not a map']), isEmpty);
  });

  test('document validation preserves schema and block failures', () {
    expect(
      () => ConfigurationDocument({'schemaVersion': 2}),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Update Alera to read this configuration format.',
        ),
      ),
    );
    expect(
      () => ConfigurationDocument({
        ...ConfigurationDocument.empty().json,
        'desktop': [],
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Invalid desktop configuration.',
        ),
      ),
    );
  });
}
