package pe.gasreparto.usuarios.api;

import pe.gasreparto.usuarios.domain.Usuario;

public record UsuarioResponse(Long id, String nombre, String usuario, String rol, boolean activo) {

    public static UsuarioResponse de(Usuario u) {
        return new UsuarioResponse(u.getId(), u.getNombre(), u.getUsuario(), u.getRol().getCodigo(), u.isActivo());
    }
}
