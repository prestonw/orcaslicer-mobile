// Print queue screen — manage pending and active prints

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/printer_manager.dart';

class PrintQueueScreen extends StatelessWidget {
  const PrintQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.queue, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Print Queue',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Consumer<PrinterManager>(
              builder: (context, manager, child) {
                if (manager.printers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.print, size: 64, color: Colors.grey[600]),
                        const SizedBox(height: 16),
                        const Text('No printers configured'),
                      ],
                    ),
                  );
                }
                
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: manager.printers.length,
                  itemBuilder: (context, index) {
                    final printer = manager.printers[index];
                    final isActive = manager.selectedPrinter?.id == printer.id;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: printer.online ? Colors.green : Colors.grey,
                          child: const Icon(Icons.print, color: Colors.white),
                        ),
                        title: Text(printer.name),
                        subtitle: Text(printer.ip),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isActive)
                              const Chip(
                                label: Text('Active', style: TextStyle(fontSize: 12)),
                                visualDensity: VisualDensity.compact,
                              ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                switch (value) {
                                  case 'connect':
                                    // TODO: connect to printer
                                    break;
                                  case 'disconnect':
                                    // TODO: disconnect
                                    break;
                                  case 'remove':
                                    // TODO: remove printer
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'connect',
                                  child: Text('Connect'),
                                ),
                                const PopupMenuItem(
                                  value: 'disconnect',
                                  child: Text('Disconnect'),
                                ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () {
                          // Select this printer
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
