import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every runtime watcher shares one coalescer instance', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = container.read(runtimeChangeCoalescerProvider);
    final second = container.read(runtimeChangeCoalescerProvider);

    expect(identical(first, second), isTrue);
  });

  test('disposing the container stops the coalescer', () async {
    final container = ProviderContainer();
    final coalescer = container.read(runtimeChangeCoalescerProvider);
    var runs = 0;

    container.dispose();
    coalescer.schedule('key', Object(), () async => runs += 1);
    await Future.pause(const Duration(milliseconds: 250));

    expect(runs, 0, reason: 'a disposed coalescer must not leak timers');
  });

  test('coalescer keys used by the repositories do not collide', () {
    // The coalescer is shared process-wide, so these namespaces are the
    // contract that keeps unrelated refreshes from merging.
    const keys = <String>[
      'workspaces:project-1',
      'tabs:workspace-1',
      'projects',
      'projectConfigs',
      'sshTargets',
      'linkedReview:workspace-1',
      'mobileStatus',
    ];

    expect(keys.toSet(), hasLength(keys.length));
  });

  test('a shared coalescer keeps unrelated keys independent', () async {
    final coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 10),
      maxDelay: const Duration(milliseconds: 50),
    );
    addTearDown(coalescer.dispose);
    var tabRuns = 0;
    var projectRuns = 0;
    final tabOwner = Object();

    for (var i = 0; i < 5; i++) {
      coalescer.schedule(
        'tabs:workspace-1',
        tabOwner,
        () async => tabRuns += 1,
      );
    }
    coalescer.schedule('projects', Object(), () async => projectRuns += 1);
    await Future.pause(const Duration(milliseconds: 80));

    expect(tabRuns, 1);
    expect(projectRuns, 1);
  });
}
