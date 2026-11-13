import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

/// Pantalla inicial: login o registro de empresa.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.local_fire_department,
                  size: 80, color: AppTheme.primary),
              const SizedBox(height: 12),
              Text(
                'GasApp',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pedidos, reparto y control de balones para tu negocio de gas',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 48),
              FilledButton(
                onPressed: () => context.push('/login'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: AppTheme.primary,
                ),
                child: const Text('INICIAR SESIÓN',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => context.push('/registro-empresa'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  side: const BorderSide(color: AppTheme.primary, width: 1.5),
                  foregroundColor: AppTheme.primary,
                ),
                child: const Text('REGISTRAR MI EMPRESA',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 32),
              const Text(
                '¿Tienes un motorizado o repartidor?\nPide al administrador de tu empresa que te cree un usuario.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black45, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
