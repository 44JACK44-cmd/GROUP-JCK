package com.grupojck.gas.auth;

import com.grupojck.gas.auth.AuthService.LoginRequest;
import com.grupojck.gas.auth.AuthService.LoginResponse;
import com.grupojck.gas.auth.AuthService.UsuarioInfo;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/login")
    public ResponseEntity<LoginResponse> login(@Valid @RequestBody LoginRequest request) {
        return ResponseEntity.ok(authService.login(request));
    }

    @GetMapping("/me")
    public ResponseEntity<UsuarioInfo> me(@AuthenticationPrincipal UserDetails principal) {
        Long id = Long.valueOf(principal.getUsername());
        return ResponseEntity.ok(authService.me(id));
    }
}
