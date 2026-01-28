import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_client/logic/mappers/update_mapper.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// A modular card for update notifications.
/// Follows the 'Atomic' shared widget pattern.
class UpdateCard extends StatelessWidget {
  final UpdateStatus status;
  final UpdateUIDescriptor descriptor;
  final String? downloadUrl;

  const UpdateCard({
    super.key,
    required this.status,
    required this.descriptor,
    this.downloadUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleDownload(),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: descriptor.glowColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: descriptor.glowColor.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: descriptor.glowColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      status == UpdateStatus.required
                          ? Icons.error_outline
                          : status == UpdateStatus.advisory
                          ? Icons.update
                          : Icons.check_circle_outline,
                      color: descriptor.glowColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          descriptor.label,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          status == UpdateStatus.required
                              ? 'Update required to connect'
                              : status == UpdateStatus.advisory
                              ? 'A new version is available'
                              : 'Tap to view releases',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.2),
                    size: 20,
                  ),
                ],
              ),
              if (status != UpdateStatus.upToDate) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: descriptor.glowColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'Download Now',
                      style: TextStyle(
                        color: descriptor.glowColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleDownload() {
    // If up to date, just go to the releases page.
    // If update available, use the direct link if we have it.
    final String targetUrl =
        (status != UpdateStatus.upToDate && downloadUrl != null)
        ? downloadUrl!
        : AppConstants.updateUrl;

    unawaited(
      launchUrl(Uri.parse(targetUrl), mode: LaunchMode.externalApplication),
    );
  }
}
