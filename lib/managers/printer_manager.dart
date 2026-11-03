// Printer manager — AD5X discovery, pairing, connection lifecycle, and live
// telemetry over the Flashforge 8899 LAN protocol (raw TCP serial).
//
// The previous implementation assumed a Bambu-style WebSocket/JSON protocol.
// The AD5X speaks raw G-code-over-TCP on port 8899 instead — see
// protocol/flashforge-ad5x-lan.md (reverse-engineered + verified live).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/printer.dart';
import '../services/flashforge_printer.dart';

class PrinterManager extends ChangeNotifier {
  final List<Printer> _printers = [];
  Printer? _selectedPrinter;
  FlashforgePrinter? _conn;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  bool _polling = false;
  bool _reconnecting = false;

  /// Print start time observed from M119 (for client-side progress estimate).
  DateTime? _printStartedAt;

  List<Printer> get printers => List.unmodifiable(_printers);
  Printer? get selectedPrinter => _selectedPrinter;

  /// True while a live 8899 connection + poll loop is active.
  bool get isConnected => _conn?.isOpen ?? false;

  /// Last upload progress fraction (bytes handed to the socket), exposed for
  /// the UI. Note: the printer writes to SD slower than we send, so this is
  /// "data sent", not "data on card".
  double uploadProgress = 0.0;
  String uploadState = ''; // '', 'uploading', 'done', 'error: ...'
  DateTime? _uploadStartedAt;

  /// Seconds since upload started (0 when not uploading).
  int get uploadElapsedSeconds {
    final s = _uploadStartedAt;
    return s == null ? 0 : DateTime.now().difference(s).inSeconds;
  }

  // ----------------------------------------------------------------
  // Pairing
  // ----------------------------------------------------------------

  Future<Printer?> pairPrinter(String ip, int port, String deviceID,
      String name) async {
    if (!_isValidIp(ip)) throw FormatException('Invalid IP address');
    Printer? dup;
    for (final p in _printers) {
      if (p.deviceID == deviceID || p.ip == ip) {
        dup = p;
        break;
      }
    }
    if (dup != null) return dup;

    final printer = Printer(
      id: deviceID.isNotEmpty ? deviceID : ip,
      deviceID: deviceID.isNotEmpty ? deviceID : ip,
      name: name.isNotEmpty ? name : 'AD5X ($deviceID)',
      ip: ip,
      port: port,
      pairedAt: DateTime.now(),
    );
    _printers.add(printer);
    await _savePrinters();
    notifyListeners();
    return printer;
  }

  // ----------------------------------------------------------------
  // Connection + telemetry
  // ----------------------------------------------------------------

  Future<void> connectToPrinter(Printer printer) async {
    await _teardownConnection();
    _selectedPrinter = printer;
    notifyListeners();
    await _connectAndStartPolling(printer);
  }

  Future<void> _connectAndStartPolling(Printer printer) async {
    final conn = FlashforgePrinter(printer.ip, port: printer.port);
    try {
      await conn.connect();
      final ok = await conn.handshake();
      if (!ok) {
        throw StateError('Handshake rejected by printer');
      }
      _conn = conn;
      printer.markOnline();

      // Identify (best effort — don't fail the connection over it).
      try {
        final id = await conn.identify();
        if (id != null) {
          printer.applyM115(
              machineType: id.machineType,
              firmware: id.firmware,
              serial: id.serial);
        }
      } catch (_) {}

      // First immediate poll, then periodic.
      await _pollOnce(printer);
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_polling) _pollOnce(printer);
      });
      notifyListeners();
    } catch (e) {
      conn.dispose();
      _conn = null;
      printer.markOffline();
      notifyListeners();
      _scheduleReconnect(printer);
      throw Exception('Failed to connect to ${printer.ip}:$e');
    }
  }

  Future<void> _pollOnce(Printer printer) async {
    final conn = _conn;
    if (conn == null || !conn.isOpen || _polling) return;
    _polling = true;
    try {
      // One short-lived command sequence per poll (matches Flash Studio).
      final st = await conn.status();
      if (st != null) {
        printer.applyM119(
          machineStatus: st.machineStatus,
          moveMode: st.moveMode,
          ledOn: st.ledOn,
          currentFile: st.currentFile,
        );
        // Track when a print starts so we can estimate progress by time.
        if (st.machineStatus == 'BUILDING' && _printStartedAt == null) {
          _printStartedAt = DateTime.now();
        } else if (st.machineStatus != 'BUILDING') {
          _printStartedAt = null;
        }
      }
      final t = await conn.temperatures();
      if (t != null) {
        printer.applyM105(
          hotendTemp: t.hotend,
          hotendTarget: t.hotendTarget,
          bedTemp: t.bed,
          bedTarget: t.bedTarget,
        );
      }
      notifyListeners();
    } catch (_) {
      // Socket died mid-poll — the listener's onDone path handles it;
      // schedule a reconnect.
      _scheduleReconnect(printer);
    } finally {
      _polling = false;
    }
  }

  void _scheduleReconnect(Printer printer) {
    if (_reconnecting) return;
    _reconnecting = true;
    _conn?.dispose();
    _conn = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    printer.markOffline();
    notifyListeners();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        await _connectAndStartPolling(printer);
        _reconnecting = false;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
      } catch (_) {
        // try again next tick
      }
    });
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnecting = false;
    await _teardownConnection();
    _selectedPrinter?.markOffline();
    notifyListeners();
  }

  Future<void> _teardownConnection() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _conn?.dispose();
    _conn = null;
    _printStartedAt = null;
  }

  // ----------------------------------------------------------------
  // Upload
  // ----------------------------------------------------------------

  /// Upload a gcode file to the printer and select it for printing.
  Future<void> uploadGcode(File file, String remoteName) async {
    final conn = _conn;
    final printer = _selectedPrinter;
    if (conn == null || !conn.isOpen || printer == null) {
      throw Exception('No printer connected');
    }
    // Pause the poll loop for the duration of the transfer; the upload owns
    // the socket and polling would race it.
    _pollTimer?.cancel();
    _pollTimer = null;
    uploadState = 'uploading';
    uploadProgress = 0.0;
    _uploadStartedAt = DateTime.now();
    notifyListeners();
    try {
      await conn.uploadFile(file, remoteName,
          onProgress: (sent, total) {
        uploadProgress = sent / total;
        notifyListeners();
      });
      uploadState = 'done';
      uploadProgress = 1.0;
    } catch (e) {
      uploadState = 'error: $e';
      rethrow;
    } finally {
      _uploadStartedAt = null;
      // Resume live monitoring now that the file is selected.
      if (conn.isOpen && _selectedPrinter == printer) {
        await _pollOnce(printer);
        _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (!_polling) _pollOnce(printer);
        });
      }
      notifyListeners();
    }
  }

  /// Estimated progress 0.0-1.0 while printing.
  ///
  /// The AD5X M119 reports MachineStatus but NOT layer/percent, so we
  /// estimate from elapsed time since BUILDING started. Callers with a known
  /// total print duration ([knownTotalSeconds]) should pass it for accuracy;
  /// otherwise we cap at a conservative default.
  double estimateProgress({int knownTotalSeconds = 4 * 3600}) {
    final start = _printStartedAt;
    if (start == null || _selectedPrinter == null) return 0.0;
    if (!(_selectedPrinter!.printing)) return 0.0;
    final elapsed = DateTime.now().difference(start).inSeconds;
    return (elapsed / knownTotalSeconds).clamp(0.0, 1.0);
  }

  // ----------------------------------------------------------------
  // LAN discovery — probe port 8899 + M601 handshake, identify via M115
  // ----------------------------------------------------------------

  Future<List<Printer>> scanLocalNetwork({String? subnet}) async {
    final baseIp = subnet ?? await _detectSubnet() ?? '192.168.0.';
    final discovered = <Printer>[];
    const batchSize = 32;
    for (int start = 1; start <= 254; start += batchSize) {
      final end = (start + batchSize - 1) > 254 ? 254 : start + batchSize - 1;
      final batch = <Future<Printer?>>[];
      for (int i = start; i <= end; i++) {
        batch.add(_probeOne('$baseIp$i'));
      }
      final found = await Future.wait(batch);
      found.whereType<Printer>().forEach(discovered.add);
    }
    return discovered;
  }

  Future<Printer?> _probeOne(String ip) async {
    try {
      final conn = FlashforgePrinter(ip);
      await conn.connect(timeoutMs: 400);
      final ok = await conn.handshake().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      if (!ok) {
        conn.dispose();
        return null;
      }
      var ident;
      try {
        ident = await conn.identify().timeout(const Duration(seconds: 2));
      } catch (_) {}
      conn.dispose();
      final type = ident?.machineType;
      if (type != null && !type.contains('AD5X')) {
        return null; // other Flashforge printers may answer M601 too
      }
      final name = ident?.name;
      return Printer(
        id: ident?.serial ?? ip,
        deviceID: ident?.serial ?? ip,
        name: (name != null && name.isNotEmpty) ? name : 'AD5X ($ip)',
        ip: ip,
        firmware: ident?.firmware,
        machineType: type,
        serial: ident?.serial,
        pairedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _detectSubnet() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address.toString();
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          final parts = ip.split('.');
          if (parts.length == 4) {
            return '${parts[0]}.${parts[1]}.${parts[2]}.';
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final o in parts) {
      final v = int.tryParse(o);
      if (v == null || v < 0 || v > 255) return false;
    }
    return true;
  }

  // ----------------------------------------------------------------
  // Persistence
  // ----------------------------------------------------------------

  Future<void> _savePrinters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'paired_printers', _printers.map((p) => p.toJson()).toList());
  }

  Future<void> loadPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('paired_printers') ?? [];
    _printers.clear();
    for (final json in jsonList) {
      try {
        _printers.add(Printer.fromJson(json));
      } catch (_) {}
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _teardownConnection();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
