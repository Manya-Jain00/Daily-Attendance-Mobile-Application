import 'package:geolocator/geolocator.dart';

import '../models/geo.dart';

/// Why the phone's position couldn't be read, or the position itself.
sealed class LocationResult {
  const LocationResult();
}

class Located extends LocationResult {
  const Located(this.location);

  final EntryLocation location;
}

/// Location (GPS) is switched off on the phone.
class LocationOff extends LocationResult {
  const LocationOff();
}

/// The app hasn't been allowed to use location yet; it can still ask.
class LocationNotAllowed extends LocationResult {
  const LocationNotAllowed();
}

/// Location was refused with "Don't ask again": only the phone's settings
/// can allow it now.
class LocationBlocked extends LocationResult {
  const LocationBlocked();
}

/// No position came in time (e.g. deep inside a building).
class LocationTimedOut extends LocationResult {
  const LocationTimedOut();
}

/// The phone's position, read once when a supervisor saves attendance. It's
/// never tracked in the background.
abstract class LocationService {
  /// Where the phone is now. Doesn't ask for permission.
  Future<LocationResult> current();

  /// Shows the phone's "Allow location?" prompt. True if allowed.
  Future<bool> requestPermission();

  /// Opens the phone's location (GPS) settings.
  Future<void> openLocationSettings();

  /// Opens this app's settings, to allow location after "Don't ask again".
  Future<void> openAppSettings();
}

/// [LocationService] using the phone's GPS.
class DeviceLocationService implements LocationService {
  const DeviceLocationService();

  @override
  Future<LocationResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationOff();
    }
    switch (await Geolocator.checkPermission()) {
      case LocationPermission.denied:
        return const LocationNotAllowed();
      case LocationPermission.deniedForever:
        return const LocationBlocked();
      case LocationPermission.whileInUse:
      case LocationPermission.always:
      case LocationPermission.unableToDetermine:
        break;
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      return Located(
        EntryLocation(
          point: GeoPoint(position.latitude, position.longitude),
          accuracy: position.accuracy,
          mocked: position.isMocked,
        ),
      );
    } on LocationServiceDisabledException {
      return const LocationOff();
    } on PermissionDeniedException {
      return const LocationNotAllowed();
    } on Exception {
      // Timed out, or the phone gave no fix.
      return const LocationTimedOut();
    }
  }

  @override
  Future<bool> requestPermission() async {
    final permission = await Geolocator.requestPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();
}
