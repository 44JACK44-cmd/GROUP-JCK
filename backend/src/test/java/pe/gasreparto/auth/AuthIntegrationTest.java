package pe.gasreparto.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.support.TransactionTemplate;
import pe.gasreparto.TestcontainersConfiguration;
import pe.gasreparto.common.audit.AuditoriaRepository;
import pe.gasreparto.usuarios.domain.Rol;
import pe.gasreparto.usuarios.domain.Usuario;
import pe.gasreparto.usuarios.repository.RolRepository;
import pe.gasreparto.usuarios.repository.UsuarioRepository;
import org.springframework.security.crypto.password.PasswordEncoder;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration.class)
class AuthIntegrationTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    UsuarioRepository usuarios;
    @Autowired
    RolRepository roles;
    @Autowired
    PasswordEncoder encoder;
    @Autowired
    AuditoriaRepository auditoria;
    @Autowired
    TransactionTemplate tx;

    private String login(String usuario, String password) throws Exception {
        return mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"usuario\":\"" + usuario + "\",\"password\":\"" + password + "\"}"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
    }

    private String refresh(String token) {
        return "{\"refreshToken\":\"" + token + "\"}";
    }

    @Test
    void administradorIniciaSesionYRecibeTokensYRol() throws Exception {
        String body = login("  ADMIN ", "Admin2026!");
        assertThat((String) JsonPath.read(body, "$.accessToken")).isNotBlank();
        assertThat((String) JsonPath.read(body, "$.refreshToken")).isNotBlank();
        assertThat((String) JsonPath.read(body, "$.usuario.rol")).isEqualTo("ADMINISTRADOR");

        Integer id = JsonPath.read(body, "$.usuario.id");
        assertThat(auditoria.findByUsuarioIdAndAccion(id.longValue(), "INICIO_SESION")).isNotEmpty();
    }

    @Test
    void contrasenaIncorrectaDevuelveMensajeAmigable() throws Exception {
        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"usuario\":\"admin\",\"password\":\"mala\"}"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.codigo").value("CREDENCIALES_INVALIDAS"))
                .andExpect(jsonPath("$.mensaje").value("Usuario o contraseña incorrectos."));
    }

    @Test
    void datosVaciosDevuelvenErrorDeValidacionPorCampo() throws Exception {
        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.codigo").value("DATOS_INVALIDOS"))
                .andExpect(jsonPath("$.campos.usuario").value("Escribe tu usuario"));
    }

    @Test
    void endpointProtegidoSinTokenDevuelve401SinDetallesTecnicos() throws Exception {
        mvc.perform(get("/api/auth/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.codigo").value("NO_AUTENTICADO"))
                .andExpect(jsonPath("$.mensaje").value("Tu sesión terminó. Vuelve a ingresar."));
        mvc.perform(get("/api/auth/me").header("Authorization", "Bearer token-falso"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.codigo").value("NO_AUTENTICADO"));
    }

    @Test
    void permisosPorRol() throws Exception {
        String admin = JsonPath.read(login("admin", "Admin2026!"), "$.accessToken");
        String repartidor = JsonPath.read(login("carlos", "Reparto2026!"), "$.accessToken");

        mvc.perform(get("/api/usuarios").header("Authorization", "Bearer " + admin))
                .andExpect(status().isOk());
        mvc.perform(get("/api/usuarios").header("Authorization", "Bearer " + repartidor))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.codigo").value("SIN_PERMISO"));
        mvc.perform(get("/api/auth/me").header("Authorization", "Bearer " + repartidor))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rol").value("REPARTIDOR"));
    }

    @Test
    void refreshRotaElTokenYReusarUnoViejoCierraTodasLasSesiones() throws Exception {
        String r1 = JsonPath.read(login("carlos", "Reparto2026!"), "$.refreshToken");

        String body = mvc.perform(post("/api/auth/refresh").contentType(MediaType.APPLICATION_JSON)
                        .content(refresh(r1)))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        String r2 = JsonPath.read(body, "$.refreshToken");
        assertThat(r2).isNotEqualTo(r1);

        mvc.perform(post("/api/auth/refresh").contentType(MediaType.APPLICATION_JSON).content(refresh(r1)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.codigo").value("SESION_INVALIDA"));
        mvc.perform(post("/api/auth/refresh").contentType(MediaType.APPLICATION_JSON).content(refresh(r2)))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void logoutInvalidaElRefreshToken() throws Exception {
        String r = JsonPath.read(login("admin", "Admin2026!"), "$.refreshToken");
        mvc.perform(post("/api/auth/logout").contentType(MediaType.APPLICATION_JSON).content(refresh(r)))
                .andExpect(status().isNoContent());
        mvc.perform(post("/api/auth/refresh").contentType(MediaType.APPLICATION_JSON).content(refresh(r)))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void usuarioDesactivadoNoPuedeIngresarNiRefrescar() throws Exception {
        tx.executeWithoutResult(s -> {
            Rol rol = roles.findByCodigo("REPARTIDOR").orElseThrow();
            usuarios.save(new Usuario("Luis  Ramos ", "luis", encoder.encode("Reparto2026!"), rol));
        });
        String r = JsonPath.read(login("luis", "Reparto2026!"), "$.refreshToken");
        assertThat(usuarios.findByUsuario("luis").orElseThrow().getNombre()).isEqualTo("Luis Ramos");

        tx.executeWithoutResult(s -> usuarios.findByUsuario("luis").orElseThrow().desactivar());

        mvc.perform(post("/api/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"usuario\":\"luis\",\"password\":\"Reparto2026!\"}"))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/api/auth/refresh").contentType(MediaType.APPLICATION_JSON).content(refresh(r)))
                .andExpect(status().isUnauthorized());
    }
}
