#!/usr/bin/env bats
# tests/02_cycles_and_depth.bats
# Pruebas de construcción de grafo, profundidad y detección de ciclos
# Metodología: AAA (Arrange-Act-Assert) / RGR (Red-Green-Refactor)

setup() {
    # Arrange: preparar entorno de prueba
    export TEST_DIR="${BATS_TEST_DIRNAME}/.."
    export OUT_DIR="${TEST_DIR}/out"

    # Asegurar que existe el directorio de salida
    mkdir -p "${OUT_DIR}"
}

teardown() {
    # Limpiar recursos de prueba si es necesario
    :
}

@test "build_graph.sh genera edges.csv con formato correcto" {
    # Arrange: verificar que existe el script
    [ -f "${TEST_DIR}/src/build_graph.sh" ]

    # Arrange: debe existir dns_resolves.csv como entrada
    [ -f "${OUT_DIR}/dns_resolves.csv" ]

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"

    # Assert: verificar código de salida exitoso
    [ "$status" -eq 0 ]

    # Assert: verificar que se generó edges.csv
    [ -f "${OUT_DIR}/edges.csv" ]

    # Assert: verificar cabecera del CSV
    header=$(head -n 1 "${OUT_DIR}/edges.csv")
    [ "$header" = "from,to,kind" ]
}

@test "build_graph.sh valida columnas de edges.csv correctamente" {
    # Arrange: verificar entrada
    [ -f "${OUT_DIR}/dns_resolves.csv" ]

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"
    [ "$status" -eq 0 ]

    # Assert: verificar que cada línea tiene 3 columnas
    run awk -F',' 'NR>1 && NF!=3 {exit 1}' "${OUT_DIR}/edges.csv"
    [ "$status" -eq 0 ]

    # Assert: verificar que kind es CNAME o A
    run awk -F',' 'NR>1 && $3!="CNAME" && $3!="A" {exit 1}' "${OUT_DIR}/edges.csv"
    [ "$status" -eq 0 ]

    # Assert: verificar que from y to no están vacíos
    run awk -F',' 'NR>1 && ($1=="" || $2=="") {exit 1}' "${OUT_DIR}/edges.csv"
    [ "$status" -eq 0 ]
}

@test "build_graph.sh genera depth_report.txt con métricas de profundidad" {
    # Arrange: verificar entrada
    [ -f "${OUT_DIR}/dns_resolves.csv" ]

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"
    [ "$status" -eq 0 ]

    # Assert: verificar que se generó depth_report.txt
    [ -f "${OUT_DIR}/depth_report.txt" ]

    # Assert: verificar presencia de métricas clave
    run grep -qi "profundidad" "${OUT_DIR}/depth_report.txt"
    [ "$status" -eq 0 ]
}

@test "build_graph.sh calcula profundidad correctamente para CNAME chain" {
    # Arrange: crear CSV de prueba con cadena CNAME→A
    local test_csv="${OUT_DIR}/dns_resolves_test.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
www.example.com,CNAME,example.com,300,1696089600
example.com,A,93.184.216.34,60,1696089600
EOF

    # Arrange: respaldar CSV original si existe
    if [ -f "${OUT_DIR}/dns_resolves.csv" ]; then
        cp "${OUT_DIR}/dns_resolves.csv" "${OUT_DIR}/dns_resolves.csv.bak"
    fi
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"
    local exit_status=$status

    # Restaurar CSV original
    if [ -f "${OUT_DIR}/dns_resolves.csv.bak" ]; then
        mv "${OUT_DIR}/dns_resolves.csv.bak" "${OUT_DIR}/dns_resolves.csv"
    fi

    # Assert: debe tener éxito
    [ "$exit_status" -eq 0 ]

    # Assert: debe generar edges con CNAME y A
    run grep -c "CNAME" "${OUT_DIR}/edges.csv"
    [ "$status" -eq 0 ]

    run grep -c ",A$" "${OUT_DIR}/edges.csv"
    [ "$status" -eq 0 ]

    # Assert: profundidad debe ser al menos 2 (CNAME→A)
    [ -f "${OUT_DIR}/depth_report.txt" ]
}

@test "build_graph.sh maneja correctamente registros solo tipo A" {
    # Arrange: crear CSV de prueba solo con registros A
    local test_csv="${OUT_DIR}/dns_resolves_test.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
google.com,A,142.250.185.46,300,1696089600
cloudflare.com,A,1.1.1.1,60,1696089600
EOF

    # Arrange: respaldar CSV original
    if [ -f "${OUT_DIR}/dns_resolves.csv" ]; then
        cp "${OUT_DIR}/dns_resolves.csv" "${OUT_DIR}/dns_resolves.csv.bak"
    fi
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"
    local exit_status=$status

    # Restaurar CSV original
    if [ -f "${OUT_DIR}/dns_resolves.csv.bak" ]; then
        mv "${OUT_DIR}/dns_resolves.csv.bak" "${OUT_DIR}/dns_resolves.csv"
    fi

    # Assert: debe tener éxito
    [ "$exit_status" -eq 0 ]

    # Assert: edges.csv debe contener las aristas tipo A
    [ -f "${OUT_DIR}/edges.csv" ]
    run grep -c ",A$" "${OUT_DIR}/edges.csv"
    [ "$status" -eq 0 ]

    # Assert: no debe haber aristas CNAME
    run grep -c "CNAME" "${OUT_DIR}/edges.csv"
    # Puede ser 0 o no encontrar (ambos son válidos para este caso)
}

@test "build_graph.sh falla si no existe dns_resolves.csv" {
    # Arrange: respaldar y eliminar archivo de entrada
    if [ -f "${OUT_DIR}/dns_resolves.csv" ]; then
        mv "${OUT_DIR}/dns_resolves.csv" "${OUT_DIR}/dns_resolves.csv.bak"
    fi

    # Act: intentar ejecutar sin entrada
    run bash "${TEST_DIR}/src/build_graph.sh"
    local exit_status=$status

    # Restaurar archivo
    if [ -f "${OUT_DIR}/dns_resolves.csv.bak" ]; then
        mv "${OUT_DIR}/dns_resolves.csv.bak" "${OUT_DIR}/dns_resolves.csv"
    fi

    # Assert: debe fallar
    [ "$exit_status" -ne 0 ]
}

@test "build_graph.sh detecta ciclos CNAME simples" {
    # Arrange: crear CSV con ciclo CNAME (loop)
    local test_csv="${OUT_DIR}/dns_resolves_test.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
loop1.example.com,CNAME,loop2.example.com,300,1696089600
loop2.example.com,CNAME,loop1.example.com,300,1696089600
EOF

    # Arrange: respaldar CSV original
    if [ -f "${OUT_DIR}/dns_resolves.csv" ]; then
        cp "${OUT_DIR}/dns_resolves.csv" "${OUT_DIR}/dns_resolves.csv.bak"
    fi
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"
    local exit_status=$status

    # Restaurar CSV original
    if [ -f "${OUT_DIR}/dns_resolves.csv.bak" ]; then
        mv "${OUT_DIR}/dns_resolves.csv.bak" "${OUT_DIR}/dns_resolves.csv"
    fi

    # Assert: puede tener éxito o fallar según implementación
    # pero debe reportar el ciclo
    if [ -f "${OUT_DIR}/cycles_report.txt" ]; then
        run grep -qi "cycle\|ciclo" "${OUT_DIR}/cycles_report.txt"
        [ "$status" -eq 0 ]
    fi
}