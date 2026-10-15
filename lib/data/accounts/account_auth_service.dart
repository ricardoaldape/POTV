import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../config/subscription_endpoint.dart';
import 'user_account.dart';

class AccountAuthException implements Exception {
  final String code;
  const AccountAuthException(this.code);
}

class AccountAuthService {
  static const _sessionKey = 'potv_account_session_v1';
  final Dio _dio;
  final FlutterSecureStorage _secure;

  AccountAuthService({
    Dio? dio,
    FlutterSecureStorage? secureStorage,
  })  : _dio = dio ?? Dio(),
        _secure = secureStorage ?? const FlutterSecureStorage();

  Future<String?> sessionToken() => _secure.read(key: _sessionKey);

  Future<UserAccount> register({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      await _dio.post(
        SubscriptionEndpoint.registerUrl,
        data: {'email': email.trim(), 'password': password, 'name': name.trim()},
      );
      return login(email: email, password: password);
    } on DioException catch (error) {
      throw AccountAuthException(_errorCode(error));
    }
  }

  Future<UserAccount> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        SubscriptionEndpoint.loginUrl,
        data: {'email': email.trim(), 'password': password},
      );
      final body = Map<String, dynamic>.from(response.data as Map);
      final token = body['access_token']?.toString();
      final account = body['account'];
      if (token == null || token.isEmpty || account is! Map) {
        throw const AccountAuthException('invalid_response');
      }
      await _secure.write(key: _sessionKey, value: token);
      return UserAccount.fromApi(Map<String, dynamic>.from(account));
    } on AccountAuthException {
      rethrow;
    } on DioException catch (error) {
      throw AccountAuthException(_errorCode(error));
    }
  }

  Future<UserAccount?> restore() async {
    final token = await sessionToken();
    if (token == null || token.isEmpty) return null;
    try {
      final response = await _dio.get(
        SubscriptionEndpoint.sessionUrl,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final body = Map<String, dynamic>.from(response.data as Map);
      final account = body['account'];
      if (account is! Map) return null;
      return UserAccount.fromApi(Map<String, dynamic>.from(account));
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _secure.delete(key: _sessionKey);
        return null;
      }
      rethrow;
    }
  }

  Future<void> requestRecovery(String email) async {
    try {
      await _dio.post(
        SubscriptionEndpoint.recoverUrl,
        data: {'email': email.trim()},
      );
    } on DioException catch (error) {
      throw AccountAuthException(_errorCode(error));
    }
  }

  Future<void> confirmRecovery({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      await _dio.post(
        SubscriptionEndpoint.recoverConfirmUrl,
        data: {
          'email': email.trim(),
          'code': code.trim(),
          'new_password': newPassword,
        },
      );
    } on DioException catch (error) {
      throw AccountAuthException(_errorCode(error));
    }
  }

  Future<void> logout() async {
    final token = await sessionToken();
    if (token != null && token.isNotEmpty) {
      try {
        await _dio.post(
          SubscriptionEndpoint.logoutUrl,
          data: const <String, dynamic>{},
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      } catch (_) {
        // Local logout must work even when the network is unavailable.
      }
    }
    await _secure.delete(key: _sessionKey);
  }

  String _errorCode(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    if (error.response?.statusCode == 401) return 'invalid_credentials';
    return 'network';
  }
}
