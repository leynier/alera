/// Time zones offered by the picker. The runtime accepts any IANA name, so the
/// current value is always added when it is not listed here.
const List<String> automationCommonTimezones = <String>[
  'UTC',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Havana',
  'America/Mexico_City',
  'America/Bogota',
  'America/Lima',
  'America/Santiago',
  'America/Sao_Paulo',
  'America/Argentina/Buenos_Aires',
  'Europe/London',
  'Europe/Madrid',
  'Europe/Paris',
  'Europe/Berlin',
  'Europe/Rome',
  'Europe/Moscow',
  'Africa/Lagos',
  'Africa/Johannesburg',
  'Asia/Dubai',
  'Asia/Kolkata',
  'Asia/Shanghai',
  'Asia/Singapore',
  'Asia/Tokyo',
  'Australia/Sydney',
  'Pacific/Auckland',
];

List<String> automationTimezoneChoices(String? current) {
  final value = current?.trim();
  return <String>[
    if (value != null &&
        value.isNotEmpty &&
        !automationCommonTimezones.contains(value))
      value,
    ...automationCommonTimezones,
  ];
}
