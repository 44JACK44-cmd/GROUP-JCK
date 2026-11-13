package pe.gasreparto.usuarios.domain;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import pe.gasreparto.common.security.BootstrapProperties;
import pe.gasreparto.common.security.Roles;
import pe.gasreparto.usuarios.repository.RolRepository;
import pe.gasreparto.usuarios.repository.UsuarioRepository;

/** Crea el administrador inicial (y un repartidor demo en desarrollo) cuando la base está vacía. */
@Component
public class UsuariosIniciales implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(UsuariosIniciales.class);

    private final UsuarioRepository usuarios;
    private final RolRepository roles;
    private final PasswordEncoder encoder;
    private final BootstrapProperties props;

    public UsuariosIniciales(UsuarioRepository usuarios, RolRepository roles, PasswordEncoder encoder,
            BootstrapProperties props) {
        this.usuarios = usuarios;
        this.roles = roles;
        this.encoder = encoder;
        this.props = props;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (usuarios.count() > 0) {
            return;
        }
        if (vacio(props.adminPassword())) {
            log.warn("No hay usuarios y ADMIN_PASSWORD no está definido: no se creó el administrador inicial");
            return;
        }
        crear("Administrador", props.adminUsuario(), props.adminPassword(), Roles.ADMINISTRADOR);
        if (!vacio(props.repartidorDemoUsuario()) && !vacio(props.repartidorDemoPassword())) {
            crear("Carlos", props.repartidorDemoUsuario(), props.repartidorDemoPassword(), Roles.REPARTIDOR);
        }
    }

    private void crear(String nombre, String usuario, String password, String rol) {
        Rol r = roles.findByCodigo(rol).orElseThrow();
        usuarios.save(new Usuario(nombre, usuario, encoder.encode(password), r));
        log.info("Usuario inicial creado: {} ({})", Usuario.normalizarUsuario(usuario), rol);
    }

    private static boolean vacio(String s) {
        return s == null || s.isBlank();
    }
}
