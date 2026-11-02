// Home screen with bottom navigation — printers, setup, print queue

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/printer_manager.dart';
import 'printer_setup_screen.dart';
import 'print_queue_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  
  late final List<Widget> _screens;
  
  @override
  void initState() {
    super.initState();
    // Load paired printers on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrinterManager>().loadPrinters();
    });
    
    _screens = [
      _PrintersList(),
      PrinterSetupScreen(),
      PrintQueueScreen(),
    ];
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OrcaSlicer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.print),
            label: 'Printers',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle),
            label: 'Add Printer',
          ),
          NavigationDestination(
            icon: Icon(Icons.queue),
            label: 'Queue',
          ),
        ],
      ),
    );
  }
}

// Printer list showing paired AD5X printers
class _PrintersList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final printers = context.watch<PrinterManager>().printers;
    final selected = context.watch<PrinterManager>().selectedPrinter;
    
    if (printers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.print, size: 80, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No printers paired',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Add your AD5X by IP and device ID',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.read<PrinterManager>(),
              icon: const Icon(Icons.add),
              label: const Text('Add Printer'),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: printers.length,
      itemBuilder: (context, index) {
        final printer = printers[index];
        final isSelected = selected?.id == printer.id;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () {
              // Navigate to printer control (future screen)
            },
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: printer.online ? Colors.green : Colors.grey,
                child: const Icon(Icons.print, color: Colors.white),
              ),
              title: Text(printer.name),
              subtitle: Text('${printer.ip}:${printer.port}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (printer.online)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                      ),
                    ),
                ],
              ),
              onTap: () {
                // Select this printer
              },
            ),
          ),
        );
      },
    );
  }
}
