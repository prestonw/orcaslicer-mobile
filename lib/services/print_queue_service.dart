// Print queue service — manages queued print jobs with prioritization

import 'dart:io';
import 'package:flutter/material.dart';
import 'slicer_service.dart';

class PrintJob {
  final String id;
  final String fileName;
  final String printerId;
  final DateTime queuedAt;
  final double fileSize; // MB
  final String status; // 'queued', 'printing', 'paused', 'completed', 'failed'
  final SlicerConfig? config;
  
  PrintJob({
    required this.id,
    required this.fileName,
    required this.printerId,
    required this.queuedAt,
    this.fileSize = 0.0,
    this.status = 'queued',
    this.config,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fileName': fileName,
      'printerId': printerId,
      'queuedAt': queuedAt.toIso8601String(),
      'fileSize': fileSize,
      'status': status,
    };
  }
  
  factory PrintJob.fromMap(Map<String, dynamic> map) {
    return PrintJob(
      id: map['id'] as String,
      fileName: map['fileName'] as String,
      printerId: map['printerId'] as String,
      queuedAt: DateTime.parse(map['queuedAt'] as String),
      fileSize: (map['fileSize'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] as String? ?? 'queued',
    );
  }
}

class PrintQueueProvider extends ChangeNotifier {
  final List<PrintJob> _queue = [];
  String? _selectedPrinter;
  
  List<PrintJob> get queue => List.unmodifiable(_queue);
  String? get selectedPrinter => _selectedPrinter;
  
  void setPrinter(String printerId) {
    _selectedPrinter = printerId;
    notifyListeners();
  }
  
  // Add file to print queue
  Future<void> addToQueue(File file, String printerId) async {
    final job = PrintJob(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fileName: file.path.split('/').last,
      printerId: printerId,
      queuedAt: DateTime.now(),
      fileSize: await file.length() / (1024 * 1024),
    );
    
    _queue.add(job);
    notifyListeners();
  }
  
  // Remove job from queue
  void removeFromQueue(String jobId) {
    _queue.removeWhere((job) => job.id == jobId);
    notifyListeners();
  }
  
  // Start next job in queue
  Future<void> startNextJob() async {
    if (_queue.isEmpty || _selectedPrinter == null) return;
    
    final job = _queue.first;
    // TODO: send to printer via WebSocket
    
    _queue.removeAt(0);
    notifyListeners();
  }
  
  // Load queue from local storage
  Future<void> loadQueue() async {
    // TODO: implement SharedPreferences loading
    notifyListeners();
  }
}
