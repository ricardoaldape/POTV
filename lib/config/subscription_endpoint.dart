class SubscriptionEndpoint {
  static const String _base = 'https://potv.fxqubit.com/api/v1';

  static const String verifyUrl = '$_base/link/claim';
  static const String registerUrl = '$_base/account/register';
  static const String loginUrl = '$_base/account/login';
  static const String sessionUrl = '$_base/account/session';
  static const String logoutUrl = '$_base/account/logout';
  static const String recoverUrl = '$_base/account/recover';
  static const String recoverConfirmUrl = '$_base/account/recover/confirm';
  static const String licenseStatusUrl = '$_base/license/status';
}
