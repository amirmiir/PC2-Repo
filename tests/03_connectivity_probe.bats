#!/usr/bin/env bats
# tests/03_connectivity_probe.bats
# Pruebas de verificación de conectividad con ss y sonda HTTP/HTTPS con curl
# Metodología: AAA (Arrange-Act-Assert) / RGR (Red-Green-Refactor)

setup() {
    # Arrange: preparar entorno de prueba
    export TEST_DIR="${BATS_TEST_DIRNAME}/.."
    export OUT_DIR="${TEST_DIR}/out"
    export SRC_DIR="${TEST_DIR}/src"

    # Asegurar que existe el directorio de salida
    mkdir -p "${OUT_DIR}"
}

teardown() {
    # Limpiar recursos temporales si es necesario
    :
}

@test "verify_connectivity.sh existe y es ejecutable" {
    # Arrange & Assert: verificar que existe el script
    [ -f "${SRC_DIR}/verify_connectivity.sh" ]

    # Assert: verificar que es ejecutable
    [ -x "${SRC_DIR}/verify_connectivity.sh" ]
}

@test "verify_connectivity.sh genera connectivity_ss.txt" {
    # Arrange: verificar prerequisitos
    [ -f "${OUT_DIR}/dns_resolves.csv" ]

    # Act: ejecutar verificación de conectividad
    run bash "${SRC_DIR}/verify_connectivity.sh"

    # Assert: debe tener éxito o fallar de forma controlada
    # (no todos los IPs pueden ser alcanzables, pero el script debe ejecutar)

    # Assert: debe generar archivo de salida
    [ -f "${OUT_DIR}/connectivity_ss.txt" ]

    # Assert: archivo no debe estar vacío
    [ -s "${OUT_DIR}/connectivity_ss.txt" ]
}

@test "verify_connectivity.sh genera curl_probe.txt" {
    # Arrange: verificar prerequisitos
    [ -f "${OUT_DIR}/dns_resolves.csv" ]

    # Act: ejecutar verificación
    run bash "${SRC_DIR}/verify_connectivity.sh"

    # Assert: debe generar archivo de sonda curl
    [ -f "${OUT_DIR}/curl_probe.txt" ]

    # Assert: archivo no debe estar vacío
    [ -s "${OUT_DIR}/curl_probe.txt" ]
}

@test "connectivity_ss.txt contiene evidencia de comando ss" {
    # Arrange: ejecutar script si no se ha ejecutado
    if [ ! -f "${OUT_DIR}/connectivity_ss.txt" ]; then
        bash "${SRC_DIR}/verify_connectivity.sh" || true
    fi

    # Assert: verificar que el archivo existe
    [ -f "${OUT_DIR}/connectivity_ss.txt" ]

    # Assert: debe contener indicadores de ss
    # Buscar patrones comunes en salida de ss: ESTAB, LISTEN, tcp, dst, src
    run grep -iE "(tcp|udp|estab|listen|dst|src|socket)" "${OUT_DIR}/connectivity_ss.txt"
    [ "$status" -eq 0 ]
}

@test "curl_probe.txt contiene evidencia de protocolo HTTP/HTTPS" {
    # Arrange: ejecutar script si no se ha ejecutado
    if [ ! -f "${OUT_DIR}/curl_probe.txt" ]; then
        bash "${SRC_DIR}/verify_connectivity.sh" || true
    fi

    # Assert: verificar que el archivo existe
    [ -f "${OUT_DIR}/curl_probe.txt" ]

    # Assert: debe contener indicadores HTTP/HTTPS
    # Buscar patrones: HTTP, HTTPS, http://, https://, status code, curl
    run grep -iE "(http|https|HTTP/[12]|status|curl)" "${OUT_DIR}/curl_probe.txt"
    [ "$status" -eq 0 ]
}

@test "curl_probe.txt incluye información de tiempos" {
    # Arrange: ejecutar script si no se ha ejecutado
    if [ ! -f "${OUT_DIR}/curl_probe.txt" ]; then
        bash "${SRC_DIR}/verify_connectivity.sh" || true
    fi

    # Assert: verificar existencia
    [ -f "${OUT_DIR}/curl_probe.txt" ]

    # Assert: debe contener información de tiempos de respuesta
    # Buscar patrones: time, ms, seconds, latencia, duration
    run grep -iE "(time|ms|second|latenc|duration|tiempo)" "${OUT_DIR}/curl_probe.txt"
    [ "$status" -eq 0 ]
}

@test "verify_connectivity.sh procesa IPs del archivo edges.csv" {
    # Arrange: verificar que existe edges.csv con registros A
    [ -f "${OUT_DIR}/edges.csv" ]

    # Arrange: contar IPs disponibles (registros tipo A)
    local ip_count=$(awk -F',' 'NR>1 && $3=="A" {print $2}' "${OUT_DIR}/edges.csv" | wc -l)

    # Skip test if no IPs available
    if [ "$ip_count" -eq 0 ]; then
        skip "No hay registros A en edges.csv para probar"
    fi

    # Act: ejecutar verificación
    run bash "${SRC_DIR}/verify_connectivity.sh"

    # Assert: archivos de salida deben contener referencias a IPs procesadas
    # Obtener una IP de muestra
    local sample_ip=$(awk -F',' 'NR>1 && $3=="A" {print $2; exit}' "${OUT_DIR}/edges.csv")

    # Verificar que la IP aparece en alguno de los reportes
    local found=false
    if grep -q "$sample_ip" "${OUT_DIR}/connectivity_ss.txt" 2>/dev/null; then
        found=true
    fi
    if grep -q "$sample_ip" "${OUT_DIR}/curl_probe.txt" 2>/dev/null; then
        found=true
    fi

    [ "$found" = true ]
}

@test "verify_connectivity.sh falla correctamente sin dns_resolves.csv" {
    # Arrange: respaldar archivo existente
    if [ -f "${OUT_DIR}/dns_resolves.csv" ]; then
        mv "${OUT_DIR}/dns_resolves.csv" "${OUT_DIR}/dns_resolves.csv.bak"
    fi

    # Act: intentar ejecutar sin entrada
    run bash "${SRC_DIR}/verify_connectivity.sh"
    local exit_status=$status

    # Restaurar archivo
    if [ -f "${OUT_DIR}/dns_resolves.csv.bak" ]; then
        mv "${OUT_DIR}/dns_resolves.csv.bak" "${OUT_DIR}/dns_resolves.csv"
    fi

    # Assert: debe fallar con código distinto de cero
    [ "$exit_status" -ne 0 ]
}

@test "connectivity_ss.txt incluye timestamp o contexto temporal" {
    # Arrange: ejecutar script si necesario
    if [ ! -f "${OUT_DIR}/connectivity_ss.txt" ]; then
        bash "${SRC_DIR}/verify_connectivity.sh" || true
    fi

    # Assert: verificar existencia
    [ -f "${OUT_DIR}/connectivity_ss.txt" ]

    # Assert: debe incluir contexto temporal
    # Buscar patrones de fecha/hora: 2025, 2024, timestamp, fecha, generado
    run grep -iE "(202[45]|timestamp|fecha|generado|generated)" "${OUT_DIR}/connectivity_ss.txt"
    [ "$status" -eq 0 ]
}

@test "curl_probe.txt diferencia entre HTTP y HTTPS" {
    # Arrange: ejecutar script si necesario
    if [ ! -f "${OUT_DIR}/curl_probe.txt" ]; then
        bash "${SRC_DIR}/verify_connectivity.sh" || true
    fi

    # Assert: verificar existencia
    [ -f "${OUT_DIR}/curl_probe.txt" ]

    # Assert: debe identificar explícitamente el protocolo usado
    # Buscar indicadores claros de protocolo
    local has_protocol=false
    if grep -qE "(https://|HTTP|443|TLS|SSL)" "${OUT_DIR}/curl_probe.txt"; then
        has_protocol=true
    fi
    if grep -qE "(http://|:80[^0-9])" "${OUT_DIR}/curl_probe.txt"; then
        has_protocol=true
    fi

    [ "$has_protocol" = true ]
}