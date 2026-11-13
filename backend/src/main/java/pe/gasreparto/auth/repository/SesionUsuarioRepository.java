package pe.gasreparto.auth.repository;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import pe.gasreparto.auth.domain.SesionUsuario;

public interface SesionUsuarioRepository extends JpaRepository<SesionUsuario, Long> {

    Optional<SesionUsuario> findByRefreshTokenHash(String refreshTokenHash);

    List<SesionUsuario> findByUsuarioIdAndRevocadaEnIsNull(Long usuarioId);
}
