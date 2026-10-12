import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../config/subscription_endpoint.dart';

class SubscriptionResult {
  /// Whether the Telegram link code was claimed, or a status request verified
  /// an existing license. This is distinct from having an active subscription.
  final bool valid;
  final DateTime? expiresAt;
  final String? reason;
  final String? plan;
  final String? licenseToken;
  final String subscriptionStatus;

  const SubscriptionResult({
    required this.valid,
    this.expiresAt,
    this.reason,
    this.plan,
    this.licenseToken,
    this.subscriptionStatus = 'free',
  });

  factory SubscriptionResult.fromJson(
    Map<String, dynamic> json, {
    bool statusRequest = false,
  }) {
    // POTV bot API responds with {ok, license_token?, account:{status,...}}.
    // A successfully claimed code DOES NOT imply a paid subscription.
    final rawAccount = json['account'];
    final account = rawAccount is Map<String, dynamic>
        ? rawAccount
        : const <String, dynamic>{};
    final token = json['license_token'] is String
        ? (json['license_token'] as String).trim()
        : '';
    final status = account['status']?.toString().toLowerCase() ?? 'free';
    final expiryRaw = account['expires_at']?.toString();
    final expiry = expiryRaw == null
        ? null
        : DateTime.tryParse(expiryRaw)?.toUtc();

    return SubscriptionResult(
      valid: json['ok'] == true &&
          rawAccount is Map<String, dynamic> &&
          (statusRequest || token.isNotEmpty),
      expiresAt: expiry,
      reason: json['error']?.toString(),
      plan: account['plan']?.toString(),
      licenseToken: token.isEmpty ? null : token,
      subscriptionStatus: status,
    );
  }
}

class SubscriptionVerifier {
  final Dio _dio;
  static const _deviceKey = 'potv_device_id';
  static const _licenseKey = 'potv_license_token';

  SubscriptionVerifier([Dio? dio]) : _dio = dio ?? Dio();

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_deviceKey, id);
    }
    return id;
  }

  static Map<String, dynamic>? _body(Object? data) {
    try {
      if (data is Map<String, dynamic>) return data;
      if (data is String) {
        final parsed = jsonDecode(data);
        if (parsed is Map<String, dynamic>) return parsed;
      }
    } catch (_) {}
    return null;
  }

  Future<SubscriptionResult> verifyCode(String code) async {
    final normalizedCode = code.trim().toUpperCase();
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(normalizedCode)) {
      return const SubscriptionResult(valid: false, reason: 'invalid_code');
    }

    try {
      final deviceId = await _deviceId();
      final response = await _dio.post(
        SubscriptionEndpoint.verifyUrl,
        data: jsonEncode({'code': normalizedCode, 'device_id': deviceId}),
        options: Options(headers: {'Content-Type': 'application/json'}),
      ).timeout(const Duration(seconds: 15));
      final result = SubscriptionResult.fromJson(
        _body(response.data) ?? const <String, dynamic>{},
      );
      if (result.valid && result.licenseToken != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_licenseKey, result.licenseToken!);
      }
      return result;
    } on DioException catch (error) {
      return SubscriptionResult(
        valid: false,
        reason: _body(error.response?.data)?['error']?.toString() ??
            (error.response?.statusCode == 401 ? 'unauthorized' : 'network'),
      );
    } catch (_) {
      return const SubscriptionResult(valid: false, reason: 'network');
    }
  }

  /// Rechecks status with the server; never authorizes payment on the client.
  Future<SubscriptionResult> checkLicense() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_licenseKey);
    if (token == null || token.isEmpty) {
      return const SubscriptionResult(valid: false, reason: 'missing_token');
    }
    try {
      final response = await _dio.get(
        SubscriptionEndpoint.statusUrl,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ).timeout(const Duration(seconds: 15));
      return SubscriptionResult.fromJson(
        _body(response.data) ?? const <String, dynamic>{},
        statusRequest: true,
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      return SubscriptionResult(
        valid: false,
        reason: status == 401 ? 'invalid_token' : 'network',
      );
    } catch (_) {
      return const SubscriptionResult(valid: false, reason: 'network');
    }
  }
}
