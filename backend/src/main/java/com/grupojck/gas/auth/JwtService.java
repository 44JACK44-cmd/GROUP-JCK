package com.grupojck.gas.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * JWT mínimo implementado con HMAC-SHA256 (sin dependencias externas).
 * Formato: base64url(header).base64url(payload).base64url(firma)
 */
@Service
public class JwtService {

    private static final String ALGORITHM = "HmacSHA256";

    private final byte[] secret;
    private final long expirationMillis;

    public JwtService(
            @Value("${app.jwt.secret}") String secret,
            @Value("${app.jwt.expiration-hours:12}") long expirationHours) {
        this.secret = secret.getBytes(StandardCharsets.UTF_8);
        this.expirationMillis = expirationHours * 3600_000L;
    }

    public String generateToken(Long usuarioId, String nombre, String rol) {
        Instant now = Instant.now();
        String header = encode("{\"alg\":\"HS256\",\"typ\":\"JWT\"}");
        String payload = encode("{"
                + "\"sub\":\"" + usuarioId + "\","
                + "\"nombre\":\"" + escapeJson(nombre) + "\","
                + "\"rol\":\"" + rol + "\","
                + "\"iat\":" + now.getEpochSecond() + ","
                + "\"exp\":" + now.plusMillis(expirationMillis).getEpochSecond()
                + "}");
        String signingInput = header + "." + payload;
        return signingInput + "." + sign(signingInput);
    }

    /** Devuelve los claims si el token es válido y no expiró; null en caso contrario. */
    public Map<String, Object> parseToken(String token) {
        try {
            String[] parts = token.split("\\.");
            if (parts.length != 3) return null;
            String expected = sign(parts[0] + "." + parts[1]);
            if (!constantTimeEquals(expected, parts[2])) return null;

            String payloadJson = new String(Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8);
            Long exp = extractLong(payloadJson, "exp");
            if (exp == null || Instant.now().getEpochSecond() >= exp) return null;

            Map<String, Object> claims = new LinkedHashMap<>();
            claims.put("sub", extractString(payloadJson, "sub"));
            claims.put("nombre", extractString(payloadJson, "nombre"));
            claims.put("rol", extractString(payloadJson, "rol"));
            claims.put("exp", exp);
            return claims;
        } catch (Exception e) {
            return null;
        }
    }

    private String sign(String data) {
        try {
            Mac mac = Mac.getInstance(ALGORITHM);
            mac.init(new SecretKeySpec(secret, ALGORITHM));
            return Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(mac.doFinal(data.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException("Error firmando JWT", e);
        }
    }

    private String encode(String json) {
        return Base64.getUrlEncoder().withoutPadding()
                .encodeToString(json.getBytes(StandardCharsets.UTF_8));
    }

    private String escapeJson(String value) {
        if (value == null) return "";
        return value.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }

    private String extractString(String json, String key) {
        Matcher m = Pattern.compile("\"" + key + "\":\"((?:[^\"\\\\]|\\\\.)*)\"").matcher(json);
        if (!m.find()) return null;
        return m.group(1)
                .replace("\\\"", "\"").replace("\\\\", "\\")
                .replace("\\n", "\n").replace("\\r", "\r").replace("\\t", "\t");
    }

    private Long extractLong(String json, String key) {
        Matcher m = Pattern.compile("\"" + key + "\":(\\d+)").matcher(json);
        return m.find() ? Long.parseLong(m.group(1)) : null;
    }

    private boolean constantTimeEquals(String a, String b) {
        return java.security.MessageDigest.isEqual(
                a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
    }
}
