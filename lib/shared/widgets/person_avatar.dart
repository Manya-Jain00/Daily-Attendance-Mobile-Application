import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/photos/photo_picker.dart';
import 'load_state.dart';

/// First letter of [name], for an avatar without a photo.
String initialOf(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}

/// A person's photo in a circle, or the first letter of their name until
/// one is added. Tapping a photo shows it large (to tell faces apart).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    required this.photo,
    this.radius = 20,
    this.ringColor,
    this.dimmed = false,
    this.enlargeOnTap = true,
  });

  final String name;
  final Uint8List? photo;
  final double radius;

  /// A coloured ring round the photo (e.g. the status it's marked with).
  final Color? ringColor;

  /// Greyed out, e.g. someone who has left.
  final bool dimmed;
  final bool enlargeOnTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photo = this.photo;
    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: dimmed
          ? scheme.surfaceContainerHighest
          : scheme.primaryContainer,
      foregroundColor: dimmed
          ? scheme.onSurfaceVariant
          : scheme.onPrimaryContainer,
      backgroundImage: photo == null ? null : MemoryImage(photo),
      child: photo == null
          ? Text(
              initialOf(name),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.8,
              ),
            )
          : null,
    );
    if (photo != null && dimmed) {
      avatar = Opacity(opacity: 0.5, child: avatar);
    }
    final ring = ringColor;
    if (ring != null) {
      avatar = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
        child: avatar,
      );
    }
    if (photo == null || !enlargeOnTap) return avatar;
    return Semantics(
      button: true,
      label: 'Photo of $name',
      child: GestureDetector(
        onTap: () => showPhoto(context, name, photo),
        child: avatar,
      ),
    );
  }
}

/// [photo] large, with [name] under it.
Future<void> showPhoto(BuildContext context, String name, Uint8List photo) =>
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Image.memory(photo, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(name, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
      ),
    );

/// A large photo with buttons to take one, choose one or remove it. Without
/// [onChanged] it's view only.
class PhotoField extends StatelessWidget {
  const PhotoField({
    super.key,
    required this.name,
    required this.photo,
    this.onChanged,
    this.hint,
  });

  final String name;
  final Uint8List? photo;
  final ValueChanged<Uint8List?>? onChanged;

  /// Shown under the buttons, e.g. why the photo helps.
  final String? hint;

  Future<void> _pick(BuildContext context, PhotoFrom from) async {
    final Uint8List? picked;
    try {
      picked = await PhotoPicker.instance.pick(from);
    } on Exception {
      if (context.mounted) {
        showMessage(
          context,
          from == PhotoFrom.camera
              ? 'The camera could not be opened. Allow it in the phone '
                    'settings, or choose from the gallery.'
              : 'The photo could not be opened.',
        );
      }
      return;
    }
    if (picked == null || !context.mounted) return;
    if (picked.length > PhotoPicker.maxBytes) {
      showMessage(context, 'That photo is too large. Try another one.');
      return;
    }
    onChanged!(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onChanged = this.onChanged;
    return Column(
      children: [
        PersonAvatar(name: name.isEmpty ? '?' : name, photo: photo, radius: 56),
        if (onChanged != null) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _pick(context, PhotoFrom.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take photo'),
              ),
              TextButton.icon(
                onPressed: () => _pick(context, PhotoFrom.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
              if (photo != null)
                TextButton.icon(
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
            ],
          ),
          if (hint != null)
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ],
    );
  }
}
