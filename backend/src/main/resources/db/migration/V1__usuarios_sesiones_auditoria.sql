CREATE TABLE rol (
    id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    codigo  VARCHAR(30)  NOT NULL,
    nombre  VARCHAR(60)  NOT NULL,
    CONSTRAINT uk_rol_codigo UNIQUE (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE usuario (
    id             BIGINT AUTO_INCREMENT PRIMARY KEY,
    nombre         VARCHAR(120) NOT NULL,
    usuario        VARCHAR(60)  NOT NULL,
    password_hash  VARCHAR(100) NOT NULL,
    rol_id         BIGINT       NOT NULL,
    telefono       VARCHAR(20)  NULL,
    activo         BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     DATETIME(3)  NOT NULL,
    updated_at     DATETIME(3)  NOT NULL,
    version        BIGINT       NOT NULL DEFAULT 0,
    CONSTRAINT uk_usuario_usuario UNIQUE (usuario),
    CONSTRAINT fk_usuario_rol FOREIGN KEY (rol_id) REFERENCES rol (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE sesion_usuario (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    usuario_id          BIGINT       NOT NULL,
    refresh_token_hash  CHAR(64)     NOT NULL,
    dispositivo         VARCHAR(120) NULL,
    creada_en           DATETIME(3)  NOT NULL,
    expira_en           DATETIME(3)  NOT NULL,
    revocada_en         DATETIME(3)  NULL,
    CONSTRAINT uk_sesion_token UNIQUE (refresh_token_hash),
    CONSTRAINT fk_sesion_usuario FOREIGN KEY (usuario_id) REFERENCES usuario (id),
    INDEX ix_sesion_usuario (usuario_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE auditoria (
    id          BIGINT AUTO_INCREMENT PRIMARY KEY,
    usuario_id  BIGINT       NULL,
    accion      VARCHAR(60)  NOT NULL,
    entidad     VARCHAR(60)  NOT NULL,
    entidad_id  VARCHAR(36)  NULL,
    detalle     JSON         NULL,
    fecha       DATETIME(3)  NOT NULL,
    CONSTRAINT fk_auditoria_usuario FOREIGN KEY (usuario_id) REFERENCES usuario (id),
    INDEX ix_auditoria_entidad (entidad, entidad_id),
    INDEX ix_auditoria_fecha (fecha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO rol (codigo, nombre) VALUES
    ('ADMINISTRADOR', 'Administrador'),
    ('REPARTIDOR', 'Repartidor');
