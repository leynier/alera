import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  var initialized = false;
  var activeThreadId = 'thr_fake';
  var activeTurnId = 'turn_fake';

  void emitCompletedTurn({
    required String status,
    String itemStatus = 'completed',
  }) {
    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'item/completed',
      'params': <String, dynamic>{
        'item': <String, dynamic>{
          'id': 'item_cmd_1',
          'type': 'commandExecution',
          'command': 'git status',
          'cwd': '.',
          'status': itemStatus,
          'aggregatedOutput': status == 'completed' ? 'ok' : '',
        },
      },
    });

    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'turn/completed',
      'params': <String, dynamic>{
        'turn': <String, dynamic>{
          'id': activeTurnId,
          'threadId': activeThreadId,
          'status': status,
          'items': <Object>[],
          'error': null,
        },
      },
    });
  }

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) {
      continue;
    }

    final message = jsonDecode(line) as Map<String, dynamic>;
    final method = message['method'] as String?;
    final id = message['id'];

    if (method == 'initialize') {
      _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'serverInfo': <String, dynamic>{
            'name': 'fake-codex-app-server',
            'version': '0.1.0',
          },
        },
      });
      continue;
    }

    if (method == 'initialized') {
      initialized = true;
      continue;
    }

    if (!initialized) {
      _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, dynamic>{
          'code': -32002,
          'message': 'Not initialized',
        },
      });
      continue;
    }

    if (method == 'thread/start') {
      final params =
          (message['params'] as Map<String, dynamic>? ??
                  const <String, dynamic>{})
              .cast<String, dynamic>();
      if (params['approvalPolicy'] != 'never') {
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32010,
            'message': 'thread/start expected approvalPolicy=never',
          },
        });
        continue;
      }

      _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, dynamic>{
            'id': activeThreadId,
            'preview': '',
            'modelProvider': 'openai',
            'createdAt': 1730910000,
          },
        },
      });
      _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'thread/started',
        'params': <String, dynamic>{
          'thread': <String, dynamic>{'id': activeThreadId},
        },
      });
      continue;
    }

    if (method == 'turn/start') {
      final params = (message['params'] as Map<String, dynamic>)
          .cast<String, dynamic>();

      if (params.containsKey('collaborationMode')) {
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32011,
            'message': 'turn/start must not include collaborationMode',
          },
        });
        continue;
      }

      if (params['approvalPolicy'] != 'never') {
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'error': <String, dynamic>{
            'code': -32012,
            'message': 'turn/start expected approvalPolicy=never',
          },
        });
        continue;
      }

      activeThreadId = (params['threadId'] ?? activeThreadId).toString();
      activeTurnId = 'turn_${DateTime.now().millisecondsSinceEpoch}';

      _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'turn': <String, dynamic>{
            'id': activeTurnId,
            'threadId': activeThreadId,
            'status': 'inProgress',
            'items': <Object>[],
          },
        },
      });

      _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/started',
        'params': <String, dynamic>{
          'turn': <String, dynamic>{
            'id': activeTurnId,
            'threadId': activeThreadId,
            'status': 'inProgress',
          },
        },
      });

      final input = (params['input'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<dynamic, dynamic>>();
      final prompt = input.isEmpty
          ? ''
          : (input.first['text'] ?? '').toString().toLowerCase();

      if (prompt.contains('trigger_approval')) {
        _write(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 900,
          'method': 'item/commandExecution/requestApproval',
          'params': <String, dynamic>{
            'threadId': activeThreadId,
            'turnId': activeTurnId,
            'itemId': 'item_cmd_1',
            'reason': 'needs approval',
            'command': 'git status',
            'cwd': params['cwd'] ?? '.',
            'commandActions': <String>['filesystemRead', 'processExecution'],
          },
        });
      } else {
        emitCompletedTurn(status: 'completed');
      }
      continue;
    }

    if (id == 900 && message.containsKey('result')) {
      final result = message['result'] as Map<String, dynamic>;
      final decision = (result['decision'] ?? '').toString();
      if (decision == 'accept') {
        emitCompletedTurn(status: 'completed');
      } else {
        emitCompletedTurn(status: 'interrupted', itemStatus: 'declined');
      }
      continue;
    }

    if (method == 'thread/resume') {
      _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{
          'thread': <String, dynamic>{
            'id': (message['params'] as Map<String, dynamic>)['threadId'],
            'preview': '',
            'modelProvider': 'openai',
            'createdAt': 1730910000,
          },
        },
      });
      continue;
    }

    if (method == 'turn/interrupt') {
      _write(<String, dynamic>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, dynamic>{},
      });
      continue;
    }

    _write(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': <String, dynamic>{},
    });
  }
}

void _write(Map<String, dynamic> payload) {
  stdout.writeln(jsonEncode(payload));
}
