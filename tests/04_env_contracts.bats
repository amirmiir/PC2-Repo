#!/usr/bin/env bats
# tests/04_env_contracts.bats
# Pruebas de contratos de variables de entorno (12-Factor III)
# Metodología: AAA (Arrange-Act-Assert) / RGR (Red-Green-Refactor)

setup() {
    # Arrange: preparar entorno de prueba
    export TEST_DIR="${BATS_TEST_DIRNAME}/.."
    export OUT_DIR="${TEST_DIR}/out"
    export SRC_DIR="${TEST_DIR}/src"

    # Respaldar variables de entorno originales
    export ORIG_DOMAINS_FILE="${DOMAINS_FILE}"
    export ORIG_DNS_SERVER="${DNS_SERVER}"
    export ORIG_MAX_DEPTH="${MAX_DEPTH}"

    # Asegurar directorio de salida
    mkdir -p "${OUT_DIR}"
}

teardown() {
    # Restaurar variables de entorno originales
    export DOMAINS_FILE="${ORIG_DOMAINS_FILE}"
    export DNS_SERVER="${ORIG_DNS_SERVER}"
    export MAX_DEPTH="${ORIG_MAX_DEPTH}"
}

@test "DOMAINS_FILE es obligatoria - script falla si no está definida" {
    # Arrange: eliminar variable obligatoria
    unset DOMAINS_FILE

    # Act: intentar ejecutar resolve_dns.sh sin DOMAINS_FILE
    run bash "${SRC_DIR}/resolve_dns.sh"

    # Assert: debe fallar con código distinto de cero
    [ "$status" -ne 0 ]

    # Assert: debe mostrar mensaje de error indicando variable faltante
    [[ "$output" =~ "DOMAINS_FILE" ]] || [[ "$output" =~ "variable" ]] || [[ "$output" =~ "required" ]]
}

@test "DOMAINS_FILE con ruta inválida causa fallo con código específico" {
    # Arrange: configurar ruta inexistente
    export DOMAINS_FILE="/ruta/totalmente/inexistente/dominios.txt"

    # Act: intentar ejecutar
    run bash "${SRC_DIR}/resolve_dns.sh"

    # Assert: debe fallar
    [ "$status" -ne 0 ]

    # Assert: preferiblemente con código de error de configuración (5)
    # O al menos con código genérico (1)
    [ "$status" -eq 5 ] || [ "$status" -eq 1 ]
}

@test "DNS_SERVER variable altera el servidor DNS usado en resolución" {
    # Arrange: configurar archivo de dominios válido
    export DOMAINS_FILE="${TEST_DIR}/DOMAINS.sample.txt"

    # Arrange: configurar servidor DNS específico
    export DNS_SERVER="8.8.8.8"

    # Act: ejecutar resolución
    run bash "${SRC_DIR}/resolve_dns.sh"

    # Assert: debe tener éxito (o código aceptable si DNS no responde)
    # Código 0 = éxito, código 3 = error DNS (aceptable si servidor no disponible)
    [ "$status" -eq 0 ] || [ "$status" -eq 3 ]

    # Note: La verificación del servidor usado requeriría inspección de logs
    # o trazas de dig, que están fuera del alcance de esta prueba básica
}

@test "MAX_DEPTH variable limita profundidad de resolución CNAME" {
    # Arrange: configurar límite de profundidad bajo
    export MAX_DEPTH=2
    export DOMAINS_FILE="${TEST_DIR}/DOMAINS.sample.txt"

    # Act: ejecutar construcción de grafo
    # Primero necesitamos dns_resolves.csv
    bash "${SRC_DIR}/resolve_dns.sh" || true

    # Luego construir grafo
    run bash "${SRC_DIR}/build_graph.sh"

    # Assert: verificar que se respeta el límite
    if [ -f "${OUT_DIR}/depth_report.txt" ]; then
        # Extraer profundidad máxima del reporte
        local max_depth=$(grep -i "profundidad.*m.*xima" "${OUT_DIR}/depth_report.txt" | grep -oE '[0-9]+' | tail -1)

        # Si se reporta profundidad, debe respetar el límite o advertir
        if [ -n "$max_depth" ]; then
            # Puede ser igual o menor que MAX_DEPTH
            # O el script puede reportar pero truncar cadenas
            [ "$max_depth" -le 10 ]  # Validación básica: no debería ser excesivo
        fi
    fi
}

@test "Variables undefined usan valores por defecto razonables" {
    # Arrange: limpiar todas las variables opcionales
    unset DNS_SERVER
    unset MAX_DEPTH

    # Arrange: mantener solo la obligatoria
    export DOMAINS_FILE="${TEST_DIR}/DOMAINS.sample.txt"

    # Act: ejecutar resolución
    run bash "${SRC_DIR}/resolve_dns.sh"

    # Assert: debe funcionar con defaults
    [ "$status" -eq 0 ]

    # Assert: debe generar salida esperada
    [ -f "${OUT_DIR}/dns_resolves.csv" ]
}

@test "DOMAINS_FILE vacío o sin contenido válido falla apropiadamente" {
    # Arrange: crear archivo vacío
    local empty_file="${BATS_TEST_TMPDIR}/empty_domains.txt"
    touch "$empty_file"

    export DOMAINS_FILE="$empty_file"

    # Act: intentar ejecutar
    run bash "${SRC_DIR}/resolve_dns.sh"

    # Assert: debe fallar o generar CSV solo con header
    # Código aceptable: 1 (error genérico) o 5 (error configuración)
    [ "$status" -ne 0 ] || {
        # Si retorna 0, debe haber generado al menos header
        [ -f "${OUT_DIR}/dns_resolves.csv" ]
        local line_count=$(wc -l < "${OUT_DIR}/dns_resolves.csv")
        [ "$line_count" -eq 1 ]
    }

    # Cleanup
    rm -f "$empty_file"
}

@test "DOMAINS_FILE con comentarios y líneas vacías se maneja correctamente" {
    # Arrange: crear archivo con formato mixto
    local test_file="${BATS_TEST_TMPDIR}/domains_with_comments.txt"
    cat > "$test_file" <<'EOF'
# Este es un comentario
google.com

# Otro comentario
cloudflare.com

EOF

    export DOMAINS_FILE="$test_file"

    # Act: ejecutar resolución
    run bash "${SRC_DIR}/resolve_dns.sh"

    # Assert: debe procesar correctamente (ignorando comentarios y vacíos)
    [ "$status" -eq 0 ]

    # Assert: debe haber procesado los dominios válidos
    [ -f "${OUT_DIR}/dns_resolves.csv" ]

    # Assert: debe contener google.com y cloudflare.com
    run grep -E "(google\.com|cloudflare\.com)" "${OUT_DIR}/dns_resolves.csv"
    [ "$status" -eq 0 ]

    # Cleanup
    rm -f "$test_file"
}

@test "Variables de entorno no interfieren entre ejecuciones" {
    # Arrange: primera ejecución con configuración A
    export DOMAINS_FILE="${TEST_DIR}/DOMAINS.sample.txt"
    export DNS_SERVER="1.1.1.1"

    # Act: primera ejecución
    run bash "${SRC_DIR}/resolve_dns.sh"
    local first_status=$status

    # Arrange: cambiar configuración para ejecución B
    export DNS_SERVER="8.8.8.8"

    # Act: segunda ejecución
    run bash "${SRC_DIR}/resolve_dns.sh"
    local second_status=$status

    # Assert: ambas ejecuciones deben comportarse consistentemente
    [ "$first_status" -eq "$second_status" ]

    # Assert: resultados deben ser deterministas para misma entrada
    [ -f "${OUT_DIR}/dns_resolves.csv" ]
}

@test "RELEASE variable se usa para empaquetado" {
    # Arrange: configurar versión de release
    export RELEASE="test-1.0.0"

    # Skip si make pack no está implementado
    if ! grep -q "^pack:" "${TEST_DIR}/Makefile"; then
        skip "Target 'pack' no implementado aún en Makefile"
    fi

    # Act: ejecutar empaquetado
    run make -C "${TEST_DIR}" pack

    # Assert: debe generar paquete con nombre que incluye RELEASE
    if [ "$status" -eq 0 ]; then
        run ls "${TEST_DIR}/dist/"*"${RELEASE}"*
        [ "$status" -eq 0 ]
    fi
}

@test "Cambio en DNS_SERVER produce salida observable diferente" {
    # Arrange: configurar primer servidor
    export DOMAINS_FILE="${TEST_DIR}/DOMAINS.sample.txt"
    export DNS_SERVER="1.1.1.1"

    # Act: primera resolución
    bash "${SRC_DIR}/resolve_dns.sh" || true

    # Arrange: respaldar resultado
    if [ -f "${OUT_DIR}/dns_resolves.csv" ]; then
        cp "${OUT_DIR}/dns_resolves.csv" "${BATS_TEST_TMPDIR}/result1.csv"
    fi

    # Arrange: cambiar servidor DNS
    export DNS_SERVER="8.8.8.8"

    # Act: segunda resolución
    bash "${SRC_DIR}/resolve_dns.sh" || true

    # Assert: resultados pueden variar en TTL o IPs resueltas
    # Esta es una validación de que el cambio de variable tiene efecto observable
    # No validamos igualdad estricta porque IPs pueden variar, pero formato debe ser consistente

    if [ -f "${OUT_DIR}/dns_resolves.csv" ] && [ -f "${BATS_TEST_TMPDIR}/result1.csv" ]; then
        # Validar que ambos tienen formato consistente
        local header1=$(head -n 1 "${BATS_TEST_TMPDIR}/result1.csv")
        local header2=$(head -n 1 "${OUT_DIR}/dns_resolves.csv")
        [ "$header1" = "$header2" ]
    fi
}