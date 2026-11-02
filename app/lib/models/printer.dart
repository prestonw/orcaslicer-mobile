// Printer model representing paired AD5X printers

import 'dart:convert';
import 'package:flutter/foundation.dart';

class Printer extends ChangeNotifier {
  final String id;
  final String deviceID;
  final String name;
  final String ip;
  final int port;
  final String? firmware;
  final DateTime pairedAt;
  
  bool _online = false;
  bool _printing = false;
  double _progress = 0.0;
  double _hotendTemp = 0.0;
  double _bedTemp = 0.0;
  int _fanSpeed = 0;
  String _status = 'offline';
  
  Printer({
    required this.id,
    required this.deviceID,
    required this.name,
    required this.ip,
    this.port = 80,
    this.firmware,
    required this.pairedAt,
  });
  
  bool get online => _online;
  bool get printing => _printing;
  double get progress => _progress;
  double get hotendTemp => _hotendTemp;
  double get bedTemp => _bedTemp;
  int get fanSpeed => _fanSpeed;
  String get status => _status;
  
  // Update printer state from Bambu protocol telemetry
  void updateState(Map<String, dynamic> telemetry) {
    _online = true;
    _printing = telemetry['printing'] ?? false;
    _progress = (telemetry['progress'] as num?)?.toDouble() ?? 0.0;
    _hotendTemp = (telemetry['hotend_temp'] as num?)?.toDouble() ?? 0.0;
    _bedTemp = (telemetry['bed_temp'] as num?)?.toDouble() ?? 0.0;
    _fanSpeed = telemetry['fan_speed'] as int? ?? 0;
    _status = telemetry['status'] as String? ?? 'ready';
    notifyListeners();
  }
  
  void markOffline() {
    _online = false;
    _printing = false;
    notifyListeners();
  }
  
  // Save printer config to local storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'deviceID': deviceID,
      'name': name,
      'ip': ip,
      'port': port,
      'firmware': firmware,
      'pairedAt': pairedAt.toIso8601String(),
    };
  }
  
  factory Printer.fromMap(Map<String, dynamic> map) {
    return Printer(
      id: map['id'] as String,
      deviceID: map['deviceID'] as String,
      name: map['name'] as String,
      ip: map['ip'] as String,
      port: map['port'] as int? ?? 80,
      firmware: map['firmware'] as String?,
      pairedAt: DateTime.parse(map['pairedAt'] as String),
    );
  }
  
  String toJson() => json.encode(toMap());
  factory Printer.fromJson(String source) => Printer.fromMap(json.decode(source));
}
