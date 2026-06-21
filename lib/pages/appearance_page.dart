import 'package:flutter/material.dart';

import '../l10n/s.dart';
import '../settings/definitions/appearance_defs.dart';
import '../widgets/settings/settings_group_page.dart';

class AppearancePage extends StatelessWidget {
  final String? highlightId;

  const AppearancePage({super.key, this.highlightId});

  @override
  Widget build(BuildContext context) {
    return SettingsGroupPage(
      title: context.l10n.appearance_title,
      groupsBuilder: buildAppearanceGroups,
      highlightId: highlightId,
    );
  }
}
