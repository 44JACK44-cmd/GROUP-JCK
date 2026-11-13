package pe.gasreparto.auth.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record LoginRequest(
        @NotBlank(message = "Escribe tu usuario") @Size(max = 60) String usuario,
        @NotBlank(message = "Escribe tu contraseña") @Size(max = 100) String password,
        @Size(max = 120) String dispositivo) {
}
