import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potv/data/accounts/user_account.dart';
import 'package:potv/data/services/subscription_verifier.dart';
import 'package:potv/providers/user_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Dio mockDio({
    required Map<String, dynamic> claim,
    Map<String, dynamic>? status,
    int claimCode = 200,
  }) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method == 'POST') {
            if (claimCode != 200) {
              return handler.reject(DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: claimCode,
                  data: claim,
                ),
                type: DioExceptionType.badResponse,
              ));
            }
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: claim,
            ));
          }
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: status ?? claim,
          ));
        },
      ),
    );
    return dio;
  }

  test('successful Telegram code claim can still have a free account', () async {
    final dio = mockDio(claim: {
      'ok': true,
      'license_token': 'test-license-token',
      'account': {
        'status': 'free',
        'plan': 'POTV',
        'expires_at': null,
      },
    });
    final verifier = SubscriptionVerifier(dio);
    final result = await verifier.verifyCode('a1b2c3d4e5f6');
    expect(result.valid, isTrue);
    expect(result.subscriptionStatus, 'free');
    expect(result.licenseToken, 'test-license-token');
    expect(
      (await SharedPreferences.getInstance())
          .getString('potv_license_token'),
      'test-license-token',
    );
  });

  test('free claim does not activate the app subscription', () async {
    final dio = mockDio(claim: {
      'ok': true,
      'license_token': 'test-license-token',
      'account': {'status': 'free', 'plan': 'POTV', 'expires_at': null},
    });
    final container = ProviderContainer(overrides: [
      subscriptionVerifierProvider.overrideWithValue(SubscriptionVerifier(dio)),
    ]);
    addTearDown(container.dispose);
    await container.read(userAccountProvider.notifier).createAccount('Demo');
    final reason = await container
        .read(userAccountProvider.notifier)
        .linkSubscription('A1B2C3D4E5F6');
    expect(reason, isNull);
    expect(container.read(userAccountProvider)?.subscriptionStatus,
        SubscriptionStatus.free);
  });

  test('active status is read from nested server account fields', () async {
    final now = DateTime.now().toUtc();
    final expiry = now.add(const Duration(days: 29)).toIso8601String();
    final dio = mockDio(
      claim: {
        'ok': true,
        'license_token': 'test-license-token',
        'account': {'status': 'active', 'expires_at': expiry},
      },
      status: {
        'ok': true,
        'account': {'status': 'active', 'expires_at': expiry},
      },
    );
    final verifier = SubscriptionVerifier(dio);
    final claim = await verifier.verifyCode('A1B2C3D4E5F6');
    expect(claim.valid, isTrue);
    expect(claim.subscriptionStatus, 'active');
    expect(claim.expiresAt, isNotNull);

    final verified = await verifier.checkLicense();
    expect(verified.valid, isTrue);
    expect(verified.subscriptionStatus, 'active');
  });

  test('rejected code keeps license unlinked and surfaces server error',
      () async {
    final dio = mockDio(
      claim: {'ok': false, 'error': 'invalid_or_expired_code'},
      claimCode: 400,
    );
    final result =
        await SubscriptionVerifier(dio).verifyCode('A1B2C3D4E5F6');
    expect(result.valid, isFalse);
    expect(result.reason, 'invalid_or_expired_code');
    expect(
      (await SharedPreferences.getInstance())
          .getString('potv_license_token'),
      isNull,
    );
  });
  test('expired cached premium never remains active while offline', () async {
    final expiredYesterday = DateTime.now().toUtc()
        .subtract(const Duration(days: 1))
        .toIso8601String();
    SharedPreferences.setMockInitialValues({
      'potv_user_account': '''{
        "id":"account-1",
        "username":"Demo",
        "createdAt":"2026-01-01T00:00:00Z",
        "subscriptionStatus":2,
        "subscriptionExpiresAt":"$expiredYesterday"
      }''',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(userAccountProvider);
    await container.read(userAccountRepositoryProvider.future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      container.read(userAccountProvider)?.subscriptionStatus,
      SubscriptionStatus.expired,
    );
    final stored = (await SharedPreferences.getInstance())
        .getString('potv_user_account');
    expect(stored, contains('"subscriptionStatus":3'));
  });

}
