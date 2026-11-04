import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

void main() {
  test('file attachments are their own capability', () {
    final both = AgentChatCapabilities.fromJson(<String, Object?>{
      'attachments': true,
      'images': true,
      'files': true,
    });
    expect(both.attachments, isTrue);
    expect(both.images, isTrue);
    expect(both.files, isTrue);

    final imagesOnly = AgentChatCapabilities.fromJson(<String, Object?>{
      'attachments': true,
      'images': true,
    });
    expect(imagesOnly.images, isTrue);
    expect(imagesOnly.files, isFalse);
    expect(const AgentChatCapabilities().files, isFalse);
  });

  test('a session carries the files capability', () {
    final session = AgentChatSession.fromJson(<String, Object?>{
      'status': 'idle',
      'capabilities': <String, Object?>{'attachments': true, 'files': true},
    });
    expect(session.capabilities.files, isTrue);
    expect(session.capabilities.images, isFalse);
  });
}
