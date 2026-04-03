import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_audio_mixer/features/cameras/models/protect_camera.dart';

void main() {
  late List<dynamic> fixture;

  setUpAll(() {
    fixture = jsonDecode(File('test/fixtures/bootstrap.json').readAsStringSync()) as List;
  });

  group('ProtectCamera', () {
    test('parses from JSON', () {
      final cam = ProtectCamera.fromJson(fixture[0] as Map<String, dynamic>);
      expect(cam.id, 'cam-001');
      expect(cam.name, 'Nursery');
      expect(cam.state, 'CONNECTED');
      expect(cam.isConnected, true);
      expect(cam.isMicEnabled, true);
    });

    test('rtspsStreamUrls is empty by default from JSON', () {
      final cam = ProtectCamera.fromJson(fixture[0] as Map<String, dynamic>);
      expect(cam.rtspsStreamUrls, isEmpty);
      expect(cam.defaultStreamUrl, isNull);
    });

    test('copyWith sets rtspsStreamUrls', () {
      final cam = ProtectCamera.fromJson(fixture[0] as Map<String, dynamic>);
      final urls = {'high': 'rtsps://1.2.3.4:7441/h', 'medium': 'rtsps://1.2.3.4:7441/m'};
      final updated = cam.copyWith(rtspsStreamUrls: urls);
      expect(updated.rtspsStreamUrls, urls);
      expect(updated.defaultStreamUrl, 'rtsps://1.2.3.4:7441/m');
      expect(updated.defaultQuality, 'medium');
      expect(updated.id, 'cam-001');
    });

    test('defaultStreamUrl prefers medium over high', () {
      final cam = ProtectCamera(
        id: 'x', state: 'CONNECTED',
        rtspsStreamUrls: {'high': 'h', 'medium': 'm', 'low': 'l'},
      );
      expect(cam.defaultStreamUrl, 'm');
      expect(cam.defaultQuality, 'medium');
    });

    test('defaultStreamUrl falls back to high when no medium', () {
      final cam = ProtectCamera(
        id: 'x', state: 'CONNECTED',
        rtspsStreamUrls: {'high': 'h'},
      );
      expect(cam.defaultStreamUrl, 'h');
      expect(cam.defaultQuality, 'high');
    });

    test('isConnected false for DISCONNECTED', () {
      final cam = ProtectCamera.fromJson(fixture[2] as Map<String, dynamic>);
      expect(cam.isConnected, false);
    });

    test('defaults state to DISCONNECTED when missing', () {
      final cam = ProtectCamera.fromJson({'id': 'x', 'name': 'X'});
      expect(cam.isConnected, false);
      expect(cam.state, 'DISCONNECTED');
    });

    test('defaults isMicEnabled to false', () {
      final cam = ProtectCamera.fromJson({'id': 'x', 'state': 'CONNECTED'});
      expect(cam.isMicEnabled, false);
    });
  });
}
