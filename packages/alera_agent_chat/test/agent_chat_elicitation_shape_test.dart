import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatElicitation _elicitation(Map<String, Object?> json) =>
    AgentChatElicitation.fromJson(json);

void main() {
  test('every elicitation reads as one shape both apps share', () {
    expect(
      _elicitation(<String, Object?>{
        'mode': 'form',
        'schema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'name': <String, Object?>{'type': 'string'},
            'count': <String, Object?>{'type': 'integer'},
          },
        },
      }).shape,
      AgentChatElicitationShape.form,
    );
    expect(
      _elicitation(<String, Object?>{
        'mode': 'url',
        'url': 'https://example.com/sign-in',
      }).shape,
      AgentChatElicitationShape.link,
    );
    expect(
      _elicitation(<String, Object?>{'mode': 'url'}).shape,
      AgentChatElicitationShape.unsupported,
    );
    expect(
      _elicitation(<String, Object?>{
        'mode': 'form',
        'message': 'Allow the tool?',
        'schema': <String, Object?>{'type': 'object'},
      }).shape,
      AgentChatElicitationShape.confirmation,
    );
    expect(
      _elicitation(<String, Object?>{
        'mode': 'form',
        'schema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'tags': <String, Object?>{'type': 'array'},
          },
        },
      }).shape,
      AgentChatElicitationShape.unsupported,
    );
  });
}
