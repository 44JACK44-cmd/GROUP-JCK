package com.grupojck.gas.config;

import com.grupojck.gas.usuario.Rol;
import com.grupojck.gas.usuario.Usuario;
import com.grupojck.gas.usuario.UsuarioRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * Datos iniciales para desarrollo.
 * Credenciales: admin/admin123 (ADMINISTRADOR) · repartidor/demo123 (REPARTIDOR)
 */
@Component
public class DataSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DataSeeder.class);

    private final UsuarioRepository usuarioRepository;
    private final PasswordEncoder passwordEncoder;

    public DataSeeder(UsuarioRepository usuarioRepository, PasswordEncoder passwordEncoder) {
        this.usuarioRepository = usuarioRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public void run(ApplicationArguments args) {
        crearSiNoExiste("Administrador", "admin", "admin123", Rol.ADMINISTRADOR);
        crearSiNoExiste("Carlos Repartidor", "repartidor", "demo123", Rol.REPARTIDOR);
    }

    private void crearSiNoExiste(String nombre, String telefono, String password, Rol rol) {
        if (usuarioRepository.existsByTelefono(telefono)) return;
        Usuario u = new Usuario();
        u.setNombre(nombre);
        u.setTelefono(telefono);
        u.setPasswordHash(passwordEncoder.encode(password));
        u.setRol(rol);
        usuarioRepository.save(u);
        log.info("Usuario inicial creado: {} ({})", telefono, rol);
    }
}
