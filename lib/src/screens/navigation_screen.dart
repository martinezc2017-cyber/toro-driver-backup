import 'package:flutter/material.dart';

class NavigationScreen extends StatelessWidget {
  const NavigationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Navegación')),
      body: const Center(
        child: Text('Aquí irá el mapa de navegación y seguimiento del viaje.'),
      ),
    );
  }
}
