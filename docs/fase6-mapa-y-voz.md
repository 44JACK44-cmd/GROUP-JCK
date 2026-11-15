# Mapa y voz de navegación (ETAPA C)

## Qué quedó implementado

| Función | Dónde | Comportamiento |
|---|---|---|
| Ruta en la app con Google Maps | `app/lib/features/rutas/ruta_page.dart` | Mapa de Google + recorrido real (Directions) + marcador del cliente |
| Indicaciones reales | `app/lib/core/maps/ruta_service.dart` | Se muestran y se leen los textos que devuelve Google, con su distancia. Nunca se inventan |
| Asistente de voz en español | `app/lib/core/audio/voz_service.dart` | `flutter_tts` en `es-PE` (respaldo `es-ES`). Solo habla si hay ruta real |
| Aviso sin clave | `ruta_page.dart` | Mapa alternativo (OpenStreetMap) + mensaje claro + botón "Abrir en Google Maps" |
| Ajuste local | Ajustes → "Navegar dentro de la app" / "Asistente de voz" | Activados por defecto; se guardan solo en el teléfono |

La ruta se abre desde **Pedido → Ir al cliente** y al tocar **Iniciar ruta**.

## Cómo activar Google Maps (el desarrollador)

La clave **nunca** se escribe en el código ni se sube al repositorio.

1. En Google Cloud Console, habilitar en el mismo proyecto:
   - **Maps SDK for Android**
   - **Directions API**
2. Crear una clave de API y **restringirla**:
   - Restricción de aplicación: *Android apps* → `com.grupojck.gas_app` + huella SHA-1 del keystore.
   - Restricción de API: solo *Maps SDK for Android* y *Directions API*.
3. Poner la clave en los dos sitios, con el **mismo** valor:

   **a) `app/android/local.properties`** (ignorado por git):
   ```properties
   maps.apiKey=AIza...tu_clave
   ```

   **b) al compilar** (Dart la usa para Directions):
   ```powershell
   flutter build apk --release --dart-define=GOOGLE_MAPS_API_KEY=AIza...tu_clave
   ```

   Si el build se lanza desde Android Studio o CI, se puede usar la variable de
   entorno `GOOGLE_MAPS_API_KEY` en lugar de `local.properties`.

4. Recompilar el APK. La app detecta la clave sola:
   - Con clave: mapa de Google y recorrido real.
   - Sin clave: mapa alternativo y aviso, sin errores.

## Reglas que se cumplen

- La ruta **no** es una línea recta: se dibuja la polilínea de Google.
- El destino es siempre la ubicación guardada del **cliente**; la ubicación del
  teléfono solo indica dónde está el motorizado.
- La voz dice únicamente texto real de la ruta (indicación + distancia). Sin
  ruta, no habla.
- Si Google rechaza la solicitud (clave inválida, cuota agotada, sin ruta), se
  explica en español y se ofrece abrir Google Maps.
- Nada de claves en el APK más allá de lo que Google exige: la clave se inyecta
  en el manifiesto al compilar y se puede restringir por app.

## Verificación hecha

- `flutter analyze`: 0 errores, 0 advertencias.
- `flutter test`: 92 pruebas en verde, incluidas:
  - decodificación de una polilínea real de Google,
  - indicaciones en metros y kilómetros,
  - cálculo de la indicación más cercana,
  - comportamiento sin clave (no llama a Google y avisa),
  - reglas del cierre diario (solo entregado cuenta, gastos por medio de pago,
    diferencias declaradas).

**Pendiente de verificación en dispositivo:** el mapa de Google y la voz
necesitan una clave válida y un teléfono real; no se probaron aún en un
dispositivo.
