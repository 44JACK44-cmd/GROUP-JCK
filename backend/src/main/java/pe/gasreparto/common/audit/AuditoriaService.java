package pe.gasreparto.common.audit;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuditoriaService {

    private final AuditoriaRepository repository;

    public AuditoriaService(AuditoriaRepository repository) {
        this.repository = repository;
    }

    @Transactional(propagation = Propagation.MANDATORY)
    public void registrar(Long usuarioId, String accion, String entidad, Object entidadId) {
        repository.save(new Auditoria(usuarioId, accion, entidad,
                entidadId == null ? null : entidadId.toString(), null));
    }
}
