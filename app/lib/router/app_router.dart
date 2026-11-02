// Navigation routing for OrcaSlicer app

import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/printer_setup_screen.dart';
import '../screens/print_queue_screen.dart';
import '../screens/printer_control_screen.dart';
import '../screens/settings_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case '/printer-setup':
        return MaterialPageRoute(builder: (_) => const PrinterSetupScreen());
      case '/print-queue':
        return MaterialPageRoute(builder: (_) => const PrintQueueScreen());
      case '/printer-control':
        return MaterialPageRoute(builder: (_) => const PrinterControlScreen());
      case '/settings':
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}
