// Printer control screen — AD5X-style layout:
//  - left icon rail (status / model / temps / settings)
//  - right temps rail with big current/target readouts
//  - center: model preview image + real progress (M27 byte % + layer)
//  - adapts to portrait (rail on top, temps inline) and landscape
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../managers/printer_manager.dart';
import '../models/printer.dart';

class PrinterControlScreen extends StatefulWidget {
  const PrinterControlScreen({super.key});

  @override
  State<PrinterControlScreen> createState() => _PrinterControlScreenState();
}

class _PrinterControlScreenState extends State<PrinterControlScreen> {
  int _section = 0; // 0 status, 1 model, 2 temps, 3 settings

  static const _bg = Color(0xFF14171D);
  static const _railBg = Color(0xFF101319);
  static const _card = Color(0xFF1E232C);
  static const _line = Color(0xFF2A3140);
  static const _accent = Color(0xFFFF8A3D); // AD5X orange
  static const _text = Color(0xFFF2F4F7);
  static const _dim = Color(0xFF9AA3B2);

  Widget _railItem(BuildContext context, int index, IconData icon) {
    final selected = _section == index;
    return Material(
      color: selected ? _line : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _section = index),
        child: Icon(icon, color: selected ? _accent : _dim, size: 26),
      ),
    );
  }

  /// "7725s" -> "2h 5m"; "2400s" -> "40m"; <60s -> "45s".
  static String _fmtDur(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${sec}s';
  }

  /// Big current/target temp tile (temps rail / temps section).
  Widget _tempTile(String label, IconData icon, double temp, double target,
      Color color, {required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: _dim, fontSize: 11, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Icon(icon, color: color, size: compact ? 22 : 30),
          const SizedBox(height: 4),
          Text(
            temp.toStringAsFixed(1),
            style: TextStyle(
              color: color,
              fontSize: compact ? 22 : 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            target > 0
                ? '${target.toStringAsFixed(0)}°C target'
                : '${temp.toStringAsFixed(1)}°C',
            style: const TextStyle(color: _dim, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _tempRail(Printer printer) {
    return Column(
      children: [
        _tempTile('HOTEND', Icons.device_thermostat, printer.hotendTemp,
            printer.hotendTarget, _accent, compact: true),
        const SizedBox(height: 12),
        _tempTile('BED', Icons.bed, printer.bedTemp, printer.bedTarget,
            const Color(0xFF4FA8FF), compact: true),
      ],
    );
  }

  Widget _progressPanel(Printer printer, double? progress) {
    final pct = progress != null ? (progress * 100).toStringAsFixed(1) : null;
    final layer = printer.sdTotalLayers > 0
        ? 'Layer ${printer.sdLayer}/${printer.sdTotalLayers}'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('PRINT PROGRESS',
                style: TextStyle(color: _dim, fontSize: 12, letterSpacing: 1.2)),
            const Spacer(),
            pct != null
                ? Text('$pct%',
                    style: const TextStyle(
                        color: _accent, fontSize: 20, fontWeight: FontWeight.bold))
                : const Text('—',
                    style: TextStyle(color: _dim, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress, // null = indeterminate
            minHeight: 10,
            backgroundColor: _line,
            valueColor: const AlwaysStoppedAnimation<Color>(_accent),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              layer ?? (printer.printing ? 'Printing…' : 'Idle'),
              style: const TextStyle(color: _text, fontSize: 13),
            ),
            if (printer.zPosition > 0)
              Text('Z ${printer.zPosition.toStringAsFixed(1)}mm',
                  style: const TextStyle(color: _dim, fontSize: 12)),
          ],
        ),
        if (printer.estimatedRemainingSeconds != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16, color: _accent),
              const SizedBox(width: 6),
              Text('Est. ${_fmtDur(printer.estimatedRemainingSeconds!.round())} left',
                  style: const TextStyle(
                      color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
              if (printer.estimatedFinishAt != null) ...[
                const SizedBox(width: 10),
                Text(
                  'finishes ~${printer.estimatedFinishAt!.hour.toString().padLeft(2, '0')}:${printer.estimatedFinishAt!.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: _dim, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
        if (printer.currentFile.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.insert_drive_file, size: 16, color: _dim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(printer.currentFile,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _text, fontSize: 13)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _noPreview() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_not_supported, size: 36, color: _dim),
          const SizedBox(height: 6),
          const Text('No model preview in this file',
              style: TextStyle(color: _dim, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _modelCard(Printer printer, double? progress) {
    final img = context.read<PrinterManager>().modelImage;
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: SizedBox(
                width: 170,
                height: 130,
                child: img != null
                    ? Image.memory(Uint8List.fromList(img), fit: BoxFit.contain)
                    : _noPreview(),
              ),
            ),
            const SizedBox(height: 12),
            _progressPanel(printer, progress),
          ],
        ),
      ),
    );
  }

  Widget _tempsSection(Printer printer) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TEMPERATURES',
                style: TextStyle(color: _dim, fontSize: 12, letterSpacing: 1.2)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _tempTile('HOTEND', Icons.device_thermostat, printer.hotendTemp,
                    printer.hotendTarget, _accent, compact: false),
                _tempTile('BED', Icons.bed, printer.bedTemp, printer.bedTarget,
                    const Color(0xFF4FA8FF), compact: false),
              ],
            ),
            const SizedBox(height: 14),
            Text('Mode: ${printer.moveMode.isEmpty ? '—' : printer.moveMode}',
                style: const TextStyle(color: _dim, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _settingsSection(Printer printer) {
    final manager = context.read<PrinterManager>();
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SETTINGS',
                style: TextStyle(color: _dim, fontSize: 12, letterSpacing: 1.2)),
            const SizedBox(height: 14),
            _infoRow('Printer', '${printer.ip}:${printer.port}'),
            _infoRow('Model', printer.machineType ?? '—'),
            _infoRow('Firmware', printer.firmware ?? '—'),
            _infoRow('Device ID', printer.deviceID),
            if (printer.xMax != null && printer.yMax != null)
              _infoRow('Build plate',
                  '${printer.xMax!.toStringAsFixed(0)} × ${printer.yMax!.toStringAsFixed(0)} mm'),
            _infoRow('Light', printer.ledOn ? 'On' : 'Off'),
            if (printer.estimatedTotalSeconds != null)
              _infoRow('Total time',
                  _fmtDur(printer.estimatedTotalSeconds!.round())),
            if (printer.estimatedRemainingSeconds != null)
              _infoRow('Time left',
                  '${_fmtDur(printer.estimatedRemainingSeconds!.round())}'
                  '${printer.estimatedFinishAt != null ? " (est. finish ~${printer.estimatedFinishAt!.hour.toString().padLeft(2, '0')}:${printer.estimatedFinishAt!.minute.toString().padLeft(2, '0')})" : ''}'),
            const Divider(color: _line, height: 24),
            if (manager.uploadState == 'uploading') ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: manager.uploadProgress,
                  minHeight: 6,
                  backgroundColor: _line,
                  valueColor: const AlwaysStoppedAnimation<Color>(_accent),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(manager.uploadProgress * 100).toStringAsFixed(1)}% sent — printer writes to SD slower than the network; keep the app open',
                style: const TextStyle(color: _dim, fontSize: 12),
              ),
            ],
            if (manager.uploadState == 'done')
              const Text('Upload complete — file is selected on the printer.',
                  style: TextStyle(color: _dim, fontSize: 12)),
            if (manager.uploadState.startsWith('error'))
              Text(manager.uploadState,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
              ),
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
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Choose .gcode and send'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: manager.disconnect,
              icon: const Icon(Icons.link_off, size: 18, color: Colors.red),
              label: const Text('Disconnect',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 92,
              child:
                  Text(k, style: const TextStyle(color: _dim, fontSize: 13))),
          Expanded(
              child: Text(v,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 13))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PrinterManager>(
      builder: (context, manager, child) {
        final printer = manager.selectedPrinter;
        if (printer == null) {
          return Scaffold(
              backgroundColor: _bg,
              body: const Center(
                  child: Text('Select a printer to begin',
                      style: TextStyle(color: _dim))));
        }
        final progress = manager.estimateProgress();

        final rail = Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _railItem(context, 0, Icons.speed),
            _railItem(context, 1, Icons.image),
            _railItem(context, 2, Icons.thermostat),
            _railItem(context, 3, Icons.settings),
          ],
        );
        final statusHeader = Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: printer.online
                ? (printer.printing ? const Color(0xFF2A2620) : const Color(0xFF22283A))
                : const Color(0xFF332222),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                printer.online ? Icons.wifi : Icons.wifi_off,
                color: printer.online ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                printer.statusLabel,
                style: TextStyle(
                  color: printer.online
                      ? (printer.printing ? _accent : Colors.green)
                      : Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Text('${printer.ip}:${printer.port}',
                  style: const TextStyle(color: _dim, fontSize: 12)),
            ],
          ),
        );

        Widget center() {
          switch (_section) {
            case 1: // model
              return ListView(
                children: [
                  _modelCard(printer, progress),
                  const SizedBox(height: 12),
                ],
              );
            case 2:
              return _tempsSection(printer);
            case 3:
              return _settingsSection(printer);
            default: // status
              return _modelCard(printer, progress);
          }
        }

        final isLandscape = MediaQuery.of(context).size.width >
            MediaQuery.of(context).size.height;

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            title: Text(printer.name,
                style: const TextStyle(color: _text, fontSize: 18)),
            actions: [
              IconButton(
                icon: Icon(
                  manager.isConnected ? Icons.link : Icons.link_off,
                  color: manager.isConnected ? Colors.green : Colors.red,
                ),
                onPressed: manager.disconnect,
                tooltip: 'Disconnect',
              ),
            ],
          ),
          body: SafeArea(
            child: isLandscape
                ? Row(
                    children: [
                      Container(
                        width: 56,
                        color: _railBg,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _railItem(context, 0, Icons.speed),
                            const SizedBox(height: 8),
                            _railItem(context, 1, Icons.image),
                            const SizedBox(height: 8),
                            _railItem(context, 2, Icons.thermostat),
                            const Spacer(),
                            _railItem(context, 3, Icons.settings),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            statusHeader,
                            const SizedBox(height: 10),
                            Expanded(
                              child: SingleChildScrollView(
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      child:
                                          Column(children: [center()]))),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 150,
                        color: _railBg,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: _tempRail(printer),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Container(
                        color: _railBg,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: rail,
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              statusHeader,
                              const SizedBox(height: 10),
                              if (_section == 2 || _section == 3)
                                center()
                              else ...[
                                _modelCard(printer, progress),
                                const SizedBox(height: 12),
                                _tempRail(printer),
                              ],
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
