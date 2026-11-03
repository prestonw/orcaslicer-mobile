// Printer manager — AD5X discovery, pairing, connection lifecycle, and live
// telemetry over the Flashforge 8899 LAN protocol (raw TCP serial).
//
// The previous implementation assumed a Bambu-style WebSocket/JSON protocol.
// The AD5X speaks raw G-code-over-TCP on port 8899 instead — see
// protocol/flashforge-ad5x-lan.md (reverse-engineered + verified live).

import 'dart:async';
import 'dart:convert';
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
      debugPrint('[FF] stage: tcp connected');
      final ok = await conn.handshake();
      if (!ok) {
        throw StateError('Handshake rejected by printer');
      }
      debugPrint('[FF] stage: handshake OK');
      _conn = conn;
      printer.markOnline();

      // Identify (best effort — don't fail the connection over it).
      try {
        final id = await conn.identify();
        debugPrint('[FF] stage: identify ${id != null ? id.machineType : 'null'}');
        if (id != null) {
          printer.applyM115(
              machineType: id.machineType,
              firmware: id.firmware,
              serial: id.serial);
        }
      } catch (e) {
        debugPrint('[FF] identify error: $e');
      }

      // First immediate poll, then periodic.
      await _pollOnce(printer);
      debugPrint('[FF] stage: first poll done, starting 5s loop');
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_polling) _pollOnce(printer);
      });
      notifyListeners();
    } catch (e) {
      debugPrint('[FF] connect failed ${printer.ip}:${printer.port} -> $e');
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
          xMax: st.xMax,
          yMax: st.yMax,
          zMin: st.zMin,
        );
        // Time-left estimate: if the total duration is unknown (print started
        // outside the app), recover it from the "6h6m" token in the file name.
        if (st.machineStatus == 'BUILDING' &&
            printer.estimatedTotalSeconds == null &&
            st.currentFile.isNotEmpty) {
          final total = _parseTotalFromFilename(st.currentFile);
          if (total != null && total > 0) {
            printer.estimatedTotalSeconds = total.toDouble();
          }
        }
        if (st.machineStatus != 'BUILDING') {
          printer.estimatedTotalSeconds = null;
        }
        // Track when a print starts (client-side cross-check).
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
      // M114 Z position + M27 SD byte/layer = real progress while printing.
      if (st != null && st.machineStatus == 'BUILDING') {
        try {
          final pos = await conn.position();
          if (pos != null) printer.applyM114(zPosition: pos.z);
        } catch (_) {}
        try {
          final sd = await conn.sdProgress();
          if (sd != null) {
            printer.applyM27(
              bytePos: sd.bytePos,
              totalBytes: sd.totalBytes,
              layer: sd.layer,
              totalLayers: sd.totalLayers,
            );
          }
        } catch (_) {}
      }
      notifyListeners();
    } catch (e) {
      // Socket died mid-poll — the listener's onDone path handles it;
      // schedule a reconnect.
      debugPrint('[FF] poll error: $e');
      _scheduleReconnect(printer);
    } finally {
      _polling = false;
    }
  }

  /// Orca/Flashforge gcode embeds the model preview as a base64 PNG between
  /// "; thumbnail begin WxH" and "; thumbnail end" — decode the first block.
  List<int>? _scanThumbnail(File file) {
    try {
      final begin = RegExp(r';\s*thumbnail begin \d+x\d+');
      final b64 = <String>[];
      var inBlock = false;
      for (final line in file.readAsLinesSync()) {
        if (!inBlock) {
          if (begin.hasMatch(line)) inBlock = true;
          continue;
        }
        if (RegExp(r'thumbnail end').hasMatch(line)) break;
        final t = line.trim().replaceFirst(RegExp(r'^;\s*'), '');
        if (t.isEmpty) continue;
        if (RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(t)) b64.add(t);
        if (b64.join('').length > 1 << 20) break; // 1MB cap
      }
      if (b64.isEmpty) return null;
      final bytes = base64Decode(b64.join(''));
      return bytes.isNotEmpty ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  /// Decoded gcode model-preview PNG bytes for the selected printer (set by
  /// uploadGcode's thumbnail scan; null when the file had no preview).
  List<int>? modelImage;

  /// "6h 5m 49s" / "6h5m" / "32m 10s" -> seconds, or null.
  static int? _parseDuration(String s) {
    final h = RegExp(r'(\d+)\s*h').firstMatch(s);
    final m = RegExp(r'(\d+)\s*m').firstMatch(s);
    final sec = RegExp(r'(\d+)\s*s').firstMatch(s);
    if (h == null && m == null && sec == null) return null;
    return (h != null ? int.parse(h.group(1)!) * 3600 : 0) +
        (m != null ? int.parse(m.group(1)!) * 60 : 0) +
        (sec != null ? int.parse(sec.group(1)!) : 0);
  }

  /// Total duration from the gcode header:
  /// "; estimated printing time (normal mode) = 6h 5m 49s".
  int? _scanEstimatedTotal(File file) {
    try {
      for (final line in file.readAsLinesSync()) {
        if (!line.contains('estimated printing time')) continue;
        final eq = line.indexOf('=');
        if (eq < 0) continue;
        final d = _parseDuration(line.substring(eq + 1));
        if (d != null && d > 0) return d;
      }
    } catch (_) {}
    return null;
  }

  /// Filename convention "Body15_PLA_6h6m.gcode" -> seconds, or null.
  int? _parseTotalFromFilename(String name) {
    final m = RegExp(r'(\d+)\s*h\s*(\d+)\s*m').firstMatch(name);
    if (m == null) return null;
    return int.parse(m.group(1)!) * 3600 + int.parse(m.group(2)!) * 60;
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
    // Scan the gcode for the max Z (Z-based progress denominator) and for the
    // embedded model-preview PNG (Flashforge/Orca thumbnail block).
    final maxZ = _scanMaxZ(file);
    if (maxZ != null) printer.applyM114(zPosition: printer.zPosition, maxZ: maxZ);
    modelImage = _scanThumbnail(file);
    // Slicer's own total duration — much better than a name guess when present.
    final total = _scanEstimatedTotal(file);
    if (total != null) printer.estimatedTotalSeconds = total.toDouble();

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

  /// Real progress 0.0-1.0 while printing. Prefers M27 (SD byte position —
  /// exact for any file the printer is playing); falls back to the Z estimate.
  double? estimateProgress() {
    final p = _selectedPrinter;
    if (p == null) return null;
    return p.sdProgress ?? p.zProgress;
  }

  /// Scan a gcode file for the largest Z coordinate (progress denominator).
  double? _scanMaxZ(File file) {
    try {
      double maxZ = 0;
      for (final line in file.readAsLinesSync()) {
        if (!line.contains('Z')) continue;
        final m = RegExp(r'Z(\d+\.?\d*)').firstMatch(line);
        if (m != null) {
          final z = double.tryParse(m.group(1)!);
          if (z != null && z > maxZ) maxZ = z;
        }
      }
      return maxZ > 0 ? maxZ : null;
    } catch (_) {
      return null;
    }
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
    var migrated = false;
    for (final json in jsonList) {
      try {
        final p = Printer.fromJson(json);
        // The AD5X LAN protocol only exists on 8899. Entries saved by older
        // app versions may carry a stale port (e.g. 80) — normalize it.
        if (p.port != 8899) {
          p.port = 8899;
          migrated = true;
        }
        _printers.add(p);
      } catch (_) {}
    }
    if (migrated) await _savePrinters();
    notifyListeners();
  }

  @override
  void dispose() {
    _teardownConnection();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
