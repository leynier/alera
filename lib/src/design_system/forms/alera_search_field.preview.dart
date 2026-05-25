import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Standard', group: 'Search field', size: Size(280, 80))
Widget aleraSearchFieldPreview() =>
    const AleraSearchField(hintText: 'Search settings');

@AleraPreview(name: 'Dense', group: 'Search field', size: Size(280, 80))
Widget aleraSearchFieldDensePreview() =>
    const AleraSearchField(dense: true, hintText: 'Search projects');
