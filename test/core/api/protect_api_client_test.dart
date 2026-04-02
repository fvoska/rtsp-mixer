import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:rtsp_audio_mixer/core/api/protect_api_client.dart';
import 'package:rtsp_audio_mixer/core/api/protect_auth_interceptor.dart';
import 'package:rtsp_audio_mixer/core/models/app_error.dart';

@GenerateMocks([Dio])
import 'protect_api_client_test.mocks.dart';

void main() {
  late MockDio mockDio;
  late ProtectAuthInterceptor authInterceptor;
  late ProtectApiClient client;

  setUp(() {
    mockDio = MockDio();
    authInterceptor = ProtectAuthInterceptor();

    // Mock interceptors list
    when(mockDio.interceptors).thenReturn(Interceptors());

    client = ProtectApiClient(
      dio: mockDio,
      authInterceptor: authInterceptor,
    );
  });

  group('ProtectApiClient', () {
    group('login', () {
      test('returns true on successful authentication', () async {
        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
              data: {},
            ));

        final result =
            await client.login('192.168.1.1', 'admin', 'password');
        expect(result, true);
      });

      test('returns false on invalid credentials (401)', () async {
        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 401,
              data: {},
            ));

        final result =
            await client.login('192.168.1.1', 'admin', 'wrong');
        expect(result, false);
      });

      test('fetches initial CSRF token if login returns 403', () async {
        var callCount = 0;

        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            // First call returns 403
            throw DioException(
              requestOptions: RequestOptions(path: ''),
              response: Response(
                requestOptions: RequestOptions(path: ''),
                statusCode: 403,
              ),
              type: DioExceptionType.badResponse,
            );
          }
          // Second call succeeds
          return Response(
            requestOptions: RequestOptions(path: ''),
            statusCode: 200,
            data: {},
          );
        });

        when(mockDio.get(
          any,
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
              headers: Headers.fromMap({
                'x-csrf-token': ['initial-csrf-token'],
              }),
            ));

        final result =
            await client.login('192.168.1.1', 'admin', 'password');
        expect(result, true);

        // Verify GET was called to fetch initial CSRF
        verify(mockDio.get(
          'https://192.168.1.1/',
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws AppError on connection error', () async {
        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.connectionError,
        ));

        expect(
          () => client.login('192.168.1.1', 'admin', 'password'),
          throwsA(isA<AppError>().having(
            (e) => e.type,
            'type',
            AppErrorType.connectionRefused,
          )),
        );
      });

      test('sends correct login body', () async {
        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
              data: {},
            ));

        await client.login('192.168.1.1', 'admin', 'password');

        verify(mockDio.post(
          'https://192.168.1.1/api/auth/login',
          data: {
            'username': 'admin',
            'password': 'password',
            'rememberMe': true,
            'token': '',
          },
          options: anyNamed('options'),
        )).called(1);
      });
    });

    group('getBootstrap', () {
      test('parses bootstrap JSON into camera list', () async {
        final bootstrapData = jsonDecode(
          File('test/fixtures/bootstrap.json').readAsStringSync(),
        );

        when(mockDio.get(
          any,
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
              data: bootstrapData,
            ));

        final cameras = await client.getBootstrap('192.168.1.1');

        expect(cameras, hasLength(3));
        expect(cameras[0].id, 'cam-001');
        expect(cameras[0].name, 'Nursery');
        expect(cameras[1].name, 'Bedroom');
        expect(cameras[2].name, 'Garage');
      });

      test('extracts lastUpdateId from bootstrap response', () async {
        final bootstrapData = jsonDecode(
          File('test/fixtures/bootstrap.json').readAsStringSync(),
        );

        when(mockDio.get(
          any,
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
              data: bootstrapData,
            ));

        await client.getBootstrap('192.168.1.1');
        expect(client.lastUpdateId, 'abc123');
      });

      test('calls correct bootstrap endpoint', () async {
        final bootstrapData = jsonDecode(
          File('test/fixtures/bootstrap.json').readAsStringSync(),
        );

        when(mockDio.get(
          any,
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
              data: bootstrapData,
            ));

        await client.getBootstrap('192.168.1.1');

        verify(mockDio.get(
          'https://192.168.1.1/proxy/protect/api/bootstrap',
          options: anyNamed('options'),
        )).called(1);
      });
    });
  });
}
