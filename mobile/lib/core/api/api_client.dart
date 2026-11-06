import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../env.dart';
import 'models.dart';

/// Thin wrapper over Dio. Feature repositories call into this; no provider API
/// keys ever live here — all third-party calls are proxied by the backend.
class ApiClient {
  final Dio _dio;

  ApiClient(this._dio);

  factory ApiClient.create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
      ),
    );
    return ApiClient(dio);
  }

  Future<MetaInfo> fetchMeta() async {
    final res = await _dio.get('/meta');
    return MetaInfo.fromJson(res.data as Map<String, dynamic>);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient.create());

final metaProvider = FutureProvider<MetaInfo>((ref) async {
  return ref.watch(apiClientProvider).fetchMeta();
});
