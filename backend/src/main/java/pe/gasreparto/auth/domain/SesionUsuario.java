package pe.gasreparto.auth.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "sesion_usuario")
public class SesionUsuario {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "usuario_id", nullable = false)
    private Long usuarioId;

    @Column(name = "refresh_token_hash", nullable = false, length = 64)
    private String refreshTokenHash;

    @Column(length = 120)
    private String dispositivo;

    @Column(name = "creada_en", nullable = false)
    private Instant creadaEn;

    @Column(name = "expira_en", nullable = false)
    private Instant expiraEn;

    @Column(name = "revocada_en")
    private Instant revocadaEn;

    protected SesionUsuario() {
    }

    public SesionUsuario(Long usuarioId, String refreshTokenHash, String dispositivo, Instant expiraEn) {
        this.usuarioId = usuarioId;
        this.refreshTokenHash = refreshTokenHash;
        this.dispositivo = dispositivo;
        this.creadaEn = Instant.now();
        this.expiraEn = expiraEn;
    }

    public boolean estaRevocada() {
        return revocadaEn != null;
    }

    public boolean estaExpirada() {
        return Instant.now().isAfter(expiraEn);
    }

    public void revocar() {
        if (revocadaEn == null) {
            revocadaEn = Instant.now();
        }
    }

    public Long getId() {
        return id;
    }

    public Long getUsuarioId() {
        return usuarioId;
    }

    public String getDispositivo() {
        return dispositivo;
    }
}
