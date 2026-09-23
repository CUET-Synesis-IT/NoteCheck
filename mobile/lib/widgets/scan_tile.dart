import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Authenticated thumbnail of a stored scan.
class ScanThumbnail extends StatelessWidget {
  const ScanThumbnail({super.key, required this.api, required this.scan, this.width = 84, this.height = 56, this.radius = 12});

  final ApiClient api;
  final Scan scan;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.image_not_supported_outlined, color: scheme.onSurfaceVariant, size: 20),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: scan.hasImage
          ? Image.network(
              api.scanImageUrl(scan.id),
              headers: api.authHeaders,
              width: width,
              height: height,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => placeholder,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      width: width,
                      height: height,
                      color: scheme.surfaceContainerHighest,
                      child: const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                    ),
            )
          : placeholder,
    );
  }
}

class ScanTile extends StatelessWidget {
  const ScanTile({super.key, required this.api, required this.scan, this.onTap, this.showUser = false});

  final ApiClient api;
  final Scan scan;
  final VoidCallback? onTap;
  final bool showUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final color = scheme.verdict(scan.isGenuine);
    return NcCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Hero(tag: 'scan-${scan.id}', child: ScanThumbnail(api: api, scan: scan)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    VerdictBadge(genuine: scan.isGenuine, compact: true),
                    const Spacer(),
                    Text('#${scan.id}', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(Fmt.percent(scan.confidence), style: t.titleMedium?.copyWith(color: color)),
                    const SizedBox(width: 6),
                    Text('confidence', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    if (scan.wasCropped) Icon(Icons.crop_rounded, size: 15, color: scheme.onSurfaceVariant),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  showUser && scan.userEmail != null
                      ? '${scan.userEmail} · ${Fmt.relative(scan.createdAt)}'
                      : Fmt.relative(scan.createdAt),
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
