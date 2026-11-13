# GROUP-JCK

App Android (Flutter) + API (Spring Boot / Java 21 / MySQL) para gestión de pedidos y reparto de balones de gas.

- Análisis (Fase 0): [docs/fase-0-analisis.md](docs/fase-0-analisis.md)
- Versiones publicadas: [CHANGELOG.md](CHANGELOG.md)

## Estructura

```
backend/   API REST Spring Boot (Java 21, Spring Security + JWT, Flyway, MySQL)
app/       App móvil Flutter (Riverpod, go_router, Dio)
docs/      Documentación funcional y técnica
```

## Requisitos

- Java 21 y Maven 3.9+
- Flutter 3.x (stable) y Android SDK
- Docker (para MySQL local)

## Ejecutar en local

```bash
# 1. Base de datos
docker compose up -d

# 2. Backend (perfil dev: crea usuarios de prueba admin y carlos)
cd backend
SPRING_PROFILES_ACTIVE=dev mvn spring-boot:run

# 3. App (emulador Android: el backend se ve como 10.0.2.2)
cd app
flutter run
# Otro servidor:  flutter run --dart-define=API_URL=https://mi-servidor
```

Credenciales del perfil `dev` en `backend/src/main/resources/application-dev.yml` (solo desarrollo).
En cualquier otro entorno se deben definir `JWT_SECRET` (32+ caracteres), `ADMIN_PASSWORD`, `DB_URL`, `DB_USER` y `DB_PASSWORD`.

## Pruebas

```bash
cd backend && mvn test        # requiere Docker (Testcontainers con MySQL 8.4)
cd app && flutter analyze && flutter test
```

## Generar el APK

```bash
cd app
flutter build apk --debug                                   # contra backend local por HTTP
flutter build apk --release --dart-define=API_URL=https://mi-servidor
```

El APK queda en `app/build/app/outputs/flutter-apk/`.
