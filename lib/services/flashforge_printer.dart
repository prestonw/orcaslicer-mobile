// Flashforge AD5X LAN protocol client — raw TCP serial-over-TCP on port 8899.
//
// Reverse-engineered from printer-handshake.pcap (2026-11-02) and verified
// live against firmware v3.1.7. See protocol/flashforge-ad5x-lan.md.
//
// Wire format:
//   send: "~<M-CODE> ...\n\n"
//   recv: "CMD <code> Received.\r\n...lines...\r\nok\r\n"
//   Every response terminates with a line containing "ok".
//   Uploads (M28) stream raw bytes with NO acks until M29.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class FlashforgePrinter {
  final String host;
  final int port;

  Socket? _socket;
  final List<int> _rxBuf = [];
  Completer<bool>? _pendingAck;
  StreamSubscription? _sub;
  bool _locked = false; // true while an upload owns the socket

  FlashforgePrinter(this.host, {this.port = 8899});

  bool get isOpen => _socket != null;

  /// True while [uploadFile] owns the socket; other commands are refused.
  bool get locked => _locked;

  Future<void> connect({int timeoutMs = 5000}) async {
    _socket = await Socket.connect(host, port,
        timeout: Duration(milliseconds: timeoutMs));
    _socket!.setOption(SocketOption.tcpNoDelay, true);
    _sub = _socket!.listen(_onData,
        onDone: _onDone,
        onError: (Object e) {
      debugPrint('[FF] socket error: $e');
    });
  }

  void dispose() {
    _sub?.cancel();
    _socket?.destroy();
    _socket = null;
  }

  void _onDone() {
    _socket = null;
    final p = _pendingAck;
    _pendingAck = null;
    if (p != null && !p.isCompleted) p.complete(false);
  }

  void _onData(List<int> chunk) {
    _rxBuf.addAll(chunk);
    // Consume complete responses: each ends with a line "ok" (CRLF-terminated
    // per capture; tolerate bare LF).
    while (true) {
      final end = _findOkBoundary(_rxBuf);
      if (end < 0) break;
      final payload = _rxBuf.sublist(0, end);
      _rxBuf.removeRange(0, end);
      _completeWith(payload);
    }
  }

  /// Returns the exclusive end index of the first complete "ok" line, or -1
  /// when none is complete yet (caller waits for more data).
  int _findOkBoundary(List<int> buf) {
    for (int i = 0; i + 1 < buf.length; i++) {
      if (buf[i] != 0x6F /*o*/ || buf[i + 1] != 0x6B /*k*/) continue;
      // "ok" must be line-anchored: preceded by \r / \n / start of buffer.
      // (Otherwise we'd match "ok" inside e.g. gcode text during upload.)
      if (i > 0 && buf[i - 1] != 0x0D && buf[i - 1] != 0x0A) continue;
      if (i + 2 < buf.length) {
        if (buf[i + 2] == 0x0A) return i + 3; // "ok\n"
        if (buf[i + 2] == 0x0D && i + 3 < buf.length && buf[i + 3] == 0x0A) {
          return i + 4; // "ok\r\n"
        }
      }
      // "ok" at buffer edge — terminator may still be in flight; wait.
    }
    return -1;
  }

  void _completeWith(List<int> payload) {
    final p = _pendingAck;
    if (p != null && !p.isCompleted) {
      _lastResponse = utf8.decode(payload, allowMalformed: true);
      p.complete(true);
      // MUST reset, or the next send() sees a non-null (completed) completer
      // and throws "Command already in flight" forever.
      _pendingAck = null;
    }
  }

  String _lastResponse = '';
  String get lastResponse => _lastResponse;

  /// Send a command and wait for the "ok" response.
  /// Returns the full response text (or throws).
  Future<String> send(String command,
      {int timeoutMs = 4000, bool expectAck = true}) async {
    final s = _socket;
    if (s == null) throw StateError('Not connected');
    if (_locked) throw StateError('Socket busy (upload in progress)');
    if (expectAck && _pendingAck != null) {
      throw StateError('Command already in flight');
    }
    final ack = expectAck ? Completer<bool>() : null;
    _pendingAck = ack;
    s.add(utf8.encode('$command\n\n'));
    await s.flush();
    if (ack != null) {
      final ok = await ack.future.timeout(Duration(milliseconds: timeoutMs),
          onTimeout: () {
        _pendingAck = null;
        return false;
      });
      if (!ok) throw TimeoutException('Printer did not ack "$command"');
      return _lastResponse;
    }
    return '';
  }

  // ------------------------------------------------------------------
  // Protocol helpers (see protocol/flashforge-ad5x-lan.md)
  // ------------------------------------------------------------------

  /// `~M601 S1` — required handshake on every fresh connection.
  ///
  /// "Control Success" = machine is idle and accepted control. "Control
  /// failed" = machine is busy (e.g. currently BUILDING) — but it is ALIVE
  /// and still answering the protocol. Either way the printer is reachable,
  /// so gate connection liveness on a protocol ack, not the idle-only result.
  Future<bool> handshake() async {
    final r = await send('~M601 S1');
    debugPrint('[FF] handshake: $r');
    return r.contains('Control Success') ||
        r.contains('Control failed') ||
        r.contains('Received');
  }

  /// `~M115` — machine identity.
  Future<({String machineType, String name, String firmware,
          String serial})?>
      identify() async {
    final r = await send('~M115');
    String? t, n, f, s;
    for (final line in r.split('\n')) {
      final l = line.trim();
      if (l.startsWith('Machine Type:')) t = l.substring(13).trim();
      if (l.startsWith('Machine Name:')) n = l.substring(13).trim();
      if (l.startsWith('Firmware:')) f = l.substring(9).trim();
      if (l.startsWith('SN:')) s = l.substring(3).trim();
    }
    if (t == null) return null;
    return (
      machineType: t,
      name: n ?? '',
      firmware: f ?? '',
      serial: s ?? ''
    );
  }

  /// `~M27` — real SD print progress: "SD printing byte 53/100" + "Layer: 303/674".
  /// Only meaningful while printing; returns null when no SD activity is
  /// reported (machine idle).
  Future<({int bytePos, int totalBytes, int? layer, int? totalLayers})?>
      sdProgress() async {
    final r = await send('~M27');
    final bm = RegExp(r'SD printing byte (\d+)/(\d+)').firstMatch(r);
    if (bm == null) return null;
    final lm = RegExp(r'Layer: (\d+)/(\d+)').firstMatch(r);
    return (
      bytePos: int.parse(bm.group(1)!),
      totalBytes: int.parse(bm.group(2)!),
      layer: lm != null ? int.parse(lm.group(1)!) : null,
      totalLayers: lm != null ? int.parse(lm.group(2)!) : null,
    );
  }

  /// `~M114` — live toolhead position: "X:92.148 Y:110.801 Z:41.600 A:8986 B:0"
  /// The Z value is the real progress signal (compare against the max Z in
  /// the uploaded gcode).
  Future<({double x, double y, double z})?> position() async {
    final r = await send('~M114');
    final m = RegExp(r'X:([\d.-]+)\s+Y:([\d.-]+)\s+Z:([\d.-]+)').firstMatch(r);
    if (m == null) return null;
    double d(int i) => double.tryParse(m!.group(i)!) ?? 0;
    return (x: d(1), y: d(2), z: d(3));
  }

  /// `~M119` — live machine state + build-plate endstops.
  Future<({String machineStatus, String moveMode, bool ledOn,
          String currentFile,
          double? xMax, double? yMax, double? zMin})?>
      status() async {
    final r = await send('~M119');
    String? ms, mm;
    bool? led;
    String? file;
    double? xMax, yMax, zMin;
    for (final line in r.split('\n')) {
      final l = line.trim();
      if (l.startsWith('MachineStatus:')) ms = l.substring(14).trim();
      if (l.startsWith('MoveMode:')) mm = l.substring(9).trim();
      if (l.startsWith('LED:')) led = l.substring(4).trim() == '1';
      if (l.startsWith('CurrentFile:')) file = l.substring(12).trim();
      final es = RegExp(r'Endstop: X-max: ([\d.-]+) Y-max: ([\d.-]+) Z-min: ([\d.-]+)')
          .firstMatch(l);
      if (es != null) {
        xMax = double.tryParse(es.group(1)!);
        yMax = double.tryParse(es.group(2)!);
        zMin = double.tryParse(es.group(3)!);
      }
    }
    if (ms == null) return null;
    return (
      machineStatus: ms ?? '',
      moveMode: mm ?? '',
      ledOn: led ?? false,
      currentFile: file ?? '',
      xMax: xMax,
      yMax: yMax,
      zMin: zMin
    );
  }

  /// `~M105` — hotend/bed temperatures: "T0:199.7/200.0 T1:0.0/0.0 B:54.7/55.0"
  Future<({double hotend, double hotendTarget, double bed, double bedTarget})?>
  temperatures() async {
    final r = await send('~M105');
    final m = RegExp(
            r'T0:([\d.]+)/([\d.]+)\s+T1:([\d.]+)/([\d.]+)\s+B:([\d.]+)/([\d.]+)')
        .firstMatch(r);
    if (m == null) return null;
    double d(int i) => double.tryParse(m!.group(i)!) ?? 0;
    return (
      hotend: d(1),
      hotendTarget: d(2),
      bed: d(5),
      bedTarget: d(6)
    );
  }

  // ------------------------------------------------------------------
  // File upload: M28 <size> 0:/user/<name> + raw bytes + M29 + M23
  //
  // CRITICAL flow detail (from the capture): Flash Studio uses SEPARATE
  // connections per phase. M28+raw-data go on one socket which the printer
  // closes when the stream ends; M29 and M23 are each sent on a FRESH
  // connection. So we must not assume our main socket survives the transfer.
  //
  // Also: the printer writes to SD slowly (0.4-1.2 MB/s), so 25 MB takes
  // 20-60 s. Flash Studio's own uploads drop at ~90% because the client
  // applies a read timeout during the write phase. We use a generous
  // per-chunk write timeout and never wait for reads mid-stream.
  // ------------------------------------------------------------------

  /// Upload a local gcode file. [onProgress] receives (bytesSent, total).
  ///
  /// The printer writes to SD slower than the network, so "sent" means
  /// "handed to the socket", not "on card" — the UI shows elapsed time too.
  Future<void> uploadFile(
    File file,
    String remoteName, {
    void Function(int sent, int total)? onProgress,
    int chunkSize = 64 * 1024,
    int perChunkWriteMs = 60000,
  }) async {
    if (_locked) throw StateError('Upload already in progress');
    _locked = true;
    try {
      final bytes = await file.readAsBytes();
      final total = bytes.length;

      // 1+2. Open + stream on a dedicated connection (not the main one),
      //       mirroring Flash Studio's M28 connection.
      final streamSock = await Socket.connect(host, port,
          timeout: const Duration(seconds: 6));
      streamSock.setOption(SocketOption.tcpNoDelay, true);
      final rxSub = streamSock.listen((_) {/* swallow any stray bytes */},
          onDone: () {}, onError: (Object e) {});

      // M28 (single \n framing, as captured).
      final openResp = await _sendOn(
          streamSock, '~M28 $total 0:/user/$remoteName', 30000);
      if (!openResp.contains('Writing to file')) {
        rxSub.cancel();
        streamSock.destroy();
        throw StateError('Printer refused upload: $openResp');
      }

      // 3. raw stream (no framing, no per-chunk acks)
      int sent = 0;
      for (int off = 0; off < total; off += chunkSize) {
        final end = off + chunkSize > total ? total : off + chunkSize;
        streamSock.add(bytes.sublist(off, end));
        await streamSock.flush().timeout(Duration(milliseconds: perChunkWriteMs),
            onTimeout: () =>
                throw TimeoutException('Write stalled at $sent/$total bytes'));
        sent = end;
        onProgress?.call(sent, total);
      }
      // Let the stream connection settle, then close it (printer closes it).
      await streamSock.flush().catchError((_) {});
      await Future.delayed(const Duration(milliseconds: 300));
      await rxSub.cancel();
      streamSock.destroy();

      // 4. M29 (Done saving) on a FRESH connection.
      final closeResp =
          await _oneShot('~M29', expectContains: 'Done saving file',
              timeoutMs: 30000);
      if (closeResp == null) {
        throw StateError('Printer failed to finish file (M29)');
      }

      // 5. M23 (select file) on a FRESH connection.
      final selResp =
          await _oneShot('~M23 0:/user/$remoteName', timeoutMs: 15000);
      if (selResp == null || !selResp.contains('File selected')) {
        throw StateError('Printer did not select file: ${selResp ?? ''}');
      }
    } finally {
      _locked = false;
    }
  }

  /// Send a single command over [sock], wait for the "ok"-terminated reply.
  Future<String> _sendOn(Socket sock, String command, int timeoutMs) async {
    final buf = <int>[];
    final sub = sock.listen((c) => buf.addAll(c));
    sock.add(utf8.encode('$command\n'));
    await sock.flush();
    final deadline =
        DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final end = _findOkBoundary(buf);
      if (end > 0) {
        await sub.cancel();
        final text = utf8.decode(buf.sublist(0, end), allowMalformed: true);
        sock.destroy();
        return text;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await sub.cancel();
    sock.destroy();
    throw TimeoutException('Printer did not ack "$command"');
  }

  /// Open a fresh connection and send one command (no handshake — the
  /// captured M29/M23 connections carry only the single command).
  Future<String?> _oneShot(String command,
      {String? expectContains, int timeoutMs = 15000}) async {
    try {
      final sock = await Socket.connect(host, port,
          timeout: const Duration(seconds: 6));
      final r = await _sendOn(sock, command, timeoutMs);
      if (expectContains != null && !r.contains(expectContains)) return null;
      return r;
    } catch (_) {
      return null;
    }
  }
}
