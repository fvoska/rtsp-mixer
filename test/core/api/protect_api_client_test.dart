import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/core/api/protect_api_client.dart';
import 'package:rtsp_mixer/features/cameras/models/protect_camera.dart';

void main() {
  group('ProtectApiClient', () {
    test('parses camera fixture JSON correctly', () {
      // Test the parsing logic directly with fixture data
      final json = jsonDecode(File('test/fixtures/bootstrap.json').readAsStringSync()) as List;
      final cameras = json.map((c) => ProtectCamera.fromJson(c as Map<String, dynamic>)).toList();

      expect(cameras, hasLength(3));
      expect(cameras[0].id, 'cam-001');
      expect(cameras[0].name, 'Nursery');
      expect(cameras[0].isConnected, true);
      expect(cameras[0].isMicEnabled, true);
      expect(cameras[2].isConnected, false);
    });

    test('client can be created and configured', () {
      final client = ProtectApiClient();
      client.setApiKey('test-key');
      // No exception means success — actual HTTP calls tested via integration
    });
  });
}
