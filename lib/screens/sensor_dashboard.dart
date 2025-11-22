import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../services/sensor_service.dart';

class SensorDashboard extends StatefulWidget {
  const SensorDashboard({super.key});

  @override
  State<SensorDashboard> createState() => _SensorDashboardState();
}

class _SensorDashboardState extends State<SensorDashboard> {
  final SensorService _sensorService = SensorService();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Sensor Data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          _buildSensorStream('Accelerometer', _sensorService.accelerometerStream),
          const Divider(),
          _buildSensorStream('Gyroscope', _sensorService.gyroscopeStream),
          const Divider(),
          _buildSensorStream('Magnetometer', _sensorService.magnetometerStream),
        ],
      ),
    );
  }

  Widget _buildSensorStream(String title, Stream<vector.Vector3> stream) {
    return StreamBuilder<vector.Vector3>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Text('$title: Waiting for data...');
        }
        final v = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('X: ${v.x.toStringAsFixed(3)}'),
            Text('Y: ${v.y.toStringAsFixed(3)}'),
            Text('Z: ${v.z.toStringAsFixed(3)}'),
          ],
        );
      },
    );
  }
}
