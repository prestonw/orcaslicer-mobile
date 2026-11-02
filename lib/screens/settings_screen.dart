// Settings screen — app preferences, API endpoints, and printer defaults

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/printer_manager.dart';
import '../services/slicer_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Slicer API section
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.precision_manufacturing),
              title: const Text('Slicer API'),
              children: [
                ListTile(
                  title: const Text('API Endpoint'),
                  subtitle: const Text('Headless OrcaSlicer service URL'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                ListTile(
                  title: const Text('Default Profile'),
                  subtitle: const Text('AD5X Standard'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),
          
          // Network section
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.wifi),
              title: const Text('Network'),
              children: [
                ListTile(
                  title: const Text('mDNS Discovery'),
                  trailing: Switch(
                    value: true,
                    onChanged: (value) {},
                  ),
                ),
                ListTile(
                  title: const Text('Auto-Connect'),
                  subtitle: const Text('Connect to last used printer'),
                  trailing: Switch(
                    value: false,
                    onChanged: (value) {},
                  ),
                ),
              ],
            ),
          ),
          
          // Print defaults section
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.settings),
              title: const Text('Print Defaults'),
              children: [
                ListTile(
                  title: const Text('Layer Height'),
                  subtitle: const Text('0.2mm'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                ListTile(
                  title: const Text('Infill'),
                  subtitle: const Text('15% Gyroid'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                ListTile(
                  title: const Text('Nozzle Temp'),
                  subtitle: const Text('200°C'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),
          
          // About section
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.info),
              title: const Text('About'),
              children: [
                const ListTile(
                  title: Text('OrcaSlicer Mobile'),
                  subtitle: Text('Version 0.1.0'),
                ),
                const ListTile(
                  title: Text('License'),
                  subtitle: Text('MIT'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
