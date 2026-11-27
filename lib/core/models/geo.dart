import 'dart:math' as math;

/// A point on the map, in degrees.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  static bool isValid(double lat, double lng) =>
      lat.isFinite && lng.isFinite && lat.abs() <= 90 && lng.abs() <= 180;

  /// Null unless [raw] is a map with a valid `lat` and `lng`.
  static GeoPoint? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final lat = raw['lat'];
    final lng = raw['lng'];
    if (lat is! num || lng is! num) return null;
    if (!isValid(lat.toDouble(), lng.toDouble())) return null;
    return GeoPoint(lat.toDouble(), lng.toDouble());
  }

  Map<String, Object> toMap() => {'lat': lat, 'lng': lng};

  /// Straight-line distance in metres (haversine).
  double distanceTo(GeoPoint other) {
    const earthRadius = 6371000.0;
    double rad(double deg) => deg * math.pi / 180;
    final dLat = rad(other.lat - lat);
    final dLng = rad(other.lng - lng);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat)) *
            math.cos(rad(other.lat)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Opens this point in Google Maps (app or browser). Needs no API key.
  Uri get mapsUri => Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': '$lat,$lng',
  });

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

/// Where the phone was when an entry was saved.
class EntryLocation {
  const EntryLocation({
    required this.point,
    required this.accuracy,
    this.mocked = false,
  });

  final GeoPoint point;

  /// How far off the phone says the point may be, in metres.
  final double accuracy;

  /// Android reported the position as coming from a location-faking app.
  final bool mocked;

  static EntryLocation? fromMap(Object? raw) {
    final point = GeoPoint.fromMap(raw);
    if (point == null || raw is! Map) return null;
    final accuracy = raw['accuracy'];
    return EntryLocation(
      point: point,
      accuracy: accuracy is num ? accuracy.toDouble() : 0,
      mocked: raw['mocked'] == true,
    );
  }

  Map<String, Object> toMap() => {
    ...point.toMap(),
    'accuracy': accuracy,
    if (mocked) 'mocked': true,
  };

  @override
  bool operator ==(Object other) =>
      other is EntryLocation &&
      other.point == point &&
      other.accuracy == accuracy &&
      other.mocked == mocked;

  @override
  int get hashCode => Object.hash(point, accuracy, mocked);
}

/// 35 to "35 m", 2300 to "2.3 km".
String displayDistance(double metres) {
  if (metres < 1000) return '${metres.round()} m';
  final km = metres / 1000;
  return '${km < 10 ? km.toStringAsFixed(1) : km.round()} km';
}
