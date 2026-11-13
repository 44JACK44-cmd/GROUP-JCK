package pe.gasreparto.common.audit;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AuditoriaRepository extends JpaRepository<Auditoria, Long> {

    List<Auditoria> findByUsuarioIdAndAccion(Long usuarioId, String accion);
}
