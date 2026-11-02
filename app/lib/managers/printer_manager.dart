// Printer manager — handles AD5X discovery, pairing, and connection lifecycle

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:mdns/mdns.dart';
import 'printer.dart';

class PrinterManager extends ChangeNotifier {
  final List<Printer> _printers = [];
  Printer? _selectedPrinter;
  WebSocketChannel? _wsChannel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  Timer? _discoveryTimer;
  
  List<Printer> get printers => List.unmodifiable(_printers);
  Printer? get selectedPrinter => _selectedPrinter;
  bool get isConnected => _wsChannel != null;
  bool get isScanning => _discoveryTimer != null;
  
  // Pair a new AD5X printer using IP + Device ID
  Future<Printer?> pairPrinter(String ip, int port, String deviceID, String name) async {
    try {
      // Validate IP format
      if (!_isValidIp(ip)) {
        throw FormatException('Invalid IP address format');
      }
      
      // Check if already paired
      final existing = _printers.firstWhere(
        (p) => p.deviceID == deviceID || p.ip == ip,
        orElse: () => throw StateError('Printer already paired'),
      );
      return existing;
    } on StateError {
      // Create new printer entry
      final printer = Printer(
        id: deviceID,
        deviceID: deviceID,
        name: name.isNotEmpty ? name : 'AD5X ($deviceID)',
        ip: ip,
        port: port,
        pairedAt: DateTime.now(),
      );
      
      _printers.add(printer);
      _savePrinters();
      notifyListeners();
      return printer;
    }
    
    // Validate IP format
    if (!_isValidIp(ip)) {
      throw FormatException('Invalid IP address format');
    }
    
    // Check if already paired
    final existing = _printers.firstWhere(
      (p) => p.deviceID == deviceID || p.ip == ip,
      orElse: () => throw StateError('Printer already paired'),
    );
    return existing;
  }
  
  Future<Printer?> pairPrinter(String ip, int port, String deviceID, String name) async {
    try {
      // Validate IP format
      if (!_isValidIp(ip)) {
        throw FormatException('Invalid IP address format');
      }
      
      // Check if already paired
      final existing = _printers.firstWhere(
        (p) => p.deviceID == deviceID || p.ip == ip,
        orElse: () => throw StateError('Printer already paired'),
      );
      return existing;
    } on StateError {
      // Create new printer entry
      final printer = Printer(
        id: deviceID,
        deviceID: deviceID,
        name: name.isNotEmpty ? name : 'AD5X ($deviceID)',
        ip: ip,
        port: port,
        pairedAt: DateTime.now(),
      );
      
      _printers.add(printer);
      _savePrinters();
      notifyListeners();
      return printer;
    }
  }
  
  Future<void> connectToPrinter(Printer printer) async {
    if (_wsChannel != null) {
      await disconnect();
    }
    
    _selectedPrinter = printer;
    notifyListeners();
    
    try {
      final url = 'ws://${printer.ip}:${printer.port}';
      _wsChannel = WebSocketChannel.connect(Uri.parse(url));
      
      // Send Bambu login handshake
      _wsChannel!.sink.add(_buildLoginHandshake(printer.deviceID));
      
      // Start heartbeat
      _startHeartbeat();
      
      printer._online = true;
      notifyListeners();
    } catch (e) {
      _wsChannel = null;
      printer._online = false;
      notifyListeners();
      throw Exception('Failed to connect to $printer');
    }
  }
  
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsChannel?.sink.close();
    _wsChannel = null;
    _selectedPrinter?._online = false;
    notifyListeners();
  }
  
  // Local LAN discovery for AD5X printers
  Future<List<Printer>> scanLocalNetwork() async {
    final discovered = <Printer>[];
    
    try {
      // mDNS/Bonjour discovery for Bambu AD5X services
      final service = ServiceBrowser('_bambulab._tcp.local.');
      
      await for (final event in eventStream(service)) {
        if (event.type == ServiceEvent.added) {
          final resolver = ServiceResolver.resolve(event.name);
          
          await for (final response in eventStream(resolver)) {
            if (response.type == ServiceEvent.added) {
              final ip = response.hostAddress?.first?.address;
              if (ip != null) {
                final printer = Printer(
                  id: event.name,
                  deviceID: event.name,
                  name: response.fullName,
                  ip: ip,
                  pairedAt: DateTime.now(),
                );
                discovered.add(printer);
              }
            }
          }
        }
      }
    } catch (e) {
      // Fall back to IP scan if mDNS fails
      discovered.addAll(await _ipScan());
    }
    
    return discovered;
  }
  
  // IP subnet scan for Bambu/AD5X printers
  Future<List<Printer>> _ipScan() async {
    final discovered = <Printer>[];
    final baseIp = '192.168.1.'; // Configurable base subnet
    
    for (int i = 1; i <= 254; i++) {
      final ip = '$baseIp$i';
      try {
        final response = await http.get(
          Uri.parse('http://$ip:80'),
          timeout: Duration(milliseconds: 500),
        );
        
        if (response.statusCode == 200) {
          discovered.add(Printer(
            id: ip,
            deviceID: ip,
            name: 'AD5X ($ip)',
            ip: ip,
            pairedAt: DateTime.now(),
          ));
        }
      } catch (_) {
        continue;
      }
    }
    
    return discovered;
  }
  
  // Send control command to connected printer
  Future<void> sendCommand(String method, {Map<String, dynamic>? params}) async {
    if (_wsChannel == null || _selectedPrinter == null) {
      throw Exception('No printer connected');
    }
    
    final command = <String, dynamic>{
      'method': method,
      'id': 1,
      if (params != null) 'params': params,
    };
    
    _wsChannel!.sink.add(
      command.entries.map((e) => '"${e.key}":"${e.value}"').join(',')
    );
  }
  
  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(Duration(seconds: 10), (_) {
      if (_wsChannel != null) {
        _wsChannel!.sink.add('{"method":"heartbeat","id":0}');
      }
    });
  }
  
  bool _isValidIp(String ip) {
    final pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    return pattern.hasMatch(ip);
  }
  
  // Persist paired printers to local storage
  Future<void> _savePrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _printers.map((p) => p.toJson()).toList();
    await prefs.setStringList('paired_printers', jsonList);
  }
  
  // Load paired printers from storage
  Future<void> loadPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('paired_printers') ?? [];
    
    _printers.clear();
    for (final json in jsonList) {
      _printers.add(Printer.fromJson(json));
    }
    notifyListeners();
  }
  
  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }
}
