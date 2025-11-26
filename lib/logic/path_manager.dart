import 'dart:math';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'package:uuid/uuid.dart';
import 'graph_models.dart';

class PathManager {
  final List<vector.Vector2> _recordedPoints = [];
  final Graph _graph = Graph();
  final Uuid _uuid = Uuid();

  Node? _lastNode; // The end node of the last finalized segment

  bool get hasPath => _graph.edges.isNotEmpty;
  Graph get graph => _graph;

  void addPoint(vector.Vector2 point) {
    _recordedPoints.add(point);
  }

  void resetRecordingSession() {
    _recordedPoints.clear();
    // Do NOT clear the graph here. We want to persist it.
    // _graph.clear(); 
    _lastNode = null;
  }

  void clearGraph() {
    _graph.clear();
    _recordedPoints.clear();
    _lastNode = null;
  }

  bool get hasPendingPoints => _recordedPoints.isNotEmpty;

  /// Prepares for a new recording session.
  /// Checks if the current position is close to an existing graph element to branch off.
  void prepareForNewRecording(vector.Vector2 currentPos) {
    resetRecordingSession();

    if (!hasPath) return;

    // 1. Check if we are close to an existing Node
    Node? closestNode = _findClosestNode(currentPos, threshold: 0.5);
    if (closestNode != null) {
      _lastNode = closestNode;
      return;
    }

    // 2. Check if we are close to an Edge (to split it)
    Node? splitNode = splitEdgeAtPoint(currentPos, threshold: 2.0);
    if (splitNode != null) {
      _lastNode = splitNode;
      return;
    }

    // If not close to anything, we start a fresh disconnected segment (or just a new tree in the forest)
    _lastNode = null;
  }

  /// Finalizes the currently recorded points into a new Edge (and Nodes).
  /// Connects to the previous segment if it exists.
  void generatePath() => finalizeCurrentSegment();

  void finalizeCurrentSegment() {
    if (_recordedPoints.length < 2) {
      // Not enough points to form a line.
      // If we have points but not enough for a line, we might just want to keep them 
      // for the next segment or discard? 
      // For now, let's just keep them if we are continuing, but this function implies "finishing" a segment.
      // If we stop with 1 point, it's noise.
      // _recordedPoints.clear(); // Don't clear, maybe we just haven't moved enough yet.
      return;
    }

    // Check total length of the segment
    double totalLength = 0;
    for (int i = 0; i < _recordedPoints.length - 1; i++) {
      totalLength += (_recordedPoints[i] - _recordedPoints[i+1]).length;
    }

    if (totalLength < 1.0) {
      // Segment too short to be meaningful (less than 1 meter)
      return;
    }

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

    // 2. Calculate PCA / Regression Line
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

    double theta = 0.5 * atan2(2 * xy, xx - yy);
    vector.Vector2 dir = vector.Vector2(cos(theta), sin(theta));

    // 3. Project points to find extents
    double minProj = double.infinity;
    double maxProj = double.negativeInfinity;

    for (var p in _recordedPoints) {
      vector.Vector2 v = p - center;
      double proj = v.dot(dir);
      if (proj < minProj) minProj = proj;
      if (proj > maxProj) maxProj = proj;
    }

    vector.Vector2 startPos = center + dir * minProj;
    vector.Vector2 endPos = center + dir * maxProj;

    // 4. Connectivity Logic
    // We need to determine which end (startPos or endPos) should connect to _lastNode.
    // The user was walking away from _lastNode.
    
    Node startNode;
    Node endNode;

    if (_lastNode != null) {
      // Find which point (startPos or endPos) is closer to _lastNode
      double distStart = (startPos - _lastNode!.position).length;
      double distEnd = (endPos - _lastNode!.position).length;

      // We force the start of the new edge to be _lastNode
      startNode = _lastNode!;

      // The other end is the new end node
      if (distStart < distEnd) {
        // startPos is closer, so the direction was start -> end
        // We use endPos as the new end, but we might want to re-project it 
        // relative to _lastNode to keep the line straight?
        // For simplicity, let's just use endPos as the geometry end.
        endNode = Node(id: _uuid.v4(), position: endPos);
      } else {
        // endPos is closer, so the direction was end -> start
        endNode = Node(id: _uuid.v4(), position: startPos);
      }
    } else {
      // First segment
      startNode = Node(id: _uuid.v4(), position: startPos);
      endNode = Node(id: _uuid.v4(), position: endPos);
      _graph.addNode(startNode);
    }

    _graph.addNode(endNode);

    final edge = Edge(
      id: _uuid.v4(),
      startNodeId: startNode.id,
      endNodeId: endNode.id,
    );
    _graph.addEdge(edge);

    // Update state
    _lastNode = endNode;
    _recordedPoints.clear();
    
    // If we want to be continuous, the next segment starts adding points.
    // Ideally, the first point of the next segment is the current position (near endNode).
  }

  /// Snaps the point to the closest edge in the graph.
  vector.Vector2 snapPoint(vector.Vector2 point, {double threshold = 2.0, bool strict = false}) {
    if (!hasPath) return point;

    double minDistance = double.infinity;
    vector.Vector2 closestPoint = point;

    // Iterate over all edges to find the global closest point
    for (var edge in _graph.edges.values) {
      final startNode = _graph.nodes[edge.startNodeId];
      final endNode = _graph.nodes[edge.endNodeId];

      if (startNode == null || endNode == null) continue;

      final start = startNode.position;
      final end = endNode.position;

      vector.Vector2 lineVec = end - start;
      double lineLenSq = lineVec.length2;

      if (lineLenSq == 0) {
        double dist = (point - start).length;
        if (dist < minDistance) {
          minDistance = dist;
          closestPoint = start;
        }
        continue;
      }

      double t = (point - start).dot(lineVec) / lineLenSq;
      t = t.clamp(0.0, 1.0);
      vector.Vector2 proj = start + lineVec * t;

      double dist = (point - proj).length;
      if (dist < minDistance) {
        minDistance = dist;
        closestPoint = proj;
      }
    }

    if (strict) {
      return closestPoint;
    }

    if (minDistance <= threshold) {
      return closestPoint;
    } else {
      return point;
    }
  }

  /// Splits the closest edge at the given point if it is within threshold.
  /// Returns the new Node created at the split point, or null if no split happened.
  Node? splitEdgeAtPoint(vector.Vector2 point, {double threshold = 2.0}) {
    if (!hasPath) return null;

    double minDistance = double.infinity;
    Edge? closestEdge;
    vector.Vector2? splitPos;

    // Find closest edge
    for (var edge in _graph.edges.values) {
      final startNode = _graph.nodes[edge.startNodeId];
      final endNode = _graph.nodes[edge.endNodeId];

      if (startNode == null || endNode == null) continue;

      final start = startNode.position;
      final end = endNode.position;

      vector.Vector2 lineVec = end - start;
      double lineLenSq = lineVec.length2;

      if (lineLenSq == 0) continue;

      double t = (point - start).dot(lineVec) / lineLenSq;
      t = t.clamp(0.0, 1.0);
      vector.Vector2 proj = start + lineVec * t;

      double dist = (point - proj).length;
      if (dist < minDistance) {
        minDistance = dist;
        closestEdge = edge;
        splitPos = proj;
      }
    }

    if (closestEdge != null && minDistance <= threshold && splitPos != null) {
      // We found an edge to split.
      // 1. Create new Node at splitPos
      final newNode = Node(id: _uuid.v4(), position: splitPos);
      _graph.addNode(newNode);

      // 2. Remove the old edge
      _graph.edges.remove(closestEdge.id);
      // Also remove from connected nodes lists (optional but good practice)
      _graph.nodes[closestEdge.startNodeId]?.connectedEdgeIds.remove(closestEdge.id);
      _graph.nodes[closestEdge.endNodeId]?.connectedEdgeIds.remove(closestEdge.id);

      // 3. Create two new edges
      final edge1 = Edge(
        id: _uuid.v4(),
        startNodeId: closestEdge.startNodeId,
        endNodeId: newNode.id,
      );
      final edge2 = Edge(
        id: _uuid.v4(),
        startNodeId: newNode.id,
        endNodeId: closestEdge.endNodeId,
      );

      _graph.addEdge(edge1);
      _graph.addEdge(edge2);
      
      // Update _lastNode to be this new node so new recording starts from here
      _lastNode = newNode;

      return newNode;
    }

    return null;
  }


  /// Finds a path between two points on the graph.
  /// Returns a list of points including intermediate nodes.
  /// If no path is found or points are not on graph, returns [end].
  List<vector.Vector2> findPath(vector.Vector2 start, vector.Vector2 end) {
    if (!hasPath) return [end];

    // 1. Find closest nodes to start and end
    Node? startNode = _findClosestNode(start);
    Node? endNode = _findClosestNode(end);

    if (startNode == null || endNode == null || startNode == endNode) {
      return [end];
    }

    // 2. Perform Dijkstra's algorithm
    Map<String, String?> cameFrom = {};
    Map<String, double> costSoFar = {};
    
    // Simple priority queue using a list
    List<Node> frontier = [];
    frontier.add(startNode);
    cameFrom[startNode.id] = null;
    costSoFar[startNode.id] = 0;

    while (frontier.isNotEmpty) {
      // Get node with lowest cost
      frontier.sort((a, b) => (costSoFar[a.id] ?? double.infinity).compareTo(costSoFar[b.id] ?? double.infinity));
      final current = frontier.removeAt(0);

      if (current == endNode) break;

      // Get neighbors
      for (var edgeId in current.connectedEdgeIds) {
        final edge = _graph.edges[edgeId];
        if (edge == null) continue;

        final nextId = (edge.startNodeId == current.id) ? edge.endNodeId : edge.startNodeId;
        final next = _graph.nodes[nextId];
        if (next == null) continue;

        double newCost = (costSoFar[current.id] ?? 0) + (current.position - next.position).length;

        if (!costSoFar.containsKey(nextId) || newCost < (costSoFar[nextId] ?? double.infinity)) {
          costSoFar[nextId] = newCost;
          cameFrom[nextId] = current.id;
          frontier.add(next);
        }
      }
    }

    // 3. Reconstruct path
    if (!cameFrom.containsKey(endNode.id)) {
      return [end]; // No path found
    }

    List<vector.Vector2> path = [];
    String? currentId = endNode.id;
    while (currentId != null) {
      final node = _graph.nodes[currentId];
      if (node != null) {
        path.add(node.position);
      }
      currentId = cameFrom[currentId];
    }
    
    // Add start point (optional, but good for continuity)
    // path.add(start); 
    
    // The path is reversed (end -> start), so reverse it back
    return path.reversed.toList()..add(end);
  }

  Node? _findClosestNode(vector.Vector2 point, {double threshold = 5.0}) {
    double minDistance = double.infinity;
    Node? closestNode;

    for (var node in _graph.nodes.values) {
      double dist = (point - node.position).length;
      if (dist < minDistance) {
        minDistance = dist;
        closestNode = node;
      }
    }
    
    // If the closest node is too far, maybe we shouldn't snap to it?
    // For now, let's just return it if it's within a reasonable range.
    if (minDistance < threshold) {
      return closestNode;
    }
    return null;
  }
}
