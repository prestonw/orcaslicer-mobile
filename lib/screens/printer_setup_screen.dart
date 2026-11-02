// Printer setup screen — pair AD5X via IP and device ID

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/printer_manager.dart';

class PrinterSetupScreen extends StatefulWidget {
  const PrinterSetupScreen({super.key});

  @override
  State<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends State<PrinterSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '80');
  final _deviceIDController = TextEditingController();
  final _nameController = TextEditingController();
  
  bool _scanning = false;
  String? _lastError;
  
  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _deviceIDController.dispose();
    _nameController.dispose();
    super.dispose();
  }
  
  Future<void> _pairPrinter() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _lastError = null;
    });
    
    try {
      final port = int.parse(_portController.text);
      final deviceID = _deviceIDController.text.trim();
      final ip = _ipController.text.trim();
      final name = _nameController.text.trim();
      
      final printer = await context.read<PrinterManager>().pairPrinter(
        ip,
        port,
        deviceID,
        name,
      );
      
      if (printer != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Printer "${printer.name}" added!')),
        );
        // Auto-connect after pairing
        await context.read<PrinterManager>().connectToPrinter(printer);
      }
    } catch (e) {
      setState(() {
        _lastError = e.toString();
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.add_circle_outline, size: 32),
                    const SizedBox(width: 12),
                    Text(
                      'Add AD5X Printer',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'IP Address',
                    hintText: '192.168.1.100',
                    prefixIcon: Icon(Icons.cloud),
                    helperText: 'Local IP of your AD5X printer',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'IP address required';
                    }
                    final pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
                    if (!pattern.hasMatch(value)) {
                      return 'Invalid IP format';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    prefixIcon: Icon(Icons.settings_input_antenna),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Port required';
                    }
                    final port = int.tryParse(value);
                    if (port == null || port < 1 || port > 65535) {
                      return 'Invalid port';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _deviceIDController,
                  decoration: const InputDecoration(
                    labelText: 'Device ID',
                    hintText: 'Printer serial number',
                    prefixIcon: Icon(Icons.device_hub),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Device ID required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'My AD5X',
                    prefixIcon: Icon(Icons.label),
                  ),
                ),
                if (_lastError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _lastError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _scanning ? null : () {},
                        icon: const Icon(Icons.search),
                        label: const Text('Scan LAN'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _scanning ? null : _pairPrinter,
                        icon: const Icon(Icons.add),
                        label: const Text('Pair Printer'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Note: AD5X printers are paired locally on your network.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
