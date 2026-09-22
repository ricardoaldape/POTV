import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Privacidad local-first'),
            subtitle: Text('Fuentes, historial y credenciales permanecen en el dispositivo.'),
          ),
          ListTile(
            leading: Icon(Icons.devices),
            title: Text('Sincronizar dispositivos'),
            subtitle: Text('Próximamente: transferencia local cifrada móvil ↔ Android TV.'),
          ),
          ListTile(
            leading: Icon(Icons.extension),
            title: Text('Addons'),
            subtitle: Text('Stremio, Nuvio y Kodi se implementarán después de Live TV y Sports Hub.'),
          ),
        ],
      ),
    );
  }
}
