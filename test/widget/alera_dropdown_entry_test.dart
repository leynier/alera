import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dropdown entry exposes the expected height and selection match', () {
    const enabled = AleraDropdownEntry<String>(value: 'tokyo', label: 'Tokyo');
    const disabled = AleraDropdownEntry<String>(
      value: 'tokyo',
      label: 'Tokyo',
      enabled: false,
    );

    expect(enabled.height, 36);
    expect(enabled.represents('tokyo'), isTrue);
    expect(disabled.represents('tokyo'), isFalse);
  });
}
