import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Consumer<SettingsService>(
        builder: (context, settings, _) => ListView(
          children: [
            SwitchListTile(
              title: const Text('Enter sends message'),
              subtitle: Text(
                settings.enterToSend
                    ? 'Press Enter to send, Shift+Enter for new line'
                    : 'Press Enter for new line, use send button to send',
              ),
              value: settings.enterToSend,
              onChanged: (v) => settings.enterToSend = v,
            ),
          ],
        ),
      ),
    );
  }
}
