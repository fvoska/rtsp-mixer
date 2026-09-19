import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/spacing.dart';
import '../models/pairing_payload.dart';

/// The pairing QR the host shows. Always black-on-white inside a padded
/// card regardless of theme: phone cameras decode a high-contrast code far
/// more reliably than a teal-on-petrol one, and the nursery is dark.
class PairingQr extends StatelessWidget {
  const PairingQr({super.key, required this.payload, this.size = 200});

  final PairingPayload payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pairing QR code for ${payload.hostName}',
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Radii.inner),
        ),
        child: QrImageView(
          data: payload.toString(),
          version: QrVersions.auto,
          size: size,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
          errorStateBuilder: (_, _) => SizedBox(
            width: size,
            height: size,
            child: const Center(
              child: Text(
                'QR unavailable — type the code instead',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
