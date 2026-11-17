/// Reglas del rediseño que se pueden comprobar sin red:
/// el bus avisa a todas las pantallas y la interfaz no contiene emojis.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/app/theme.dart';
import 'package:gas_app/core/state/bus.dart';
import 'package:gas_app/core/ui/diseno.dart';

void main() {
  group('SyncBus', () {
    test('un cambio de pedido avisa pedidos, dinero, movimientos y rendición', () {
      final a = SyncBus.pedidos.value;
      final b = SyncBus.dinero.value;
      final c = SyncBus.movimientos.value;
      final d = SyncBus.rendiciones.value;

      SyncBus.pedidoYdinero();

      expect(SyncBus.pedidos.value, a + 1);
      expect(SyncBus.dinero.value, b + 1);
      expect(SyncBus.movimientos.value, greaterThan(c));
      expect(SyncBus.rendiciones.value, d + 1);
    });

    test('conexión y sincronización son observables', () {
      final antes = SyncBus.movimientos.value;
      SyncBus.conexionCambio(false);
      expect(SyncBus.enLinea.value, isFalse);
      expect(SyncBus.movimientos.value, antes + 1);

      SyncBus.sincronizandoCambio(true);
      expect(SyncBus.sincronizando.value, isTrue);
      SyncBus.sincronizandoCambio(false);
      SyncBus.conexionCambio(true);
    });
  });

  group('paleta del sistema', () {
    test('el modo oscuro es negro neutro, no azul', () {
      expect(AppTheme.dark().scaffoldBackgroundColor, const Color(0xFF0B0B0B));
      expect(AppTheme.dark().colorScheme.surface, const Color(0xFF151515));
      expect(AppTheme.dark().cardTheme.color, const Color(0xFF151515));
      expect(AppTheme.dark().colorScheme.primary, AppTheme.primary);
    });

    test('el modo claro es gris claro con superficies blancas', () {
      expect(AppTheme.light().scaffoldBackgroundColor, const Color(0xFFF7F7F7));
      expect(AppTheme.light().colorScheme.surface, const Color(0xFFFFFFFF));
    });
  });

  group('iconografía profesional', () {
    test('cada tipo de movimiento tiene icono y color', () {
      for (final tipo in ['PEDIDO', 'PAGO', 'GASTO', 'INCIDENCIA', 'BALON']) {
        expect(iconoMovimiento(tipo), isNotNull);
        expect(colorMovimiento(tipo), isNotNull);
      }
    });

    test('ningún archivo Dart de lib contiene emojis', () {
      final raiz = Directory('lib');
      final permitidos = <int>{
        0x00B0, 0x00A1, 0x00BF, // ° ¡ ¿
      };
      final encontrados = <String>[];
      for (final archivo in raiz
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final contenido = archivo.readAsStringSync();
        for (final rune in contenido.runes) {
          final esEmoji = (rune >= 0x2600 && rune <= 0x27BF) ||
              (rune >= 0x1F000 && rune <= 0x1FAFF) ||
              rune == 0xFE0F;
          if (esEmoji && !permitidos.contains(rune)) {
            encontrados.add('${archivo.path}: U+${rune.toRadixString(16)}');
            break;
          }
        }
      }
      expect(encontrados, isEmpty, reason: encontrados.join('\n'));
    });
  });
}
