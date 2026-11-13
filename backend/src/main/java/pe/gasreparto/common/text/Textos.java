package pe.gasreparto.common.text;

public final class Textos {

    private Textos() {
    }

    /** Quita espacios al inicio/fin y reduce espacios repetidos a uno. */
    public static String limpiar(String texto) {
        if (texto == null) {
            return null;
        }
        String limpio = texto.strip().replaceAll("\\s+", " ");
        return limpio.isEmpty() ? null : limpio;
    }
}
