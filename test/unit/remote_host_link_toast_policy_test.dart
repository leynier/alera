import 'package:alera/src/features/remote_hosts/application/remote_host_link_toasts.dart';
import 'package:alera/src/features/remote_hosts/domain/host_link.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the first snapshot is silent', () {
    final policy = RemoteHostLinkToastPolicy();
    expect(policy.evaluate(_hosts(const RemoteHostOffline())), isEmpty);
  });

  test('a drop toasts once and a reconnect follows it', () {
    final policy = RemoteHostLinkToastPolicy()
      ..evaluate(_hosts(const RemoteHostConnected()));

    final drop = policy.evaluate(
      _hosts(const RemoteHostOffline(retry: HostLinkRetry(attempt: 1))),
    );
    expect(drop, hasLength(1));
    expect(drop.single.message, 'Build Mac disconnected. Reconnecting…');
    expect(drop.single.tone, RemoteHostToastTone.warning);
    expect(drop.single.long, isTrue);
    expect(drop.single.actionLabel, 'Open Host');

    expect(
      policy.evaluate(
        _hosts(const RemoteHostConnecting(retry: HostLinkRetry(attempt: 2))),
      ),
      isEmpty,
    );

    final back = policy.evaluate(_hosts(const RemoteHostConnected()));
    expect(back.single.message, 'Build Mac reconnected');
    expect(back.single.tone, RemoteHostToastTone.success);
    expect(back.single.actionLabel, isNull);

    expect(policy.evaluate(_hosts(const RemoteHostConnected())), isEmpty);
  });

  test('does not promise a reconnect the runtime will not attempt', () {
    final policy = RemoteHostLinkToastPolicy()
      ..evaluate(_hosts(const RemoteHostConnected()));
    expect(
      policy.evaluate(_hosts(const RemoteHostOffline())).single.message,
      'Build Mac disconnected.',
    );
  });

  test('a connection error toasts the reason', () {
    final policy = RemoteHostLinkToastPolicy()
      ..evaluate(_hosts(const RemoteHostConnected()));
    final toast = policy
        .evaluate(_hosts(const RemoteHostError(detail: 'Permission denied')))
        .single;
    expect(toast.message, 'Build Mac: Permission denied');
    expect(toast.tone, RemoteHostToastTone.error);
  });

  test('a retrying connect after a drop counts as the drop', () {
    final policy = RemoteHostLinkToastPolicy()
      ..evaluate(_hosts(const RemoteHostConnected()));
    expect(
      policy.evaluate(
        _hosts(const RemoteHostConnecting(retry: HostLinkRetry(attempt: 1))),
      ),
      hasLength(1),
    );
    expect(policy.evaluate(_hosts(const RemoteHostOffline())), isEmpty);
  });

  test('the user Disconnect and installs stay quiet', () {
    final policy = RemoteHostLinkToastPolicy()
      ..evaluate(_hosts(const RemoteHostConnected()));
    expect(policy.evaluate(_hosts(const RemoteHostDisconnected())), isEmpty);
    expect(policy.evaluate(_hosts(const RemoteHostConnecting())), isEmpty);
    expect(policy.evaluate(_hosts(const RemoteHostConnected())), isEmpty);
    expect(
      policy.evaluate(_hosts(const RemoteHostInstalling(stage: 'restart'))),
      isEmpty,
    );
    expect(policy.evaluate(_hosts(const RemoteHostConnected())), isEmpty);
  });

  test('a drop the user then disconnects does not announce a reconnect', () {
    final policy = RemoteHostLinkToastPolicy()
      ..evaluate(_hosts(const RemoteHostConnected()));
    expect(policy.evaluate(_hosts(const RemoteHostOffline())), hasLength(1));
    expect(policy.evaluate(_hosts(const RemoteHostDisconnected())), isEmpty);
    expect(policy.evaluate(_hosts(const RemoteHostConnected())), isEmpty);
  });

  test('the host on screen is silent and not marked', () {
    final policy = RemoteHostLinkToastPolicy()
      ..evaluate(_hosts(const RemoteHostConnected()));
    expect(
      policy.evaluate(_hosts(const RemoteHostOffline()), visibleHostId: 'mac'),
      isEmpty,
    );
    expect(policy.evaluate(_hosts(const RemoteHostConnected())), isEmpty);
  });

  test('a new or removed host is silent', () {
    final policy = RemoteHostLinkToastPolicy()
      ..evaluate(_hosts(const RemoteHostConnected()));
    expect(
      policy.evaluate(<RemoteHostLinkSnapshot>[
        ..._hosts(const RemoteHostConnected()),
        const RemoteHostLinkSnapshot(
          hostId: 'box',
          alias: 'Linux Box',
          status: RemoteHostOffline(),
        ),
      ]),
      isEmpty,
    );
    expect(policy.evaluate(const <RemoteHostLinkSnapshot>[]), isEmpty);
  });

  test('toasts each host that drops', () {
    final policy = RemoteHostLinkToastPolicy()
      ..evaluate(<RemoteHostLinkSnapshot>[
        const RemoteHostLinkSnapshot(
          hostId: 'mac',
          alias: 'Build Mac',
          status: RemoteHostConnected(),
        ),
        const RemoteHostLinkSnapshot(
          hostId: 'box',
          alias: 'Linux Box',
          status: RemoteHostConnected(),
        ),
      ]);
    final toasts = policy.evaluate(<RemoteHostLinkSnapshot>[
      const RemoteHostLinkSnapshot(
        hostId: 'mac',
        alias: 'Build Mac',
        status: RemoteHostOffline(),
      ),
      const RemoteHostLinkSnapshot(
        hostId: 'box',
        alias: 'Linux Box',
        status: RemoteHostError(detail: 'boom'),
      ),
    ]);
    expect(toasts.map((toast) => toast.hostId), <String>['mac', 'box']);
  });
}

List<RemoteHostLinkSnapshot> _hosts(RemoteHostStatus status) =>
    <RemoteHostLinkSnapshot>[
      RemoteHostLinkSnapshot(hostId: 'mac', alias: 'Build Mac', status: status),
    ];
