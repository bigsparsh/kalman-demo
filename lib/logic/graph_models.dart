import 'package:vector_math/vector_math_64.dart' as vector;

class Node {
  final String id;
  final vector.Vector2 position;
  final List<String> connectedEdgeIds = [];

  Node({required this.id, required this.position});
}

class Edge {
  final String id;
  final String startNodeId;
  final String endNodeId;
  
  // For now, edges are straight lines, so geometry is implicit from nodes.
  // We can add intermediate points here if needed later.

  Edge({
    required this.id,
    required this.startNodeId,
    required this.endNodeId,
  });
}

class Graph {
  final Map<String, Node> nodes = {};
  final Map<String, Edge> edges = {};

  void addNode(Node node) {
    nodes[node.id] = node;
  }

  void addEdge(Edge edge) {
    edges[edge.id] = edge;
    nodes[edge.startNodeId]?.connectedEdgeIds.add(edge.id);
    nodes[edge.endNodeId]?.connectedEdgeIds.add(edge.id);
  }

  void clear() {
    nodes.clear();
    edges.clear();
  }
}
