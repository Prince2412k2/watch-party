import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../tokens.dart';

/// A self-contained QR code encoding a party-invite URL, rendered entirely
/// client-side (no network) inside a small rounded white card so it stays
/// scannable against any theme. Mirrors the web `PartyQr`/`JoinQR`
/// (`WebShell.tsx`, `RoomControls.tsx`) — dark `#0a0a0c` modules on white.
class PartyQr extends StatelessWidget {
  const PartyQr({super.key, required this.url, this.size = 112});

  final String url;
  final double size;

  static const Color _module = Color(0xFF0A0A0C);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 20,
      height: size + 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: QrImageView(
        data: url,
        version: QrVersions.auto,
        size: size,
        padding: EdgeInsets.zero,
        backgroundColor: const Color(0xFFFFFFFF),
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: _module,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: _module,
        ),
      ),
    );
  }
}
