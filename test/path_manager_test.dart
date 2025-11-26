import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_filter/logic/path_manager.dart';
import 'package:kalman_filter/logic/graph_models.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

void main() {
  group('PathManager Tests', () {
    late PathManager pathManager;

    setUp(() {
      pathManager = PathManager();
    });

    test('prepareForNewRecording splits edge when close to middle but far from nodes', () {
      // 1. Setup a graph with one edge from (0,0) to (10,0)
      final startNode = Node(id: 'start', position: vector.Vector2(0, 0));
      final endNode = Node(id: 'end', position: vector.Vector2(10, 0));
      final edge = Edge(id: 'edge1', startNodeId: 'start', endNodeId: 'end');

      pathManager.graph.addNode(startNode);
      pathManager.graph.addNode(endNode);
      pathManager.graph.addEdge(edge);

      // 2. Prepare for recording at (1.5, 0)
      // This is 1.5m away from startNode. 
      // If threshold is 2.0m, it will snap to startNode (BUG).
      // If threshold is 0.5m, it should split the edge (FIX).
      pathManager.prepareForNewRecording(vector.Vector2(1.5, 0));

      // 3. Verify graph state
      // We expect the original edge to be gone, and 2 new edges to exist.
      // We expect 3 nodes total (start, end, and split node).
      
      expect(pathManager.graph.nodes.length, 3, reason: "Should have 3 nodes (start, end, split)");
      expect(pathManager.graph.edges.length, 2, reason: "Should have 2 edges after split");
      
      // Verify the split node position
      // The new node should be at (1.5, 0)
      bool foundSplitNode = false;
      for (var node in pathManager.graph.nodes.values) {
        if (node.id != 'start' && node.id != 'end') {
          expect(node.position.x, closeTo(1.5, 0.001));
          expect(node.position.y, closeTo(0, 0.001));
          foundSplitNode = true;
        }
      }
      expect(foundSplitNode, isTrue, reason: "Did not find the split node at (1.5, 0)");
    });
  });
}
