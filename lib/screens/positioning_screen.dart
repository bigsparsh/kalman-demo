
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import '../logic/pdr_engine.dart';
import '../services/sensor_service.dart';

import '../logic/geo_utils.dart';
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
  
  // Map State
  final MapController _mapController = MapController();
  LatLng _mapCenter = GeoUtils.defaultOrigin;
  final double _currentZoom = 18.0;

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
        
        // Update map center to follow user
        // _mapCenter = GeoUtils.localToGlobal(_currentPosition, GeoUtils.defaultOrigin);
        // _mapController.move(_mapCenter, _currentZoom);
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
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _mapCenter,
                initialZoom: _currentZoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.kalman_filter',
                ),
                // Draw Graph (if exists)
                if (_pdrEngine.hasPath)
                  PolylineLayer(
                    polylines: _buildGraphPolylines(),
                  ),
                // Draw Walked Path (Fading)
                PolylineLayer(
                  polylines: _buildTrailPolylines(),
                ),
                // Draw Marker (at currentPosition)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: GeoUtils.localToGlobal(_currentPosition, GeoUtils.defaultOrigin),
                      width: 20,
                      height: 20,
                      child: Transform.rotate(
                        angle: _currentHeading,
                        child: const Icon(
                          Icons.navigation,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
                FloatingActionButton(
                  onPressed: () {
                    _mapCenter = GeoUtils.localToGlobal(_currentPosition, GeoUtils.defaultOrigin);
                    _mapController.move(_mapCenter, _currentZoom);
                  },
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Polyline> _buildGraphPolylines() {
    List<Polyline> polylines = [];
    final graph = _pdrEngine.graph;
    
    for (var edge in graph.edges.values) {
      final startNode = graph.nodes[edge.startNodeId];
      final endNode = graph.nodes[edge.endNodeId];

      if (startNode != null && endNode != null) {
        polylines.add(
          Polyline(
            points: [
              GeoUtils.localToGlobal(startNode.position, GeoUtils.defaultOrigin),
              GeoUtils.localToGlobal(endNode.position, GeoUtils.defaultOrigin),
            ],
            color: Colors.green.withValues(alpha: 0.5),
            strokeWidth: 4.0,
          ),
        );
      }
    }
    return polylines;
  }

  List<Polyline> _buildTrailPolylines() {
    List<Polyline> polylines = [];
    final now = DateTime.now();
    final maxAge = 5000; // 5 seconds

    for (int i = 0; i < _path.length - 1; i++) {
      final p1 = _path[i];
      final p2 = _path[i + 1];

      final age = now.difference(p1.timestamp).inMilliseconds;
      double opacity = 1.0 - (age / maxAge);
      opacity = opacity.clamp(0.0, 1.0);

      if (opacity <= 0) continue;

      polylines.add(
        Polyline(
          points: [
            GeoUtils.localToGlobal(p1.position, GeoUtils.defaultOrigin),
            GeoUtils.localToGlobal(p2.position, GeoUtils.defaultOrigin),
          ],
          color: Colors.blue.withValues(alpha: opacity),
          strokeWidth: 3.0,
        ),
      );
    }
    return polylines;
  }
}

