#!/usr/bin/env bats
# tests/01_resolve_basic.bats
# Pruebas básicas de resolución DNS A/CNAME
# Metodología: AAA (Arrange-Act-Assert) / RGR (Red-Green-Refactor)

setup() {
    # Arrange: preparar entorno de prueba
    export TEST_DIR="${BATS_TEST_DIRNAME}/.."
    export OUT_DIR="${TEST_DIR}/out"
    export TEST_DOMAINS_FILE="${BATS_TEST_TMPDIR}/test_domains.txt"

    # Crear archivo de prueba con dominios comunes
    cat > "${TEST_DOMAINS_FILE}" <<EOF
google.com
www.github.com
cloudflare.com
EOF
}

teardown() {
    # Limpiar recursos de prueba
    rm -f "${TEST_DOMAINS_FILE}"
}

@test "resolve_dns.sh genera archivo CSV con formato correcto" {
    # Arrange: verificar que existe el script
    [ -f "${TEST_DIR}/src/resolve_dns.sh" ]

    # Act: ejecutar resolución DNS
    export DOMAINS_FILE="${TEST_DOMAINS_FILE}"
    run bash "${TEST_DIR}/src/resolve_dns.sh"

    # Assert: verificar código de salida exitoso
    [ "$status" -eq 0 ]

    # Assert: verificar que se generó el archivo de salida
    [ -f "${OUT_DIR}/dns_resolves.csv" ]

    # Assert: verificar cabecera del CSV
    header=$(head -n 1 "${OUT_DIR}/dns_resolves.csv")
    [ "$header" = "source,record_type,target,ttl,trace_ts" ]
}

@test "resolve_dns.sh contiene al menos una resolución válida" {
    # Arrange: configurar variables de entorno
    export DOMAINS_FILE="${TEST_DOMAINS_FILE}"

    # Act: ejecutar script
    run bash "${TEST_DIR}/src/resolve_dns.sh"

    # Assert: debe haber más de una línea (cabecera + datos)
    line_count=$(wc -l < "${OUT_DIR}/dns_resolves.csv")
    [ "$line_count" -gt 1 ]

    # Assert: verificar que hay registros con tipo A o CNAME
    run grep -E ",(A|CNAME)," "${OUT_DIR}/dns_resolves.csv"
    [ "$status" -eq 0 ]
}

@test "resolve_dns.sh valida columnas del CSV correctamente" {
    # Arrange: preparar entorno
    export DOMAINS_FILE="${TEST_DOMAINS_FILE}"

    # Act: ejecutar resolución
    bash "${TEST_DIR}/src/resolve_dns.sh"

    # Assert: verificar que cada línea tiene 5 columnas
    # Saltar la cabecera (NR>1) y verificar formato
    run awk -F',' 'NR>1 && NF!=5 {exit 1}' "${OUT_DIR}/dns_resolves.csv"
    [ "$status" -eq 0 ]

    # Assert: verificar que TTL es numérico
    run awk -F',' 'NR>1 && $4 !~ /^[0-9]+$/ {exit 1}' "${OUT_DIR}/dns_resolves.csv"
    [ "$status" -eq 0 ]
}

@test "resolve_dns.sh falla cuando DOMAINS_FILE no existe" {
    # Arrange: configurar ruta inválida
    export DOMAINS_FILE="/ruta/inexistente/dominios.txt"

    # Act: intentar ejecutar script
    run bash "${TEST_DIR}/src/resolve_dns.sh"

    # Assert: debe fallar con código distinto de cero
    [ "$status" -ne 0 ]
}

@test "resolve_dns.sh falla cuando DOMAINS_FILE no está definido" {
    # Arrange: limpiar variable de entorno
    unset DOMAINS_FILE

    # Act: intentar ejecutar script sin variable
    run bash "${TEST_DIR}/src/resolve_dns.sh"

    # Assert: debe fallar con código distinto de cero
    [ "$status" -ne 0 ]
}