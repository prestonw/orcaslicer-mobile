// Printer control screen — real-time status, temperature monitoring, print controls

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
        
        return Scaffold(
          appBar: AppBar(
            title: Text(printer.name),
            actions: [
              IconButton(
                icon: Icon(
                  printer.online ? Icons.link : Icons.link_off,
                  color: printer.online ? Colors.green : Colors.red,
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
                      printer.online ? 'Connected' : 'Offline',
                      style: TextStyle(
                        color: printer.online ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text('${printer.ip}:${printer.port}'),
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
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: printer.progress,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${(printer.progress * 100).toStringAsFixed(0)}%'),
                            Text('Status: ${printer.status}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Temperature card
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
                              unit: '°C',
                              color: Colors.orange,
                            ),
                            _TempGauge(
                              label: 'Bed',
                              temperature: printer.bedTemp,
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
                
                // Fan speed card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fan Speed',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: (printer.fanSpeed / 100).clamp(0, 1),
                                onChanged: (value) {
                                  // TODO: send fan speed command
                                },
                              ),
                            ),
                            Text('${printer.fanSpeed}%'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Print controls
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Print Controls',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                // TODO: upload G-code file
                              },
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Upload File'),
                            ),
                            ElevatedButton.icon(
                              onPressed: printer.printing ? () {
                                // TODO: pause print
                              } : null,
                              icon: const Icon(Icons.pause),
                              label: const Text('Pause'),
                            ),
                            ElevatedButton.icon(
                              onPressed: printer.printing ? () {
                                // TODO: resume print
                              } : null,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Resume'),
                            ),
                            ElevatedButton.icon(
                              onPressed: printer.printing ? () {
                                // TODO: stop print
                              } : null,
                              icon: const Icon(Icons.stop),
                              label: const Text('Stop'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                            ),
                          ],
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
  final String unit;
  final Color color;
  
  const _TempGauge({
    required this.label,
    required this.temperature,
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
          '$temperature$unit',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
