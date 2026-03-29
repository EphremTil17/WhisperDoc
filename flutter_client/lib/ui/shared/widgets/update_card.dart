import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_client/logic/mappers/update_mapper.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// A modular card for update notifications.
/// Follows the 'Atomic' shared widget pattern.
class UpdateCard extends StatelessWidget {
  const UpdateCard({
    super.key,
    required this.status,
    required this.descriptor,
    this.downloadUrl,
  });

  static const double _cardBackgroundAlpha = 0.05;
  static const double _cardBorderAlpha = 0.15;
  static const double _iconBackgroundAlpha = 0.1;
  static const double _primaryTextAlpha = 0.9;
  static const double _secondaryTextAlpha = 0.5;
  static const double _chevronAlpha = 0.2;
  static const double _downloadBackgroundAlpha = 0.2;
  static const double _iconSize = 20;
  static const double _titleFontSize = 14;
  static const double _subtitleFontSize = 12;
  static const double _downloadFontSize = 12;
  static const double _cardBorderWidth = 1;

  final UpdateStatus status;
  final UpdateUIDescriptor descriptor;
  final String? downloadUrl;

  void _handleDownload() {
    // If up to date, just go to the releases page.
    // If update available, use the direct link if we have it.
    final url = downloadUrl;
    final String targetUrl = (status != UpdateStatus.upToDate && url != null)
        ? url
        : AppConstants.updateUrl;

    unawaited(
      launchUrl(Uri.parse(targetUrl), mode: LaunchMode.externalApplication),
    );
  }

  @override
  Widget build(BuildContext context) {
    IconData statusIcon;
    String subtitle;
    switch (status) {
      case UpdateStatus.required:
        statusIcon = Icons.error_outline;
        subtitle = 'Update required to connect';
      case UpdateStatus.advisory:
        statusIcon = Icons.update;
        subtitle = 'A new version is available';
      case UpdateStatus.upToDate:
        statusIcon = Icons.check_circle_outline;
        subtitle = 'Tap to view releases';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleDownload(),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: descriptor.glowColor.withValues(alpha: _cardBackgroundAlpha),
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            border: Border.all(
              color: descriptor.glowColor.withValues(alpha: _cardBorderAlpha),
              width: _cardBorderWidth,
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
                      color: descriptor.glowColor.withValues(
                        alpha: _iconBackgroundAlpha,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      statusIcon,
                      color: descriptor.glowColor,
                      size: _iconSize,
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
                            color: Colors.white.withValues(
                              alpha: _primaryTextAlpha,
                            ),
                            fontWeight: FontWeight.bold,
                            fontSize: _titleFontSize,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(
                              alpha: _secondaryTextAlpha,
                            ),
                            fontSize: _subtitleFontSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withValues(alpha: _chevronAlpha),
                    size: _iconSize,
                  ),
                ],
              ),
              if (status != UpdateStatus.upToDate) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: descriptor.glowColor.withValues(
                      alpha: _downloadBackgroundAlpha,
                    ),
                    borderRadius: const BorderRadius.all(Radius.circular(8)),
                  ),
                  child: Center(
                    child: Text(
                      'Download Now',
                      style: TextStyle(
                        color: descriptor.glowColor,
                        fontWeight: FontWeight.bold,
                        fontSize: _downloadFontSize,
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
}
