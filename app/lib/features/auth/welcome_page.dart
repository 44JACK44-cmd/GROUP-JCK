import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';

/// Pantalla inicial: login o registro de empresa.
class WelcomePage extends StatelessWidget {
  WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // Configuración disponible antes de iniciar sesión.
        actions: [
          IconButton(
            tooltip: 'Configuración',
            icon: Icon(Icons.settings_outlined),
            onPressed: () => context.push('/ajustes'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.local_fire_department,
                  size: 80, color: AppTheme.primary),
              SizedBox(height: 12),
              Text(
                'GasApp',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
              ),
              SizedBox(height: 8),
              Text(
                'Pedidos, reparto y control de balones para tu negocio de gas',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textoSecundario),
              ),
              SizedBox(height: 48),
              FilledButton(
                onPressed: () => context.push('/login'),
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(54),
                  backgroundColor: AppTheme.primary,
                ),
                child: Text('INICIAR SESIÓN',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => context.push('/registro-empresa'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(54),
                  side: BorderSide(color: AppTheme.primary, width: 1.5),
                  foregroundColor: AppTheme.primary,
                ),
                child: Text('REGISTRAR MI EMPRESA',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              SizedBox(height: 32),
              Text(
                '¿Tienes un motorizado o repartidor?\nPide al administrador de tu empresa que te cree un usuario.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textoMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}