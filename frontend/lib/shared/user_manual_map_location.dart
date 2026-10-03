import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'network/api_client.dart';
import 'providers/app_providers.dart';

/// Persists manual map coordinates to `PATCH /users/me` for the signed-in user.
/// Returns false for demo sessions or failed requests.
Future<bool> persistUserManualMapLocation(WidgetRef ref, LatLng location) async {
  final token = ref.read(authTokenProvider);
  if (token == null || token == 'demo-token-local') {
    return false;
  }
  try {
    final dio = ref.read(dioProvider);
    await dio.patch(
      '/users/me',
      data: {
        'manual_map_lat': location.latitude,
        'manual_map_lng': location.longitude,
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);
    ref.invalidate(userMeProvider);
    try {
      await ref.read(userMeProvider.future);
    } catch (_) {}
    return true;
  } on DioException {
    return false;
  } on FormatException {
    return false;
  } on TypeError {
    return false;
  }
}
