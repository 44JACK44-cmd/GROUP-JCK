package pe.gasreparto.auth.api;

import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import pe.gasreparto.auth.domain.AuthService;
import pe.gasreparto.common.security.UsuarioActual;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthService auth;

    public AuthController(AuthService auth) {
        this.auth = auth;
    }

    @PostMapping("/login")
    public SesionResponse login(@Valid @RequestBody LoginRequest req) {
        return auth.login(req);
    }

    @PostMapping("/refresh")
    public SesionResponse refresh(@Valid @RequestBody RefreshRequest req) {
        return auth.refrescar(req.refreshToken(), req.dispositivo());
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@Valid @RequestBody RefreshRequest req) {
        auth.cerrarSesion(req.refreshToken());
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/me")
    public SesionResponse.UsuarioSesion me() {
        return SesionResponse.UsuarioSesion.de(auth.usuarioActivo(UsuarioActual.id()));
    }
}
