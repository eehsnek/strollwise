import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

import '../../core/constants/api_constants.dart';
import '../providers/app_providers.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: '${ApiConstants.baseUrl}${ApiConstants.apiPrefix}',
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 12),
      contentType: 'application/json',
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(authTokenProvider);
        if (token != null &&
            token.isNotEmpty &&
            token != 'demo-token-local') {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final status = error.response?.statusCode;
        final path = error.requestOptions.path;
        final hadAuth = error.requestOptions.headers['Authorization'] != null;
        final isAuthRoute = path.contains('/auth/login') ||
            path.contains('/auth/register');
        if (status == 401 && hadAuth && !isAuthRoute) {
          final token = ref.read(authTokenProvider);
          if (token != null &&
              token.isNotEmpty &&
              token != 'demo-token-local') {
            await clearPersistedAuth();
            ref.read(authTokenProvider.notifier).state = null;
            ref.read(authUserEmailProvider.notifier).state = null;
            ref.read(cachedUserMeProvider.notifier).state = null;
            routerRefreshListenable.value++;
          }
        }
        handler.next(error);
      },
    ),
  );

  if (!kIsWeb) {
    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        // Keep simulator/device traffic direct to the local backend and avoid
        // stale system proxy settings that can break localhost requests.
        client.findProxy = (_) => 'DIRECT';
        return client;
      };
    }
  }

  return dio;
});
