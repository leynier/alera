import 'package:alera/src/features/orchestration/presentation/run_board_read_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workflow attention status uses a title-case label', () {
    expect(runBoardStatusLabel('attention'), 'Attention');
  });
}
