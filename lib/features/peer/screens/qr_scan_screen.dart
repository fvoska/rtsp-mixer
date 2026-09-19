import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/spacing.dart';
import '../models/pairing_payload.dart';

/// Full-screen QR scanner. Pops with a [PairingPayload] on the first valid
/// Roomtone code; foreign codes are ignored silently. Camera failures
/// (no permission, no camera on a tablet/desktop) render an inline message
/// with a way back to typing the code — never a crash.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    try {
      for (final barcode in capture.barcodes) {
        final payload = PairingPayload.tryParse(barcode.rawValue);
        if (payload != null) {
          _done = true;
          appLog('PAIR', 'Scanned pairing QR for "${payload.hostName}"');
          if (mounted) context.pop(payload);
          return;
        }
      }
    } catch (e) {
      appLog('PAIR', 'QR detect handler failed (ignored): $e');
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() => _torch = !_torch);
    } catch (e) {
      appLog('PAIR', 'torch toggle failed (ignored): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan pairing code'),
        actions: [
          IconButton(
            icon: Icon(_torch ? Icons.flashlight_off : Icons.flashlight_on),
            tooltip: _torch ? 'Torch off' : 'Torch on',
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScanError(
              message: switch (error.errorCode) {
                MobileScannerErrorCode.permissionDenied =>
                  'Camera permission was denied. Allow it in system settings, '
                      'or type the code instead.',
                MobileScannerErrorCode.unsupported =>
                  'No camera available on this device — type the code instead.',
                _ => 'The camera could not be started — type the code instead.',
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Text(
                  'Point at the QR code on the host phone\'s "Phone as '
                  'camera" screen.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    shadows: const [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanError extends StatelessWidget {
  const _ScanError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(Spacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined,
                size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: Spacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.lg),
            FilledButton.tonal(
              onPressed: () => context.pop(),
              child: const Text('Type the code instead'),
            ),
          ],
        ),
      ),
    );
  }
}
