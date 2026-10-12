import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../config/subscription_endpoint.dart';

class SubscriptionResult {
  final bool linked;
  final String status;
  final DateTime? expiresAt;
  final String? reason;
  final String? plan;
  final String? telegramChatId;

  const SubscriptionResult({
    required this.linked,
    required this.status,
    this.expiresAt,
    this.reason,
    this.plan,
    this.telegramChatId,
  });

  bool get active => status == 'active';

  factory SubscriptionResult.fromJson(Map<String, dynamic> json) =>
      SubscriptionResult(
        linked: json['ok'] == true,
        status: json['status']?.toString() ?? 'free',
        expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '')?.toUtc(),
        reason: json['error']?.toString(),
        plan: json['plan']?.toString(),
        telegramChatId: json['telegram_chat_id']?.toString(),
      );
}

class SubscriptionVerifier {
  static const _deviceKey = 'potv_device_id';
  static const _licenseKey = 'potv_license_token_v2';
  final Dio _dio;
  final FlutterSecureStorage _secure;

  SubscriptionVerifier({
    Dio? dio,
    FlutterSecureStorage? secureStorage,
  })  : _dio = dio ?? Dio(),
        _secure = secureStorage ?? const FlutterSecureStorage();

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_deviceKey, id);
    }
    return id;
  }

  Future<SubscriptionResult> verifyCode(
    String code, {
    String? accountSessionToken,
  }) async {
    try {
      final response = await _dio
          .post(
            SubscriptionEndpoint.verifyUrl,
            data: json.encode({
              'code': code.trim().toUpperCase(),
              'device_id': await _deviceId(),
            }),
            options: Options(
              headers: {
                'Content-Type': 'application/json',
                if (accountSessionToken != null && accountSessionToken.isNotEmpty)
                  'Authorization': 'Bearer $accountSessionToken',
              },
            ),
          )
          .timeout(const Duration(seconds: 15));
      final data = response.data is String
          ? json.decode(response.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(response.data as Map);
      final token = data['license_token']?.toString();
      if (token != null && token.isNotEmpty) {
        await _secure.write(key: _licenseKey, value: token);
      }
      return SubscriptionResult.fromJson(data);
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map) {
        return SubscriptionResult.fromJson(Map<String, dynamic>.from(data));
      }
      return const SubscriptionResult(
        linked: false,
        status: 'free',
        reason: 'network',
      );
    } catch (_) {
      return const SubscriptionResult(
        linked: false,
        status: 'free',
        reason: 'exception',
      );
    }
  }
}
