package pe.gasreparto.common.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("app.bootstrap")
public record BootstrapProperties(
        String adminUsuario,
        String adminPassword,
        String repartidorDemoUsuario,
        String repartidorDemoPassword) {
}
