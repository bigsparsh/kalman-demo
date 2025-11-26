import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

class GeoUtils {
  // Default starting point (e.g., a park or open area)
  // Using a generic location: Central Park, NY for demo purposes
  // Or maybe something more neutral? Let's use 0,0 for now or a specific place.
  // Let's use a coordinate that looks like a realistic starting point.
  static const LatLng defaultOrigin = LatLng(37.7749, -122.4194); // San Francisco

  static const double earthRadius = 6371000.0; // Meters

  /// Converts a local point (meters) to a global LatLng relative to an origin.
  static LatLng localToGlobal(vector.Vector2 localPoint, LatLng origin) {
    // Simple flat earth approximation for small distances
    // dy = lat change * R
    // dx = lon change * R * cos(lat)
    
    double dLat = localPoint.y / earthRadius;
    double dLon = localPoint.x / (earthRadius * cos(origin.latitude * pi / 180.0));

    double newLat = origin.latitude + dLat * 180.0 / pi;
    double newLon = origin.longitude + dLon * 180.0 / pi;

    return LatLng(newLat, newLon);
  }

  /// Converts a global LatLng to a local point (meters) relative to an origin.
  static vector.Vector2 globalToLocal(LatLng globalPoint, LatLng origin) {
    double dLat = (globalPoint.latitude - origin.latitude) * pi / 180.0;
    double dLon = (globalPoint.longitude - origin.longitude) * pi / 180.0;

    double y = dLat * earthRadius;
    double x = dLon * earthRadius * cos(origin.latitude * pi / 180.0);

    return vector.Vector2(x, y);
  }
}
