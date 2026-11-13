package pe.gasreparto.auth.domain;

import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import pe.gasreparto.auth.api.LoginRequest;
import pe.gasreparto.auth.api.SesionResponse;
import pe.gasreparto.auth.repository.SesionUsuarioRepository;
import pe.gasreparto.common.audit.AuditoriaService;
import pe.gasreparto.common.error.BusinessException;
import pe.gasreparto.common.error.Errores;
import pe.gasreparto.usuarios.domain.Usuario;
import pe.gasreparto.usuarios.repository.UsuarioRepository;

@Service
public class AuthService {

    public static final String CREDENCIALES_INVALIDAS = "CREDENCIALES_INVALIDAS";
    public static final String SESION_INVALIDA = "SESION_INVALIDA";

    private final UsuarioRepository usuarios;
    private final SesionUsuarioRepository sesiones;
    private final PasswordEncoder encoder;
    private final TokenService tokens;
    private final AuditoriaService auditoria;
    private final String hashFicticio;

    public AuthService(UsuarioRepository usuarios, SesionUsuarioRepository sesiones, PasswordEncoder encoder,
            TokenService tokens, AuditoriaService auditoria) {
        this.usuarios = usuarios;
        this.sesiones = sesiones;
        this.encoder = encoder;
        this.tokens = tokens;
        this.auditoria = auditoria;
        this.hashFicticio = encoder.encode("contrasena-ficticia-para-tiempo-constante");
    }

    @Transactional
    public SesionResponse login(LoginRequest req) {
        Usuario usuario = usuarios.findByUsuario(Usuario.normalizarUsuario(req.usuario())).orElse(null);
        boolean ok = encoder.matches(req.password(), usuario != null ? usuario.getPasswordHash() : hashFicticio);
        if (usuario == null || !ok || !usuario.isActivo()) {
            throw new BusinessException(HttpStatus.UNAUTHORIZED, CREDENCIALES_INVALIDAS,
                    "Usuario o contraseña incorrectos.");
        }
        auditoria.registrar(usuario.getId(), "INICIO_SESION", "usuario", usuario.getId());
        return abrirSesion(usuario, req.dispositivo());
    }

    /** Rota el refresh token. Si se reutiliza uno ya rotado, se cierran todas las sesiones del usuario. */
    @Transactional(noRollbackFor = BusinessException.class)
    public SesionResponse refrescar(String refreshToken, String dispositivo) {
        SesionUsuario sesion = sesiones.findByRefreshTokenHash(TokenService.hash(refreshToken))
                .orElseThrow(AuthService::sesionInvalida);
        if (sesion.estaRevocada()) {
            sesiones.findByUsuarioIdAndRevocadaEnIsNull(sesion.getUsuarioId()).forEach(SesionUsuario::revocar);
            auditoria.registrar(sesion.getUsuarioId(), "REUSO_TOKEN_REVOCADO", "sesion_usuario", sesion.getId());
            throw sesionInvalida();
        }
        Usuario usuario = usuarios.findById(sesion.getUsuarioId()).orElseThrow(AuthService::sesionInvalida);
        if (sesion.estaExpirada() || !usuario.isActivo()) {
            sesion.revocar();
            throw sesionInvalida();
        }
        sesion.revocar();
        return abrirSesion(usuario, dispositivo != null ? dispositivo : sesion.getDispositivo());
    }

    @Transactional
    public void cerrarSesion(String refreshToken) {
        sesiones.findByRefreshTokenHash(TokenService.hash(refreshToken)).ifPresent(s -> {
            s.revocar();
            auditoria.registrar(s.getUsuarioId(), "CIERRE_SESION", "sesion_usuario", s.getId());
        });
    }

    @Transactional(readOnly = true)
    public Usuario usuarioActivo(Long id) {
        return usuarios.findById(id).filter(Usuario::isActivo).orElseThrow(
                () -> new BusinessException(HttpStatus.UNAUTHORIZED, Errores.NO_AUTENTICADO,
                        Errores.noAutenticado().mensaje()));
    }

    private SesionResponse abrirSesion(Usuario usuario, String dispositivo) {
        String refresh = tokens.nuevoRefreshToken();
        sesiones.save(new SesionUsuario(usuario.getId(), TokenService.hash(refresh), recortar(dispositivo),
                tokens.expiracionRefresh()));
        return new SesionResponse(tokens.crearAccessToken(usuario), refresh, tokens.accessTokenSegundos(),
                SesionResponse.UsuarioSesion.de(usuario));
    }

    private static String recortar(String s) {
        return s == null ? null : s.length() > 120 ? s.substring(0, 120) : s;
    }

    private static BusinessException sesionInvalida() {
        return new BusinessException(HttpStatus.UNAUTHORIZED, SESION_INVALIDA, "Tu sesión terminó. Vuelve a ingresar.");
    }
}
