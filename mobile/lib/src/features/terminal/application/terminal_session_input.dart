part of 'terminal_session_controller.dart';

extension TerminalSessionInput on TerminalSessionController {
  /// Raw accessory/direct keys are never pasted or deferred.
  Future<void> write(List<int> bytes) => _runAttachedOperation(
    (client, sessionId) => client.writeTerminal(sessionId, bytes),
  );

  /// Explicit paste never submits and brackets only when the text needs it.
  Future<void> pasteText(String text) => _runAttachedOperation((client, id) {
    final delivery = TerminalComposeDelivery.forText(
      text,
      withEnter: false,
      hostSupportsDeferredInput: client.supportsDeferredTerminalInput,
    );
    return client.writeTerminal(
      id,
      delivery.bytes,
      bracketedPaste: delivery.bracketedPaste,
    );
  });

  /// Compose send separates prompt bytes from Enter when the host supports it.
  Future<void> sendComposedText(String text, {required bool withEnter}) =>
      _runAttachedOperation((client, id) {
        final delivery = TerminalComposeDelivery.forText(
          text,
          withEnter: withEnter,
          hostSupportsDeferredInput: client.supportsDeferredTerminalInput,
        );
        return client.writeTerminal(
          id,
          delivery.bytes,
          bracketedPaste: delivery.bracketedPaste,
          deferredEnter: delivery.deferredEnter,
        );
      });

  Future<void> resize(int cols, int rows) async {
    if (cols <= 0 || rows <= 0) {
      return;
    }
    _cols = cols;
    _rows = rows;
    await _runAttachedOperation(
      (client, sessionId) => client.resizeTerminal(sessionId, cols, rows),
    );
  }
}
