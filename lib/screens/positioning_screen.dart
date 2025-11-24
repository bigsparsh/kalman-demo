import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../logic/pdr_engine.dart';
import '../services/sensor_service.dart';
import '../logic/graph_models.dart';
import 'sensor_dashboard.dart';

class TrailPoint {
  final vector.Vector2 position;
  final DateTime timestamp;

  TrailPoint(this.position, this.timestamp);
}

class PositioningScreen extends StatefulWidget {
  const PositioningScreen({super.key});

  @override
  State<PositioningScreen> createState() => _PositioningScreenState();
}

class _PositioningScreenState extends State<PositioningScreen> {
  late PDREngine _pdrEngine;
  final List<TrailPoint> _path = [];
  vector.Vector2 _currentPosition = vector.Vector2.zero();
  double _currentHeading = 0.0;
  int _stepCount = 0;
  Timer? _trailTimer;
  static const Duration _trailDuration = Duration(seconds: 5);
  static const double _jumpThreshold = 1.0; // Meters

  @override
  void initState() {
    super.initState();
    _pdrEngine = PDREngine(SensorService());
    _pdrEngine.start();

    // Timer to clean up old trail points
    _trailTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final now = DateTime.now();
      setState(() {
        _path.removeWhere((p) => now.difference(p.timestamp) > _trailDuration);
      });
    });

    _pdrEngine.positionStream.listen((pos) {
      setState(() {
        // Check for jump
        if (_path.isNotEmpty) {
          final lastPos = _path.last.position;
          if ((pos - lastPos).length > _jumpThreshold && _pdrEngine.hasPath) {
            // Jump detected, try to find path
            final interpolatedPath = _pdrEngine.findPath(lastPos, pos);
            for (var p in interpolatedPath) {
              _path.add(TrailPoint(p, DateTime.now()));
            }
          } else {
            _path.add(TrailPoint(pos, DateTime.now()));
          }
        } else {
          _path.add(TrailPoint(pos, DateTime.now()));
        }
        
        _currentPosition = pos;
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
    _trailTimer?.cancel();
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
                graph: _pdrEngine.hasPath ? _pdrEngine.graph : null,
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
  final List<TrailPoint> path;
  final vector.Vector2 currentPosition;
  final double heading;
  final Graph? graph;

  PathPainter({
    required this.path,
    required this.currentPosition,
    required this.heading,
    this.graph,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Transform canvas to keep current position at center
    canvas.translate(center.dx, center.dy);
    
    double scale = 50.0;
    canvas.scale(scale, scale);
    canvas.translate(-currentPosition.x, -currentPosition.y);

    // Draw Graph (if exists)
    if (graph != null) {
      final edgePaint = Paint()
        ..color = Colors.green.withValues(alpha: 0.5)
        ..strokeWidth = 0.3 // Thicker line
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      
      final nodePaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.fill;

      for (var edge in graph!.edges.values) {
        final startNode = graph!.nodes[edge.startNodeId];
        final endNode = graph!.nodes[edge.endNodeId];

        if (startNode != null && endNode != null) {
          canvas.drawLine(
            Offset(startNode.position.x, startNode.position.y),
            Offset(endNode.position.x, endNode.position.y),
            edgePaint,
          );
        }
      }

      for (var node in graph!.nodes.values) {
        canvas.drawCircle(
          Offset(node.position.x, node.position.y),
          0.2,
          nodePaint,
        );
      }
    }

    // Draw Walked Path (Fading)
    if (path.isNotEmpty) {
      final now = DateTime.now();
      
      for (int i = 0; i < path.length - 1; i++) {
        final p1 = path[i];
        final p2 = path[i + 1];
        
        // Calculate opacity based on age of p1
        final age = now.difference(p1.timestamp).inMilliseconds;
        final maxAge = 5000; // 5 seconds
        double opacity = 1.0 - (age / maxAge);
        opacity = opacity.clamp(0.0, 1.0);
        
        if (opacity <= 0) continue;

        final segmentPaint = Paint()
          ..color = Colors.blue.withValues(alpha: opacity)
          ..strokeWidth = 0.1
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(
          Offset(p1.position.x, p1.position.y),
          Offset(p2.position.x, p2.position.y),
          segmentPaint,
        );
      }
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
