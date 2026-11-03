// Printer model — Flashforge AD5X state as reported over the 8899 LAN protocol
// (see /tmp/orca-build/protocol/flashforge-ad5x-lan.md)

import 'dart:convert';

class Printer {
  final String id;
  final String deviceID;
  final String name;
  final String ip;
  final int port;
  String? firmware;
  String? serial;
  String? machineType;
  final DateTime pairedAt;

  bool _online = false;
  String _machineStatus = 'UNKNOWN'; // READY | BUILDING | ...
  String _moveMode = '';
  bool _ledOn = false;
  String _currentFile = '';
  double _hotendTemp = 0.0;
  double _hotendTarget = 0.0;
  double _bedTemp = 0.0;
  double _bedTarget = 0.0;
  double _zPosition = 0.0;
  double? _maxZ; // from the uploaded gcode (scan) — real progress = z/maxZ

  Printer({
    required this.id,
    required this.deviceID,
    required this.name,
    required this.ip,
    this.port = 8899,
    this.firmware,
    this.serial,
    this.machineType,
    required this.pairedAt,
  });

  bool get online => _online;
  String get machineStatus => _machineStatus;
  String get moveMode => _moveMode;
  bool get ledOn => _ledOn;
  String get currentFile => _currentFile;
  double get hotendTemp => _hotendTemp;
  double get hotendTarget => _hotendTarget;
  double get bedTemp => _bedTemp;
  double get bedTarget => _bedTarget;
  double get zPosition => _zPosition;
  double? get maxZ => _maxZ;

  /// True while actively printing (M119 MachineStatus == BUILDING).
  bool get printing => _machineStatus == 'BUILDING';

  /// Human label for the machine status.
  String get statusLabel {
    switch (_machineStatus) {
      case 'READY': return 'Ready';
      case 'BUILDING': return 'Printing';
      case 'IDLE': return 'Idle';
      case 'ERROR': return 'Error';
      case 'OFFLINE': return 'Offline';
      default: return _machineStatus.isEmpty ? 'Unknown' : _machineStatus;
    }
  }

  void markOnline() { _online = true; }

  void markOffline() {
    _online = false;
    _machineStatus = 'OFFLINE';
    _currentFile = '';
  }

  void applyM119({
    required String machineStatus,
    required String moveMode,
    required bool ledOn,
    required String currentFile,
  }) {
    _online = true;
    _machineStatus = machineStatus;
    _moveMode = moveMode;
    _ledOn = ledOn;
    _currentFile = currentFile;
  }

  void applyM114({required double zPosition, double? maxZ}) {
    _online = true;
    _zPosition = zPosition;
    if (maxZ != null && maxZ > 0) _maxZ = maxZ;
  }

  /// Real progress from Z position, or null if maxZ unknown / not printing.
  double? get zProgress {
    final m = _maxZ;
    if (m == null || m <= 0 || _machineStatus != 'BUILDING') return null;
    return (_zPosition / m).clamp(0.0, 1.0);
  }

  void applyM105({
    required double hotendTemp,
    required double hotendTarget,
    required double bedTemp,
    required double bedTarget,
  }) {
    _online = true;
    _hotendTemp = hotendTemp;
    _hotendTarget = hotendTarget;
    _bedTemp = bedTemp;
    _bedTarget = bedTarget;
  }

  void applyM115({String? machineType, String? firmware, String? serial}) {
    _online = true;
    if (machineType != null && machineType.isNotEmpty) this.machineType = machineType;
    if (firmware != null && firmware.isNotEmpty) this.firmware = firmware;
    if (serial != null && serial.isNotEmpty) this.serial = serial;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deviceID': deviceID,
      'name': name,
      'ip': ip,
      'port': port,
      'firmware': firmware,
      'serial': serial,
      'machineType': machineType,
      'pairedAt': pairedAt.toIso8601String(),
    };
  }

  factory Printer.fromMap(Map<String, dynamic> map) {
    return Printer(
      id: map['id'] as String,
      deviceID: map['deviceID'] as String? ?? (map['id'] as String),
      name: map['name'] as String? ?? 'Printer',
      ip: map['ip'] as String,
      port: map['port'] as int? ?? 8899,
      firmware: map['firmware'] as String?,
      serial: map['serial'] as String?,
      machineType: map['machineType'] as String?,
      pairedAt: map['pairedAt'] != null
          ? DateTime.parse(map['pairedAt'] as String)
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());
  factory Printer.fromJson(String source) => Printer.fromMap(json.decode(source));
}
