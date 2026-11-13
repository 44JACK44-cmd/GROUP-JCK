package pe.gasreparto.common.error;

import org.springframework.http.HttpStatus;

/**
 * Error esperado de negocio. El mensaje se muestra tal cual al usuario, por eso debe ser cotidiano.
 */
public class BusinessException extends RuntimeException {

    private final HttpStatus status;
    private final String codigo;

    public BusinessException(HttpStatus status, String codigo, String mensaje) {
        super(mensaje);
        this.status = status;
        this.codigo = codigo;
    }

    public HttpStatus getStatus() {
        return status;
    }

    public String getCodigo() {
        return codigo;
    }
}
