// OrcaSlicer Mobile — Android app for AD5X 3D printer control
// Flutter + Material 3, Kotlin/Java for native printer communication

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PrinterManager()),
        ChangeNotifierProvider(create: (_) => PrintQueueProvider()),
      ],
      child: const OrcaSlicerApp(),
    ),
  );
}
