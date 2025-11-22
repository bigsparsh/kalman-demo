import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

class SensorService {
  // Singleton instance
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  // Stream controllers for processed data
  final _accelerometerController = BehaviorSubject<vector.Vector3>();
  final _magnetometerController = BehaviorSubject<vector.Vector3>();
  final _gyroscopeController = BehaviorSubject<vector.Vector3>();

  // Public streams
  Stream<vector.Vector3> get accelerometerStream => _accelerometerController.stream;
  Stream<vector.Vector3> get magnetometerStream => _magnetometerController.stream;
  Stream<vector.Vector3> get gyroscopeStream => _gyroscopeController.stream;

  StreamSubscription? _accSub;
  StreamSubscription? _magSub;
  StreamSubscription? _gyroSub;

  // Low-pass filter alpha (0 < alpha < 1). Lower = smoother but more lag.
  final double _alpha = 0.1;
  vector.Vector3? _lastAcc;

  void startListening() {
    _accSub = accelerometerEventStream().listen((event) {
      final rawAcc = vector.Vector3(event.x, event.y, event.z);
      
      // Apply Low-Pass Filter
      if (_lastAcc == null) {
        _lastAcc = rawAcc;
      } else {
        _lastAcc = _lastAcc! * (1 - _alpha) + rawAcc * _alpha;
      }
      
      _accelerometerController.add(_lastAcc!);
    });

    _magSub = magnetometerEventStream().listen((event) {
      _magnetometerController.add(vector.Vector3(event.x, event.y, event.z));
    });

    _gyroSub = gyroscopeEventStream().listen((event) {
      _gyroscopeController.add(vector.Vector3(event.x, event.y, event.z));
    });
  }

  void stopListening() {
    _accSub?.cancel();
    _magSub?.cancel();
    _gyroSub?.cancel();
    _lastAcc = null;
  }

  void dispose() {
    stopListening();
    _accelerometerController.close();
    _magnetometerController.close();
    _gyroscopeController.close();
  }
}
