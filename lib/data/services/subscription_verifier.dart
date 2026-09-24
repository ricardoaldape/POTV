import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../config/subscription_endpoint.dart';

class SubscriptionResult {
  final bool valid;
  final DateTime? expiresAt;
  final String? reason;
  final String? plan;
  final String? licenseToken;

  SubscriptionResult({
    required this.valid,
    this.expiresAt,
    this.reason,
    this.plan,
    this.licenseToken,
  });

  factory SubscriptionResult.fromJson(Map<String, dynamic> json) {
    return SubscriptionResult(
      valid: json['status'] == 'active' || (json['valid'] as bool? ?? false),
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String).toUtc() : null,
      reason: json['error'] as String?,
      plan: json['plan'] as String?,
      licenseToken: json['license_token'] as String?,
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

  Future<SubscriptionResult> verifyCode(String code) async {
    try {
      final url = SubscriptionEndpoint.verifyUrl;
      final deviceId = await _deviceId();
      final body = json.encode({'code': code, 'device_id': deviceId});
      final resp = await _dio.post(url,
          data: body,
          options: Options(headers: {'Content-Type': 'application/json'})).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = resp.data is String ? json.decode(resp.data as String) as Map<String, dynamic> : resp.data as Map<String, dynamic>;
        final result = SubscriptionResult.fromJson(data);
        if (result.licenseToken != null && result.licenseToken!.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_licenseKey, result.licenseToken!);
        }
        return result;
      }

      // Try parse error body
      if (resp.data != null) {
        final data = resp.data is String ? json.decode(resp.data as String) as Map<String, dynamic> : resp.data as Map<String, dynamic>;
        return SubscriptionResult.fromJson(data);
      }

      return SubscriptionResult(valid: false, reason: 'network');
    } catch (e) {
      return SubscriptionResult(valid: false, reason: 'exception');
    }
  }
}
