import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as vector;

class PathManager {
  final List<vector.Vector2> _recordedPoints = [];
  
  // Defined Path Segment (Start, End)
  vector.Vector2? _pathStart;
  vector.Vector2? _pathEnd;
  
  bool get hasPath => _pathStart != null && _pathEnd != null;
  vector.Vector2? get pathStart => _pathStart;
  vector.Vector2? get pathEnd => _pathEnd;

  void addPoint(vector.Vector2 point) {
    _recordedPoints.add(point);
  }

  void clearRecording() {
    _recordedPoints.clear();
    _pathStart = null;
    _pathEnd = null;
  }

  void generatePath() {
    if (_recordedPoints.length < 2) return;

    // 1. Calculate Centroid
    double sumX = 0;
    double sumY = 0;
    for (var p in _recordedPoints) {
      sumX += p.x;
      sumY += p.y;
    }
    double centerX = sumX / _recordedPoints.length;
    double centerY = sumY / _recordedPoints.length;
    final center = vector.Vector2(centerX, centerY);

    // 2. Calculate Covariance Matrix components
    double xx = 0;
    double xy = 0;
    double yy = 0;

    for (var p in _recordedPoints) {
      double dx = p.x - centerX;
      double dy = p.y - centerY;
      xx += dx * dx;
      xy += dx * dy;
      yy += dy * dy;
    }

    // 3. PCA / Eigenvector calculation for 2D
    // We want the eigenvector corresponding to the largest eigenvalue.
    // Matrix M = [[xx, xy], [xy, yy]]
    // This is equivalent to finding the angle of the regression line.
    // theta = 0.5 * atan2(2*xy, xx - yy)
    
    double theta = 0.5 * atan2(2 * xy, xx - yy);
    
    // Direction vector of the line
    vector.Vector2 dir = vector.Vector2(cos(theta), sin(theta));

    // 4. Project all points onto this line to find extents
    double minProj = double.infinity;
    double maxProj = double.negativeInfinity;

    for (var p in _recordedPoints) {
      // Vector from center to point
      vector.Vector2 v = p - center;
      // Dot product with direction
      double proj = v.dot(dir);
      if (proj < minProj) minProj = proj;
      if (proj > maxProj) maxProj = proj;
    }

    // 5. Define Start and End points
    _pathStart = center + dir * minProj;
    _pathEnd = center + dir * maxProj;
  }

  vector.Vector2 snapPoint(vector.Vector2 point, {double threshold = 2.0}) {
    if (!hasPath) return point;

    final start = _pathStart!;
    final end = _pathEnd!;
    
    // Vector from Start to End
    vector.Vector2 lineVec = end - start;
    double lineLenSq = lineVec.length2;
    
    if (lineLenSq == 0) return start;

    // Project point onto line segment
    // t = ((point - start) . lineVec) / lineLenSq
    double t = (point - start).dot(lineVec) / lineLenSq;

    // Clamp t to [0, 1] to stay within segment
    // If we want to allow snapping beyond the segment (infinite line), remove clamping.
    // But usually "corridor" implies a finite segment. Let's clamp.
    t = t.clamp(0.0, 1.0);

    // Closest point on line
    vector.Vector2 closest = start + lineVec * t;

    // Check distance
    double dist = (point - closest).length;
    
    if (dist <= threshold) {
      return closest;
    } else {
      return point; // Too far, don't snap
    }
  }
}
