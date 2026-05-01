import 'package:flutter/material.dart';

import '../services/image_upload_service.dart';
import '../theme/app_theme.dart';

class PhotoUploadField extends StatelessWidget {
  final String title;
  final String subtitle;
  final PickedUploadImage? image;
  final VoidCallback onPick;
  final VoidCallback? onRemove;
  final IconData icon;
  final Color color;

  const PhotoUploadField({
    super.key,
    required this.title,
    required this.subtitle,
    required this.image,
    required this.onPick,
    this.onRemove,
    this.icon = Icons.add_a_photo_outlined,
    this.color = AppPalette.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 58,
              height: 58,
              color: Colors.white,
              child: image == null
                  ? Icon(icon, color: color)
                  : Image.memory(image!.bytes, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppPalette.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppPalette.muted,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: image == null ? 'Choose photo' : 'Change photo',
            onPressed: onPick,
            icon: Icon(
              image == null ? Icons.upload_outlined : Icons.swap_horiz,
            ),
            color: color,
          ),
          if (image != null)
            IconButton(
              tooltip: 'Remove photo',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              color: AppPalette.danger,
            ),
        ],
      ),
    );
  }
}
