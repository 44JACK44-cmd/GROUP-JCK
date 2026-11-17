/// Widgets compartidos por las pantallas de pedidos, clientes y finanzas.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../domain/estado_pedido.dart';
import '../domain/formato.dart';
import '../domain/prioridad.dart';

/// Etiqueta de color con el nombre del estado.
class EstadoBadge extends StatelessWidget {
  final String estado;
  final bool compacto;

  EstadoBadge(this.estado, {super.key, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    final e = EstadoPedido.desdeDb(estado);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compacto ? 8 : 12, vertical: compacto ? 3 : 6),
      decoration: BoxDecoration(
        color: e.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        e.label,
        style: TextStyle(
          color: e.color,
          fontSize: compacto ? 11 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Tarjeta de una métrica (un número grande + su etiqueta).
class TarjetaMetrica extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;
  final VoidCallback? onTap;

  TarjetaMetrica({
    super.key,
    required this.titulo,
    required this.valor,
    required this.icono,
    this.color = AppTheme.primary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 22, color: color),
              SizedBox(height: 6),
              Text(
                valor,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 2),
              Text(titulo, style: TextStyle(color: AppColors.textoSecundario, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila etiqueta / valor.
class FilaValor extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final Color? color;
  final bool destacado;

  FilaValor(
    this.etiqueta,
    this.valor, {
    super.key,
    this.color,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              etiqueta,
              style: TextStyle(
                color: destacado ? AppColors.textoPrincipal : AppColors.textoSecundario,
                fontWeight: destacado ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          SizedBox(width: 12),
          Text(
            valor,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: destacado ? 18 : 15,
              color: color ?? (destacado ? AppTheme.primary : AppColors.textoPrincipal),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vacío con mensaje y acción opcional.
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? mensaje;
  final String? accionTexto;
  final VoidCallback? onAccion;

  EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    this.mensaje,
    this.accionTexto,
    this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: AppColors.textoMuted),
            SizedBox(height: 12),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (mensaje != null) ...[
              SizedBox(height: 6),
              Text(
                mensaje!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textoSecundario),
              ),
            ],
            if (accionTexto != null && onAccion != null) ...[
              SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAccion,
                icon: Icon(Icons.add),
                label: Text(accionTexto!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de un pedido, con antigüedad y prioridad calculadas.
///
/// Se usa en la lista del admin, en "Mis pedidos" del motorizado y en la
/// ficha del cliente. Muestra solo lo necesario para decidir.
class TarjetaPedido extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final VoidCallback onTap;
  final bool mostrarPrioridad;
  final Widget? trailer;
  final String? productoResumen;
  final String? motorizadoNombre;
  final List<Widget>? acciones;

  TarjetaPedido({
    super.key,
    required this.pedido,
    required this.onTap,
    this.mostrarPrioridad = true,
    this.trailer,
    this.productoResumen,
    this.motorizadoNombre,
    this.acciones,
  });

  @override
  Widget build(BuildContext context) {
    final cliente = pedido['clientes'] as Map<String, dynamic>?;
    final estado = pedido['estado'] as String? ?? 'NUEVO';
    final fecha = parseFecha(pedido['fecha']);
    final prioridad = Prioridad.de(fecha);
    final total = (pedido['total'] as num? ?? 0).toDouble();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (mostrarPrioridad && estado != 'ENTREGADO' && estado != 'CANCELADO') ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: prioridad.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      cliente?['nombre'] as String? ?? 'Cliente',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    dinero(total),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                [
                  if ((cliente?['direccion'] as String? ?? '').isNotEmpty)
                    cliente?['direccion'] as String,
                  if (productoResumen != null && productoResumen!.isNotEmpty)
                    productoResumen,
                  if (mostrarPrioridad && fecha != null) antiguedad(fecha),
                ].join('  ·  '),
                style: TextStyle(color: AppColors.textoSecundario, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (motorizadoNombre != null && motorizadoNombre!.isNotEmpty) ...[
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.delivery_dining_outlined, size: 13, color: AppColors.textoMuted),
                    SizedBox(width: 4),
                    Text(
                      motorizadoNombre!,
                      style: TextStyle(color: AppColors.textoMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ],
              SizedBox(height: 10),
              Row(
                children: [
                  EstadoBadge(estado, compacto: true),
                  Spacer(),
                  if (trailer != null) trailer! else SizedBox.shrink(),
                ],
              ),
              if (acciones != null && acciones!.isNotEmpty) ...[
                SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < acciones!.length; i++) ...[
                      if (i > 0) SizedBox(width: 8),
                      Expanded(child: acciones![i]),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}