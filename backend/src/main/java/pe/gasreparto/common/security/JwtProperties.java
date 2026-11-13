package pe.gasreparto.common.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties("app.jwt")
public record JwtProperties(String secret, long accessTokenMinutos, long refreshTokenDias) {
}
