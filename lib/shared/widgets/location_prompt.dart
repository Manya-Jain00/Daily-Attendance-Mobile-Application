import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/location/location_service.dart';
import '../../core/models/geo.dart';
import 'load_state.dart';

/// Reads the phone's position, walking the person through whatever is in the
/// way (permission, GPS switched off, no fix). Null if they gave up.
///
/// [why] is shown before the phone's own "Allow location?" prompt, e.g.
/// "The director sees where attendance was saved."
Future<EntryLocation?> askLocation(
  BuildContext context,
  LocationService service, {
  required String why,
}) async {
  for (var tries = 0; tries < 5; tries++) {
    final result = await service.current();
    if (!context.mounted) return null;
    switch (result) {
      case Located(:final location):
        return location;
      case LocationNotAllowed():
        final go = await _ask(
          context,
          icon: Icons.location_on_outlined,
          title: 'Allow location',
          message:
              '$why\n\nYour location is read only at the moment you save. '
              'It is never tracked at other times.',
          action: 'Continue',
        );
        if (!go || !context.mounted) return null;
        if (!await service.requestPermission()) {
          if (context.mounted) {
            showMessage(context, 'Location is needed to save.');
          }
          return null;
        }
      case LocationOff():
        final go = await _ask(
          context,
          icon: Icons.location_off_outlined,
          title: 'Turn on location',
          message:
              'Location is switched off on this phone. Turn it on, then '
              'come back and save again.',
          action: 'Open settings',
        );
        if (go) await service.openLocationSettings();
        return null;
      case LocationBlocked():
        final go = await _ask(
          context,
          icon: Icons.location_disabled_outlined,
          title: 'Location is blocked',
          message:
              '$why\n\nLocation was refused for this app. Open the app '
              'settings, choose Permissions → Location → "Allow only while '
              'using the app", then come back and save again.',
          action: 'Open app settings',
        );
        if (go) await service.openAppSettings();
        return null;
      case LocationTimedOut():
        final go = await _ask(
          context,
          icon: Icons.location_searching,
          title: 'Could not find your location',
          message:
              'Move near a window or outside for a moment, then try '
              'again.',
          action: 'Try again',
        );
        if (!go) return null;
    }
    if (!context.mounted) return null;
  }
  return null;
}

/// True if [action] was tapped, false for Cancel.
Future<bool> _ask(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String action,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(icon),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return answer == true;
}

/// Opens [point] in Google Maps.
Future<void> openMap(BuildContext context, GeoPoint point) async {
  final opened = await launchUrl(
    point.mapsUri,
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    showMessage(context, 'Could not open the map.');
  }
}
