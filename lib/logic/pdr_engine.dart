import 'dart:async';
import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../services/sensor_service.dart';

import 'path_manager.dart';

class PDREngine {
  final SensorService _sensorService;
  final PathManager _pathManager = PathManager();
  
  // PDR State
  double _currentX = 0.0;
  double _currentY = 0.0;
  final double _stepLength = 0.7; // Average step length in meters
  double _heading = 0.0; // Radians, 0 = North

  // Recording & Snapping State
  bool _isRecording = false;
  bool _isSnapping = false;

  bool get isRecording => _isRecording;
  bool get isSnapping => _isSnapping;
  bool get hasPath => _pathManager.hasPath;
  vector.Vector2? get pathStart => _pathManager.pathStart;
  vector.Vector2? get pathEnd => _pathManager.pathEnd;

  // Step Detection Constants
  final double _stepThreshold = 11.0; // Magnitude threshold for step
  final int _minStepIntervalMs = 400; // Minimum time between steps
  int _lastStepTime = 0;
  bool _isStepPeak = false;

  // Kalman Filter State (Simple 1D for Heading)
  double _kalmanP = 1.0; // Error covariance
  final double _kalmanQ = 0.01; // Process noise covariance
  final double _kalmanR = 0.1; // Measurement noise covariance
  double _kalmanX = 0.0; // Estimated value (heading)

  // Stream Controllers
  final _positionController = StreamController<vector.Vector2>.broadcast();
  final _stepController = StreamController<int>.broadcast();
  final _headingController = StreamController<double>.broadcast();
  final _pathStatusController = StreamController<void>.broadcast(); // Notify when path changes

  Stream<vector.Vector2> get positionStream => _positionController.stream;
  Stream<int> get stepStream => _stepController.stream;
  Stream<double> get headingStream => _headingController.stream;
  Stream<void> get pathStatusStream => _pathStatusController.stream;

  int _stepCount = 0;
  vector.Vector3? _lastAcc;
  vector.Vector3? _lastMag;

  PDREngine(this._sensorService);

  void start() {
    _sensorService.startListening();

    _sensorService.accelerometerStream.listen((acc) {
      _lastAcc = acc;
      _detectStep(acc);
      _updateHeading();
    });

    _sensorService.magnetometerStream.listen((mag) {
      _lastMag = mag;
      _updateHeading();
    });
  }

  void toggleRecording() {
    _isRecording = !_isRecording;
    if (_isRecording) {
      _pathManager.clearRecording();
      // Also reset position? Maybe not, user might want to start recording from current pos.
      // But usually recording a path implies defining the coordinate system.
      // For simplicity, let's keep current position but start adding points.
    } else {
      // Stop recording, generate path
      _pathManager.generatePath();
      _pathStatusController.add(null);
    }
  }

  void toggleSnapping() {
    _isSnapping = !_isSnapping;
  }

  void _detectStep(vector.Vector3 acc) {
    double magnitude = acc.length;
    int now = DateTime.now().millisecondsSinceEpoch;

    if (magnitude > _stepThreshold) {
      if (!_isStepPeak && (now - _lastStepTime) > _minStepIntervalMs) {
        _isStepPeak = true;
        _lastStepTime = now;
        _stepCount++;
        _stepController.add(_stepCount);
        _updatePosition();
      }
    } else {
      _isStepPeak = false;
    }
  }

  void _updateHeading() {
    if (_lastAcc == null || _lastMag == null) return;

    // Calculate rotation matrix
    // This is a simplified calculation. For robust PDR, we need full tilt compensation.
    // Pitch and Roll from Accelerometer
    double normAcc = _lastAcc!.length;
    double ax = _lastAcc!.x / normAcc;
    double ay = _lastAcc!.y / normAcc;
    double az = _lastAcc!.z / normAcc;

    double pitch = asin(-ay);
    double roll = atan2(ax, az);

    // Magnetometer compensation
    double mx = _lastMag!.x;
    double my = _lastMag!.y;
    double mz = _lastMag!.z;

    double mx2 = mx * cos(pitch) + mz * sin(pitch);
    double my2 = mx * sin(roll) * sin(pitch) + my * cos(roll) - mz * sin(roll) * cos(pitch);
    
    double rawHeading = atan2(-my2, mx2);

    // Apply Kalman Filter to Heading
    _heading = _kalmanFilter(rawHeading);
    _headingController.add(_heading);
  }

  double _kalmanFilter(double measurement) {
    // Prediction Update
    // _kalmanX = _kalmanX; // No control input
    _kalmanP = _kalmanP + _kalmanQ;

    // Measurement Update
    double k = _kalmanP / (_kalmanP + _kalmanR);
    
    // Handle wrapping for heading (so 359 -> 1 doesn't go the long way)
    double diff = measurement - _kalmanX;
    if (diff > pi) diff -= 2 * pi;
    if (diff < -pi) diff += 2 * pi;

    _kalmanX = _kalmanX + k * diff;
    _kalmanP = (1 - k) * _kalmanP;

    // Normalize result
    if (_kalmanX > pi) _kalmanX -= 2 * pi;
    if (_kalmanX < -pi) _kalmanX += 2 * pi;

    return _kalmanX;
  }

  void _updatePosition() {
    // Update position based on step and current heading
    _currentX += _stepLength * sin(_heading); // X is East-West
    _currentY -= _stepLength * cos(_heading); // Y is North-South (Screen Y is down)

    vector.Vector2 rawPos = vector.Vector2(_currentX, _currentY);

    if (_isRecording) {
      _pathManager.addPoint(rawPos);
    }

    vector.Vector2 outputPos = rawPos;
    if (_isSnapping) {
      outputPos = _pathManager.snapPoint(rawPos);
    }

    _positionController.add(outputPos);
  }

  void stop() {
    _sensorService.stopListening();
  }

  void dispose() {
    stop();
    _positionController.close();
    _stepController.close();
    _headingController.close();
    _pathStatusController.close();
  }
}
