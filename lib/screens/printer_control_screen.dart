// Printer control screen — real-time status, temperature monitoring, upload

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/printer_manager.dart';

class PrinterControlScreen extends StatefulWidget {
  const PrinterControlScreen({super.key});

  @override
  State<PrinterControlScreen> createState() => _PrinterControlScreenState();
}

class _PrinterControlScreenState extends State<PrinterControlScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<PrinterManager>(
      builder: (context, manager, child) {
        if (manager.selectedPrinter == null) {
          return const Center(child: Text('Select a printer to begin'));
        }

        final printer = manager.selectedPrinter!;
        final realProgress = manager.estimateProgress(); // null = unknown
        // Real Z-based progress when available, else elapsed-time estimate.
        final double progress;
        final String progressLabel;
        if (realProgress != null) {
          progress = realProgress;
          progressLabel = '${(realProgress * 100).toStringAsFixed(0)}% (Z: ${printer.zPosition.toStringAsFixed(1)}mm)';
        } else {
          progress = 0.0;
          progressLabel = printer.printing ? 'Printing (Z-based progress not available)' : printer.statusLabel;
        }
        
        return Scaffold(
          appBar: AppBar(
            title: Text(printer.name),
            actions: [
              IconButton(
                icon: Icon(
                  manager.isConnected ? Icons.link : Icons.link_off,
                  color: manager.isConnected ? Colors.green : Colors.red,
                ),
                onPressed: () => manager.disconnect(),
                tooltip: 'Disconnect',
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection status card
                Card(
                  color: printer.online ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                  child: ListTile(
                    leading: Icon(
                      printer.online ? Icons.wifi : Icons.wifi_off,
                      color: printer.online ? Colors.green : Colors.red,
                    ),
                    title: Text(
                      printer.statusLabel,
                      style: TextStyle(
                        color: printer.online ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      printer.machineType != null
                          ? '${printer.ip}:${printer.port} · ${printer.machineType}${printer.firmware != null ? ' ${printer.firmware}' : ''}'
                          : '${printer.ip}:${printer.port}',
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Print progress card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Print Progress',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (printer.currentFile.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              printer.currentFile,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(progressLabel),
                            Text('Mode: ${printer.moveMode}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Temperature card (M105: T0 hotend / B bed, current/target)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Temperatures',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _TempGauge(
                              label: 'Hotend',
                              temperature: printer.hotendTemp,
                              target: printer.hotendTarget,
                              unit: '°C',
                              color: Colors.orange,
                            ),
                            _TempGauge(
                              label: 'Bed',
                              temperature: printer.bedTemp,
                              target: printer.bedTarget,
                              unit: '°C',
                              color: Colors.blue,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Upload card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Send G-code to Printer',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        if (manager.uploadState == 'uploading') ...[
                          LinearProgressIndicator(
                            value: manager.uploadProgress,
                            minHeight: 6,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(manager.uploadProgress * 100).toStringAsFixed(1)}% sent · ${manager.uploadElapsedSeconds}s — printer writes to SD slower than the network; keep the app open',
                          ),
                        ],
                        if (manager.uploadState == 'done')
                          const Text('Upload complete — file is selected on the printer.'),
                        if (manager.uploadState.startsWith('error'))
                          Text(manager.uploadState,
                              style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final path = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['gcode', 'gco'],
                            );
                            final p = path?.files.single.path;
                            if (p == null) return;
                            final name = p.split(RegExp(r'[\\/]')).last;
                            if (!mounted) return;
                            try {
                              await manager.uploadGcode(File(p), name);
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Upload failed: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Choose .gcode and send'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Temperature gauge widget
class _TempGauge extends StatelessWidget {
  final String label;
  final double temperature;
  final double target;
  final String unit;
  final Color color;
  
  const _TempGauge({
    required this.label,
    required this.temperature,
    required this.target,
    required this.unit,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          label == 'Hotend' ? Icons.device_thermostat : Icons.bed,
          color: color,
          size: 40,
        ),
        const SizedBox(height: 4),
        Text(
          '${temperature.toStringAsFixed(1)}$unit',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          target > 0 ? 'target ${target.toStringAsFixed(0)}$unit' : label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
