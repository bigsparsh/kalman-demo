import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../logic/pdr_engine.dart';
import '../services/sensor_service.dart';
import 'sensor_dashboard.dart';

class PositioningScreen extends StatefulWidget {
  const PositioningScreen({super.key});

  @override
  State<PositioningScreen> createState() => _PositioningScreenState();
}

class _PositioningScreenState extends State<PositioningScreen> {
  late PDREngine _pdrEngine;
  final List<vector.Vector2> _path = [];
  vector.Vector2 _currentPosition = vector.Vector2.zero();
  double _currentHeading = 0.0;
  int _stepCount = 0;

  @override
  void initState() {
    super.initState();
    _pdrEngine = PDREngine(SensorService());
    _pdrEngine.start();

    _pdrEngine.positionStream.listen((pos) {
      setState(() {
        _currentPosition = pos;
        _path.add(pos);
      });
    });

    _pdrEngine.headingStream.listen((heading) {
      setState(() {
        _currentHeading = heading;
      });
    });

    _pdrEngine.stepStream.listen((steps) {
      setState(() {
        _stepCount = steps;
      });
    });
    
    _pdrEngine.pathStatusStream.listen((_) {
      setState(() {
        // Path generated, trigger repaint
      });
    });
  }

  @override
  void dispose() {
    _pdrEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Indoor Positioning'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) => const SensorDashboard(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map View
          Positioned.fill(
            child: CustomPaint(
              painter: PathPainter(
                path: _path,
                currentPosition: _currentPosition,
                heading: _currentHeading,
                definedPathStart: _pdrEngine.pathStart,
                definedPathEnd: _pdrEngine.pathEnd,
              ),
            ),
          ),
          // Stats Overlay
          Positioned(
            top: 20,
            left: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Steps: $_stepCount'),
                    Text('X: ${_currentPosition.x.toStringAsFixed(2)} m'),
                    Text('Y: ${_currentPosition.y.toStringAsFixed(2)} m'),
                    Text('Heading: ${(_currentHeading * 180 / pi).toStringAsFixed(0)}°'),
                  ],
                ),
              ),
            ),
          ),
          // Controls Overlay
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton.extended(
                  onPressed: () {
                    setState(() {
                      _pdrEngine.toggleRecording();
                    });
                  },
                  label: Text(_pdrEngine.isRecording ? 'Stop Recording' : 'Record Path'),
                  icon: Icon(_pdrEngine.isRecording ? Icons.stop : Icons.fiber_manual_record),
                  backgroundColor: _pdrEngine.isRecording ? Colors.red : null,
                ),
                FloatingActionButton.extended(
                  onPressed: _pdrEngine.hasPath ? () {
                    setState(() {
                      _pdrEngine.toggleSnapping();
                    });
                  } : null,
                  label: Text(_pdrEngine.isSnapping ? 'Disable Snap' : 'Enable Snap'),
                  icon: Icon(_pdrEngine.isSnapping ? Icons.link_off : Icons.link),
                  backgroundColor: _pdrEngine.isSnapping ? Colors.green : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PathPainter extends CustomPainter {
  final List<vector.Vector2> path;
  final vector.Vector2 currentPosition;
  final double heading;
  final vector.Vector2? definedPathStart;
  final vector.Vector2? definedPathEnd;

  PathPainter({
    required this.path,
    required this.currentPosition,
    required this.heading,
    this.definedPathStart,
    this.definedPathEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Transform canvas to keep current position at center
    canvas.translate(center.dx, center.dy);
    
    double scale = 50.0;
    canvas.scale(scale, scale);
    canvas.translate(-currentPosition.x, -currentPosition.y);

    // Draw Defined Path (if exists)
    if (definedPathStart != null && definedPathEnd != null) {
      final definedPathPaint = Paint()
        ..color = Colors.green.withValues(alpha: 0.5)
        ..strokeWidth = 0.3 // Thicker line
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      
      canvas.drawLine(
        Offset(definedPathStart!.x, definedPathStart!.y),
        Offset(definedPathEnd!.x, definedPathEnd!.y),
        definedPathPaint,
      );
    }

    // Draw Walked Path
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 0.1 // Relative to scale
      ..style = PaintingStyle.stroke;

    if (path.isNotEmpty) {
      final pathObj = Path();
      pathObj.moveTo(path.first.x, path.first.y);
      for (var point in path) {
        pathObj.lineTo(point.x, point.y);
      }
      canvas.drawPath(pathObj, paint);
    }

    // Draw Marker (at currentPosition)
    final markerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(currentPosition.x, currentPosition.y), 0.2, markerPaint);

    // Draw Heading Indicator
    final headingPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 0.05
      ..style = PaintingStyle.stroke;
    
    double indicatorLen = 0.5;
    canvas.drawLine(
      Offset(currentPosition.x, currentPosition.y),
      Offset(
        currentPosition.x + indicatorLen * sin(heading),
        currentPosition.y - indicatorLen * cos(heading),
      ),
      headingPaint,
    );
  }

  @override
  bool shouldRepaint(covariant PathPainter oldDelegate) => true;
}
