import 'package:alera_mobile/src/features/runtime/infra/relay_wire.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large relay envelopes round trip through fragments', () {
    final payload = List<int>.filled(70 * 1024, 7);
    final fragments = fragmentRelayPayload(payload);
    final reassembler = RelayFragmentReassembler();
    List<int>? complete;

    for (final fragment in fragments) {
      complete = reassembler.accept(fragment);
    }

    expect(fragments, hasLength(2));
    expect(fragments.first.sublist(0, 13), <int>[
      0x41,
      0x4c,
      0x52,
      0x46,
      0x01,
      0,
      1,
      0x18,
      0,
      0,
      0,
      0,
      0,
    ]);
    expect(complete, payload);
  });

  test('relay fragmentation rejects oversized and out-of-order input', () {
    expect(
      () =>
          fragmentRelayPayload(List<int>.filled(maxRelayEnvelopeBytes + 1, 0)),
      throwsFormatException,
    );
    final fragments = fragmentRelayPayload(List<int>.filled(70 * 1024, 7));
    final reassembler = RelayFragmentReassembler();

    expect(() => reassembler.accept(fragments[1]), throwsFormatException);
  });
}
