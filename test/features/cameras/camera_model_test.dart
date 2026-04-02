import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_audio_mixer/features/cameras/models/protect_camera.dart';
import 'package:rtsp_audio_mixer/features/cameras/models/stream_channel.dart';

void main() {
  late Map<String, dynamic> bootstrapData;
  late List<dynamic> camerasJson;

  setUpAll(() {
    final file = File('test/fixtures/bootstrap.json');
    bootstrapData = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    camerasJson = bootstrapData['cameras'] as List<dynamic>;
  });

  group('StreamChannel', () {
    test('parses channel from JSON', () {
      final json = {
        'id': 0,
        'name': 'High',
        'rtspAlias': 'nursery_high',
        'isRtspEnabled': true,
      };
      final channel = StreamChannel.fromJson(json);

      expect(channel.id, 0);
      expect(channel.name, 'High');
      expect(channel.rtspAlias, 'nursery_high');
      expect(channel.isRtspEnabled, true);
    });

    test('defaults rtspAlias to empty string when missing', () {
      final json = {
        'id': 0,
        'name': 'High',
        'isRtspEnabled': false,
      };
      final channel = StreamChannel.fromJson(json);
      expect(channel.rtspAlias, '');
    });

    test('defaults isRtspEnabled to false when missing', () {
      final json = {
        'id': 0,
        'name': 'High',
        'rtspAlias': 'test',
      };
      final channel = StreamChannel.fromJson(json);
      expect(channel.isRtspEnabled, false);
    });
  });

  group('ProtectCamera', () {
    test('parses camera from bootstrap JSON', () {
      final camera =
          ProtectCamera.fromJson(camerasJson[0] as Map<String, dynamic>);

      expect(camera.id, 'cam-001');
      expect(camera.name, 'Nursery');
      expect(camera.type, 'UVC G4 Dome');
      expect(camera.state, 'CONNECTED');
      expect(camera.isConnected, true);
      expect(camera.channels, hasLength(3));
    });

    test('parses all cameras from bootstrap fixture', () {
      final cameras = camerasJson
          .map((c) => ProtectCamera.fromJson(c as Map<String, dynamic>))
          .toList();

      expect(cameras, hasLength(3));
      expect(cameras[0].name, 'Nursery');
      expect(cameras[1].name, 'Bedroom');
      expect(cameras[2].name, 'Garage');
    });

    test('reports isConnected correctly', () {
      final cameras = camerasJson
          .map((c) => ProtectCamera.fromJson(c as Map<String, dynamic>))
          .toList();

      expect(cameras[0].isConnected, true); // Nursery
      expect(cameras[1].isConnected, true); // Bedroom
      expect(cameras[2].isConnected, false); // Garage
    });

    test('generates RTSP URL from first enabled channel', () {
      final camera =
          ProtectCamera.fromJson(camerasJson[0] as Map<String, dynamic>);

      expect(
        camera.rtspUrl('192.168.1.1'),
        'rtsp://192.168.1.1:7447/nursery_high',
      );
    });

    test('generates encrypted RTSPS URL when requested', () {
      final camera =
          ProtectCamera.fromJson(camerasJson[0] as Map<String, dynamic>);

      expect(
        camera.rtspUrl('192.168.1.1', encrypted: true),
        'rtsps://192.168.1.1:7441/nursery_high?enableSrtp',
      );
    });

    test('returns null RTSP URL when no channel has RTSP enabled', () {
      final camera =
          ProtectCamera.fromJson(camerasJson[2] as Map<String, dynamic>);

      expect(camera.rtspUrl('192.168.1.1'), isNull);
    });
  });
}
