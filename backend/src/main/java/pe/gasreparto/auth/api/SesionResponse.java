package pe.gasreparto.auth.api;

import pe.gasreparto.usuarios.domain.Usuario;

public record SesionResponse(String accessToken, String refreshToken, long expiraEnSegundos, UsuarioSesion usuario) {

    public record UsuarioSesion(Long id, String nombre, String usuario, String rol) {

        public static UsuarioSesion de(Usuario u) {
            return new UsuarioSesion(u.getId(), u.getNombre(), u.getUsuario(), u.getRol().getCodigo());
        }
    }
}
