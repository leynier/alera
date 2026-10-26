import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_request_cards.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatRequest _request(Map<String, Object?> json) =>
    AgentChatRequest.fromJson(<String, Object?>{'requestId': 'req-1', ...json});

Widget _host(Widget card) {
  return MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: card,
      ),
    ),
  );
}

List<String?> _actionLabels(WidgetTester tester) => <String?>[
  for (final text in tester.widgetList<Text>(
    find.descendant(of: find.byType(Wrap), matching: find.byType(Text)),
  ))
    text.data,
];

void main() {
  group('AgentChatApprovalCard', () {
    testWidgets('offers the runtime decisions in order and reports them', (
      tester,
    ) async {
      final decisions = <AgentChatApprovalDecision>[];
      final expiresAt = DateTime(2026, 10, 12, 14, 5);
      final request = _request(<String, Object?>{
        'kind': 'commandExecutionApproval',
        'command': 'pnpm test --filter api',
        'cwd': '/work/alera',
        'detail': 'Runs the API test suite.',
        'decisions': <Object?>[
          'accept',
          'acceptForSession',
          'decline',
          'cancel',
        ],
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      });
      await tester.pumpWidget(
        _host(
          AgentChatApprovalCard(
            request: request,
            responding: false,
            enabled: true,
            onDecision: decisions.add,
          ),
        ),
      );

      expect(find.text('Run Command?'), findsOneWidget);
      expect(find.text('pnpm test --filter api'), findsOneWidget);
      expect(find.text('Directory'), findsOneWidget);
      expect(find.text('/work/alera'), findsOneWidget);
      expect(find.text('Runs the API test suite.'), findsOneWidget);
      expect(find.text('Expires at 14:05'), findsOneWidget);
      // The first decision and Decline are buttons; the rest wait in the
      // overflow, each group in the runtime's order.
      expect(_actionLabels(tester), <String>['Allow Once', 'Decline']);
      expect(find.widgetWithText(FilledButton, 'Allow Once'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Decline'), findsOneWidget);
      expect(find.text('Allow For Session'), findsNothing);

      await tester.tap(find.byTooltip('More Decisions'));
      await tester.pumpAndSettle();
      final overflow = <String?>[
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(AleraMenuItem),
            matching: find.byType(Text),
          ),
        ))
          text.data,
      ];
      expect(overflow, <String>['Allow For Session', 'Cancel Turn']);
      await tester.tap(find.text('Allow For Session'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More Decisions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel Turn'));
      await tester.pumpAndSettle();
      expect(decisions, <AgentChatApprovalDecision>[
        AgentChatApprovalDecision.acceptForSession,
        AgentChatApprovalDecision.cancel,
      ]);
    });

    testWidgets('falls back to Allow Once and Decline without decisions', (
      tester,
    ) async {
      final decisions = <AgentChatApprovalDecision>[];
      final request = _request(<String, Object?>{
        'kind': 'fileChangeApproval',
        'title': 'Rewrite the lockfile?',
        'path': 'pnpm-lock.yaml',
      });
      await tester.pumpWidget(
        _host(
          AgentChatApprovalCard(
            request: request,
            responding: false,
            enabled: true,
            onDecision: decisions.add,
          ),
        ),
      );

      expect(find.text('Rewrite the lockfile?'), findsOneWidget);
      expect(find.text('Apply File Changes?'), findsNothing);
      expect(find.text('Path'), findsOneWidget);
      expect(find.textContaining('Expires at'), findsNothing);
      expect(_actionLabels(tester), <String>['Allow Once', 'Decline']);

      await tester.tap(find.text('Decline'));
      expect(decisions, <AgentChatApprovalDecision>[
        AgentChatApprovalDecision.decline,
      ]);
    });

    testWidgets('declines with feedback and explains a full access ask', (
      tester,
    ) async {
      final feedback = <String>[];
      final request = _request(<String, Object?>{
        'kind': 'permissionApproval',
        'title': 'Run git push?',
        'decisions': <Object?>['accept', 'decline', 'cancel'],
        'supportsFeedback': true,
        'fullAccessOverride': 'ask_rule',
      });
      await tester.pumpWidget(
        _host(
          AgentChatApprovalCard(
            request: request,
            responding: false,
            enabled: true,
            onDecision: (_) {},
            onDeclineWithFeedback: feedback.add,
          ),
        ),
      );

      expect(
        find.widgetWithText(
          AleraInlineNotice,
          agentChatFullAccessOverrideMessage(.askRule),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('agent-chat-decline-feedback')),
      );
      await tester.pumpAndSettle();
      final send = find.byKey(
        const ValueKey<String>('agentChatDeclineFeedbackSend'),
      );
      expect(tester.widget<FilledButton>(send).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey<String>('agentChatDeclineFeedback')).last,
        '  Push to a branch instead.  ',
      );
      await tester.pump();
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(feedback, <String>['Push to a branch instead.']);
    });

    testWidgets('offers no feedback when the provider takes none', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AgentChatApprovalCard(
            request: _request(<String, Object?>{
              'kind': 'commandExecutionApproval',
              'decisions': <Object?>['accept', 'decline'],
            }),
            responding: false,
            enabled: true,
            onDecision: (_) {},
            onDeclineWithFeedback: (_) {},
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('agent-chat-decline-feedback')),
        findsNothing,
      );
      expect(find.byType(AleraInlineNotice), findsNothing);
    });

    testWidgets('disables its decisions while responding', (tester) async {
      final decisions = <AgentChatApprovalDecision>[];
      final request = _request(<String, Object?>{
        'kind': 'fileReadApproval',
        'path': '.env',
      });
      await tester.pumpWidget(
        _host(
          AgentChatApprovalCard(
            request: request,
            responding: true,
            enabled: true,
            onDecision: decisions.add,
          ),
        ),
      );

      expect(find.text('Read File?'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Allow Once'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Decline'));
      expect(decisions, isEmpty);
    });
  });

  group('AgentChatElicitationCard', () {
    late List<(AgentChatElicitationAction, Map<String, Object?>?)> responses;

    setUp(() {
      responses = <(AgentChatElicitationAction, Map<String, Object?>?)>[];
    });

    Widget card(
      Map<String, Object?> elicitation, {
      ValueChanged<String>? onOpenUrl,
    }) {
      return _host(
        AgentChatElicitationCard(
          request: _request(<String, Object?>{
            'kind': 'mcpElicitationApproval',
            'elicitation': elicitation,
          }),
          responding: false,
          enabled: true,
          onOpenUrl: onOpenUrl,
          onRespond: (action, content) => responses.add((action, content)),
        ),
      );
    }

    testWidgets('accepts only a valid form and sends typed values', (
      tester,
    ) async {
      await tester.pumpWidget(
        card(<String, Object?>{
          'mode': 'form',
          'message': 'Configure the deploy.',
          'schema': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'name': <String, Object?>{'type': 'string', 'title': 'Name'},
              'replicas': <String, Object?>{
                'type': 'integer',
                'title': 'Replicas',
              },
              'ratio': <String, Object?>{
                'type': 'number',
                'title': 'Ratio',
                'description': 'Share of traffic, between 0 and 1.',
              },
              'verbose': <String, Object?>{
                'type': 'boolean',
                'title': 'Verbose',
                'default': true,
              },
              'note': <String, Object?>{'type': 'string'},
            },
            'required': <Object?>['name', 'replicas'],
          },
        }),
      );

      FilledButton accept() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Accept'),
      );
      expect(find.text('Configure the deploy.'), findsOneWidget);
      expect(find.text('Share of traffic, between 0 and 1.'), findsOneWidget);
      expect(find.text('This field is required.'), findsNothing);
      expect(accept().onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Name *'), 'api');
      await tester.enterText(
        find.widgetWithText(TextField, 'Replicas *'),
        'two',
      );
      await tester.pump();
      expect(find.text('Enter a whole number.'), findsOneWidget);
      expect(accept().onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Replicas *'), '3');
      await tester.enterText(find.widgetWithText(TextField, 'Ratio'), '0.x');
      await tester.pump();
      expect(find.text('Enter a whole number.'), findsNothing);
      expect(find.text('Enter a number.'), findsOneWidget);
      expect(accept().onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Name *'), ' ');
      await tester.enterText(find.widgetWithText(TextField, 'Ratio'), '0.25');
      await tester.pump();
      expect(find.text('This field is required.'), findsOneWidget);
      expect(accept().onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Name *'), 'api');
      await tester.tap(find.text('Verbose'));
      await tester.pump();
      expect(accept().onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      expect(responses, hasLength(1));
      final (action, content) = responses.single;
      expect(action, AgentChatElicitationAction.accept);
      expect(content, <String, Object?>{
        'name': 'api',
        'replicas': 3,
        'ratio': 0.25,
        'verbose': false,
      });
      expect(content!['replicas'], isA<int>());
      expect(content['ratio'], isA<double>());
    });

    testWidgets('an unsupported form explains itself and only refuses', (
      tester,
    ) async {
      await tester.pumpWidget(
        card(<String, Object?>{
          'mode': 'form',
          'message': 'Pick the services.',
          'schema': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'services': <String, Object?>{'type': 'array'},
            },
          },
        }),
      );

      expect(find.byType(AleraInlineNotice), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(_actionLabels(tester), <String>['Decline', 'Cancel']);

      await tester.tap(find.text('Cancel'));
      await tester.tap(find.text('Decline'));
      expect(responses, <(AgentChatElicitationAction, Map<String, Object?>?)>[
        (AgentChatElicitationAction.cancel, null),
        (AgentChatElicitationAction.decline, null),
      ]);
    });

    testWidgets(
      'a URL elicitation opens the link and accepts without content',
      (tester) async {
        final opened = <String>[];
        await tester.pumpWidget(
          card(<String, Object?>{
            'mode': 'url',
            'message': 'Sign in to the issue tracker.',
            'url': 'https://tracker.example.com/authorize',
          }, onOpenUrl: opened.add),
        );

        expect(
          find.text('https://tracker.example.com/authorize'),
          findsOneWidget,
        );
        expect(find.text('Sign in to the issue tracker.'), findsOneWidget);
        expect(_actionLabels(tester), <String>['Accept', 'Decline', 'Cancel']);

        await tester.tap(find.text('Open Link'));
        expect(opened, <String>['https://tracker.example.com/authorize']);
        expect(responses, isEmpty);

        await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
        expect(responses, <(AgentChatElicitationAction, Map<String, Object?>?)>[
          (AgentChatElicitationAction.accept, null),
        ]);
      },
    );

    testWidgets('a link that is not a web address cannot be opened', (
      tester,
    ) async {
      await tester.pumpWidget(
        card(<String, Object?>{
          'mode': 'url',
          'url': 'file:///etc/hosts',
        }, onOpenUrl: (_) {}),
      );

      expect(find.text('file:///etc/hosts'), findsOneWidget);
      expect(find.text('Open Link'), findsNothing);
    });

    testWidgets('a form without fields is a confirmation', (tester) async {
      await tester.pumpWidget(
        card(<String, Object?>{
          'mode': 'form',
          'message': 'Continue with the migration?',
          'schema': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
        }),
      );

      expect(find.byType(AleraInlineNotice), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      expect(responses, <(AgentChatElicitationAction, Map<String, Object?>?)>[
        (AgentChatElicitationAction.accept, const <String, Object?>{}),
      ]);
    });
  });

  group('AgentChatUnsupportedRequestCard', () {
    testWidgets('explains the request and offers only listed decisions', (
      tester,
    ) async {
      final decisions = <AgentChatApprovalDecision>[];
      await tester.pumpWidget(
        _host(
          AgentChatUnsupportedRequestCard(
            request: _request(<String, Object?>{
              'kind': 'dynamicToolCall',
              'decisions': <Object?>['cancel'],
            }),
            responding: false,
            enabled: true,
            onDecision: decisions.add,
          ),
        ),
      );

      expect(find.text('The Agent Is Waiting'), findsOneWidget);
      expect(find.textContaining('Alera cannot answer'), findsOneWidget);
      expect(_actionLabels(tester), <String>['Cancel Turn']);
      await tester.tap(find.text('Cancel Turn'));
      expect(decisions, <AgentChatApprovalDecision>[
        AgentChatApprovalDecision.cancel,
      ]);

      await tester.pumpWidget(
        _host(
          AgentChatUnsupportedRequestCard(
            request: _request(<String, Object?>{
              'kind': 'authTokensRefresh',
              'title': 'Refresh credentials',
            }),
            responding: false,
            enabled: true,
            onDecision: decisions.add,
          ),
        ),
      );
      expect(find.text('Refresh credentials'), findsOneWidget);
      expect(find.byType(Wrap), findsNothing);
    });
  });
}
