// Smoke test — verifies the app boots and renders its home screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:orcaslicer_mobile/app.dart';
import 'package:orcaslicer_mobile/managers/printer_manager.dart';
import 'package:orcaslicer_mobile/services/print_queue_service.dart';

void main() {
  testWidgets('App boots without crashing', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PrinterManager()),
          ChangeNotifierProvider(create: (_) => PrintQueueProvider()),
        ],
        child: const OrcaSlicerApp(),
      ),
    );

    expect(find.byType(OrcaSlicerApp), findsOneWidget);
  });
}
