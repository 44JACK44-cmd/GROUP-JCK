package pe.gasreparto.common.error;

public final class Errores {

    public static final String DATOS_INVALIDOS = "DATOS_INVALIDOS";
    public static final String NO_AUTENTICADO = "NO_AUTENTICADO";
    public static final String SIN_PERMISO = "SIN_PERMISO";
    public static final String NO_ENCONTRADO = "NO_ENCONTRADO";
    public static final String ERROR_INTERNO = "ERROR_INTERNO";

    private Errores() {
    }

    public static ApiError noAutenticado() {
        return new ApiError(NO_AUTENTICADO, "Tu sesión terminó. Vuelve a ingresar.");
    }

    public static ApiError sinPermiso() {
        return new ApiError(SIN_PERMISO, "No tienes permiso para hacer esto.");
    }
}
