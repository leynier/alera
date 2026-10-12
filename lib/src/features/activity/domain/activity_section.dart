import 'package:dart_mappable/dart_mappable.dart';

part 'activity_section.mapper.dart';

/// The sections of the Activity page, in rail order.
@MappableEnum()
enum ActivitySection(final String label) {
  runs('Runs'),
  questions('Questions'),
  automations('Automations'),
}
