package com.grupojck.gas.auth;

import com.grupojck.gas.usuario.Rol;
import com.grupojck.gas.usuario.Usuario;
import com.grupojck.gas.usuario.UsuarioRepository;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class AuthService {

    private final UsuarioRepository usuarioRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;

    public AuthService(UsuarioRepository usuarioRepository,
                       PasswordEncoder passwordEncoder,
                       JwtService jwtService) {
        this.usuarioRepository = usuarioRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
    }

    public LoginResponse login(LoginRequest request) {
        Usuario usuario = usuarioRepository.findByTelefono(request.telefono().trim())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Usuario o contraseña incorrectos"));

        if (!usuario.isActivo() || !passwordEncoder.matches(request.password(), usuario.getPasswordHash())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Usuario o contraseña incorrectos");
        }

        String token = jwtService.generateToken(usuario.getId(), usuario.getNombre(), usuario.getRol().name());
        return new LoginResponse(token, new UsuarioInfo(usuario.getId(), usuario.getNombre(), usuario.getTelefono(), usuario.getRol()));
    }

    public UsuarioInfo me(Long usuarioId) {
        Usuario usuario = usuarioRepository.findById(usuarioId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Sesión inválida"));
        return new UsuarioInfo(usuario.getId(), usuario.getNombre(), usuario.getTelefono(), usuario.getRol());
    }

    public record LoginRequest(String telefono, String password) { }

    public record LoginResponse(String token, UsuarioInfo usuario) { }

    public record UsuarioInfo(Long id, String nombre, String telefono, Rol rol) { }
}
