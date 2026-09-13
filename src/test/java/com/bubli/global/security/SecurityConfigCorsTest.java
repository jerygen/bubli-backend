package com.bubli.global.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.cors.CorsConfiguration;

import static org.assertj.core.api.Assertions.assertThat;

public class SecurityConfigCorsTest {

    @Test
    void corsAllowsTauriReleaseOrigins() {
        SecurityConfig securityConfig = new SecurityConfig(null, new ObjectMapper(), null);
        ReflectionTestUtils.setField(
                securityConfig,
                "allowedOriginPatterns",
                "https://my-bubli.kro.kr,tauri://localhost,http://tauri.localhost,http://localhost:3000"
        );

        for (String origin : new String[] { "tauri://localhost", "http://tauri.localhost" }) {
            MockHttpServletRequest request = new MockHttpServletRequest("OPTIONS", "/api/me");
            request.addHeader("Origin", origin);

            CorsConfiguration corsConfiguration = securityConfig.corsConfigurationSource().getCorsConfiguration(request);

            assertThat(corsConfiguration).isNotNull();
            assertThat(corsConfiguration.getAllowedOriginPatterns()).contains(origin);
            assertThat(corsConfiguration.checkOrigin(origin)).isEqualTo(origin);
            assertThat(corsConfiguration.getAllowCredentials()).isTrue();
            assertThat(corsConfiguration.getAllowedMethods()).contains("OPTIONS", "GET", "POST");
        }
    }
}
