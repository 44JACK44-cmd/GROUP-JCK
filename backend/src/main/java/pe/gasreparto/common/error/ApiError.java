package pe.gasreparto.common.error;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.util.Map;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record ApiError(String codigo, String mensaje, Map<String, String> campos) {

    public ApiError(String codigo, String mensaje) {
        this(codigo, mensaje, null);
    }

    public String toJson() {
        return "{\"codigo\":\"" + escape(codigo) + "\",\"mensaje\":\"" + escape(mensaje) + "\"}";
    }

    private static String escape(String s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
