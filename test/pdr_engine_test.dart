import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_filter/logic/pdr_engine.dart';
import 'package:kalman_filter/logic/graph_models.dart';
import 'package:kalman_filter/services/sensor_service.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'dart:async';

class MockSensorService implements SensorService {
  final _accController = StreamController<vector.Vector3>.broadcast();
  final _magController = StreamController<vector.Vector3>.broadcast();

  final _gyroController = StreamController<vector.Vector3>.broadcast();

  @override
  Stream<vector.Vector3> get accelerometerStream => _accController.stream;

  @override
  Stream<vector.Vector3> get magnetometerStream => _magController.stream;

  @override
  Stream<vector.Vector3> get gyroscopeStream => _gyroController.stream;

  @override
  void startListening() {}

  @override
  void stopListening() {}

  @override
  void dispose() {
    _accController.close();
    _magController.close();
    _gyroController.close();
  }

  void emitAccelerometer(vector.Vector3 acc) {
    _accController.add(acc);
  }

  void emitMagnetometer(vector.Vector3 mag) {
    _magController.add(mag);
  }
}

void main() {
  group('PDREngine Tests', () {
    late PDREngine pdrEngine;
    late MockSensorService mockSensorService;

    setUp(() {
      mockSensorService = MockSensorService();
      pdrEngine = PDREngine(mockSensorService);
    });

    tearDown(() {
      pdrEngine.dispose();
    });

    test('PDR position is constrained to snapped position when snapping is enabled', () async {
      print("Step 1: Setup");
      // 1. Setup Graph: (0,0) -> (10,0)
      final startNode = Node(id: 'start', position: vector.Vector2(0, 0));
      final endNode = Node(id: 'end', position: vector.Vector2(10, 0));
      final edge = Edge(id: 'edge1', startNodeId: 'start', endNodeId: 'end');

      pdrEngine.graph.addNode(startNode);
      pdrEngine.graph.addNode(endNode);
      pdrEngine.graph.addEdge(edge);

      pdrEngine.start();
      
      // 2. Enable Snapping
      pdrEngine.toggleSnapping(); // Now true
      expect(pdrEngine.isSnapping, isTrue);

      print("Step 2: Simulate steps");
      // Mock Magnetometer for Heading 0 (North)
      mockSensorService.emitMagnetometer(vector.Vector3(10, 0, 0));
      
      // Mock Accelerometer for Step 1
      mockSensorService.emitAccelerometer(vector.Vector3(0, 12, 0));
      await Future.delayed(Duration(milliseconds: 50));
      mockSensorService.emitAccelerometer(vector.Vector3(0, 0, 9.8)); 
      
      await Future.delayed(Duration(milliseconds: 400));

      // Mock Accelerometer for Step 2
      mockSensorService.emitAccelerometer(vector.Vector3(0, 12, 0));
      await Future.delayed(Duration(milliseconds: 50));
      mockSensorService.emitAccelerometer(vector.Vector3(0, 0, 9.8));
      
      await Future.delayed(Duration(milliseconds: 400));

      // 4. Verify Position
      pdrEngine.toggleSnapping(); // Now false
      expect(pdrEngine.isSnapping, isFalse);

      print("Step 3: Verify drift");
      // Listen for the next position update BEFORE triggering it
      final positionFuture = pdrEngine.positionStream.first.timeout(Duration(seconds: 2));

      // Take one more step North
      mockSensorService.emitAccelerometer(vector.Vector3(0, 12, 0));
      await Future.delayed(Duration(milliseconds: 50));
      mockSensorService.emitAccelerometer(vector.Vector3(0, 0, 9.8));
      
      try {
        final position = await positionFuture;
        print("Final Position Y: ${position.y}");
        expect(position.y, greaterThan(-1.0), reason: "Position drifted too far! Internal state was not constrained.");
      } catch (e) {
        print("Timeout waiting for position update: $e");
        rethrow;
      }
    });
  });
}
