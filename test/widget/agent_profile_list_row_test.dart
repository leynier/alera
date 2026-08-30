import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profile_list_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saved profile row shows the click cursor on hover', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 30);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentProfileListRow(
            profile: AgentProfile(
              id: 'profile-1',
              name: 'Codex',
              agentType: 'codex',
              command: 'codex',
              createdAt: now,
              updatedAt: now,
            ),
            selected: false,
            onTap: () {},
            dragHandle: const SizedBox(),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: .mouse, pointer: 1);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text('Codex')));
    await tester.pump();

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });
}
