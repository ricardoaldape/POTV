/// Builds an individually configured Stremio manifest URL on the user's
/// device. Never embed a personal token in POTV source, APK assets or CI.
class PrivateAddonLink {
  const PrivateAddonLink._();

  static Uri penguPlay(String supplied) {
    final text = supplied.trim();
    if (text.startsWith('https://')) {
      final uri = Uri.tryParse(text);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'pengu.uk' ||
          uri.userInfo.isNotEmpty ||
          !uri.path.endsWith('/manifest.json')) {
        throw const FormatException('Enlace privado no válido.');
      }
      return uri;
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]{20,256}$').hasMatch(text)) {
      throw const FormatException('El código de acceso no es válido.');
    }
    final encoded = Uri.encodeComponent('{"auth_token":"$text"}');
    return Uri.parse('https://pengu.uk/$encoded/manifest.json');
  }
}
