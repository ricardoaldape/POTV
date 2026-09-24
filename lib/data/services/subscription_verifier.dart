import 'dart:convert';

import 'package:dio/dio.dart';

import '../../config/subscription_endpoint.dart';

class SubscriptionResult {
  final bool valid;
  final DateTime? expiresAt;
  final String? reason;
  final String? plan;

  SubscriptionResult({
    required this.valid,
    this.expiresAt,
    this.reason,
    this.plan,
  });

  factory SubscriptionResult.fromJson(Map<String, dynamic> json) {
    return SubscriptionResult(
      valid: json['valid'] as bool? ?? false,
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt'] as String).toUtc() : null,
      reason: json['reason'] as String?,
      plan: json['plan'] as String?,
    );
  }
}

class SubscriptionVerifier {
  final Dio _dio;

  SubscriptionVerifier([Dio? dio]) : _dio = dio ?? Dio();

  Future<SubscriptionResult> verifyCode(String code) async {
    try {
      final url = '${SubscriptionEndpoint.verifyUrl}?code=$code';
      final resp = await _dio.get(url).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = resp.data is String ? json.decode(resp.data as String) as Map<String, dynamic> : resp.data as Map<String, dynamic>;
        return SubscriptionResult.fromJson(data);
      }
      return SubscriptionResult(valid: false, reason: 'network');
    } catch (e) {
      return SubscriptionResult(valid: false, reason: 'exception');
    }
  }
}
