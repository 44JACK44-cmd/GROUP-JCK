# Versiones

## v0.1.0 — Fase 1: esqueleto

- Backend Spring Boot (Java 21) con MySQL y migraciones Flyway.
- Login con usuario y contraseña, JWT de acceso (30 min) y refresh (7 días) con rotación.
- Roles ADMINISTRADOR y REPARTIDOR; rutas de administración protegidas.
- Auditoría de inicio/cierre de sesión. Errores siempre en lenguaje cotidiano.
- App Flutter: tema visual, login, sesión guardada de forma segura, navegación por rol
  (admin: Inicio, Pedidos, Clientes, Cobros, Más · repartidor: Entregas, Cobros, Más).
- Las secciones muestran estados vacíos; se completan en las fases siguientes.

## v0.0.1 — Fase 0: análisis

- Documento de análisis en `docs/fase-0-analisis.md`.
