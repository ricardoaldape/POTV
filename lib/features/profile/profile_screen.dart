import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(radius: 30, child: Icon(Icons.person_rounded, size: 32)),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Perfil local POTV', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        SizedBox(height: 4),
                        Text('Cuenta y sincronización entre dispositivos se conectarán aquí.', style: TextStyle(color: Colors.white60)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.bookmark_rounded),
            title: const Text('Mi lista e historial'),
            onTap: () => context.push('/library'),
          ),
          ListTile(
            leading: const Icon(Icons.search_rounded),
            title: const Text('Buscar en POTV'),
            onTap: () => context.push('/search'),
          ),
          ListTile(
            leading: const Icon(Icons.extension_rounded),
            title: const Text('Fuentes y extensiones'),
            onTap: () => context.push('/sources'),
          ),
          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: const Text('Ajustes'),
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }
}
