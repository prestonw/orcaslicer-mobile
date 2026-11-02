// Slicer service — interface for headless OrcaSlicer API calls

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class SlicerConfig {
  final String profile;
  final double layerHeight;
  final double wallThickness;
  final int infillDensity;
  final String infillPattern;
  final int nozzleTemperature;
  final int bedTemperature;
  final String printerModel;
  
  SlicerConfig({
    this.profile = 'default',
    this.layerHeight = 0.2,
    this.wallThickness = 1.2,
    this.infillDensity = 15,
    this.infillPattern = 'gyroid',
    this.nozzleTemperature = 200,
    this.bedTemperature = 60,
    this.printerModel = 'AD5X',
  });
  
  Map<String, dynamic> toMap() {
    return {
      'profile': profile,
      'layer_height': layerHeight,
      'wall_thickness': wallThickness,
      'infill_density': infillDensity,
      'infill_pattern': infillPattern,
      'nozzle_temperature': nozzleTemperature,
      'bed_temperature': bedTemperature,
      'printer_model': printerModel,
    };
  }
}

class SlicerService {
  final String apiUrl;
  
  SlicerService({this.apiUrl = 'http://localhost:8000'});
  
  // Send STL/3MF file to headless slicer for G-code generation
  Future<String> sliceFile(
    File file,
    SlicerConfig config,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiUrl/api/v1/slice'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('model', file.path),
      );
      
      request.fields.addAll({
        'profile': config.profile,
        'layer_height': config.layerHeight.toString(),
        'wall_thickness': config.wallThickness.toString(),
        'infill_density': config.infillDensity.toString(),
        'infill_pattern': config.infillPattern,
        'nozzle_temperature': config.nozzleTemperature.toString(),
        'bed_temperature': config.bedTemperature.toString(),
        'printer_model': config.printerModel,
      });
      
      final response = await request.send();
      
      if (response.statusCode == 200) {
        final body = await response.stream.bytesToString();
        final data = jsonDecode(body);
        return data['gcode_path'] as String;
      } else {
        throw Exception('Slicing failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Slicer error: $e');
    }
  }
  
  // Upload G-code to printer
  Future<bool> uploadGcode(String printerIp, String gcodePath) async {
    try {
      final file = File(gcodePath);
      if (!await file.exists()) {
        throw Exception('G-code file not found');
      }
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://$printerIp/api/upload'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('gcode', gcodePath),
      );
      
      final response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      print('Upload error: $e');
      return false;
    }
  }
  
  // Start print job on printer
  Future<bool> startPrint(String printerIp, String fileName) async {
    try {
      final response = await http.post(
        Uri.parse('http://$printerIp/api/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'file': fileName}),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('Start print error: $e');
      return false;
    }
  }
}
