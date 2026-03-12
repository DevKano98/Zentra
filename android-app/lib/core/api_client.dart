import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'constants.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  late Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    final backendUrl = await _storage.read(key: kStorageBackendUrl) ?? kDefaultBackendUrl;

    _dio = Dio(BaseOptions(
      baseUrl: backendUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: kStorageJwtToken);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            // Token expired — clear and let caller handle
            await _storage.delete(key: kStorageJwtToken);
          }
          handler.next(error);
        },
      ),
    );

    _initialized = true;
  }

  Future<Dio> getDio() async {
    await ensureInitialized();
    return _dio;
  }

  Future<void> updateBaseUrl(String newUrl) async {
    await _storage.write(key: kStorageBackendUrl, value: newUrl);
    _initialized = false;
    await ensureInitialized();
  }

  Future<WebSocketChannel> connectCallWebSocket(String callId) async {
    final backendUrl = await _storage.read(key: kStorageBackendUrl) ?? kDefaultBackendUrl;
    final token = await _storage.read(key: kStorageJwtToken) ?? '';

    final wsUrl = backendUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    final uri = Uri.parse('$wsUrl/ws/calls/$callId?token=$token');
    return WebSocketChannel.connect(uri);
  }
}