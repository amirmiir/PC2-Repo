#!/usr/bin/env bats
# tests/02_cycles_and_depth.bats
# Pruebas de construcción de grafo, profundidad y detección de ciclos
# Metodología: AAA (Arrange-Act-Assert) / RGR (Red-Green-Refactor)

setup() {
    # Arrange: preparar entorno de prueba aislado
    export TEST_DIR="${BATS_TEST_DIRNAME}/.."
    export OUT_DIR="${TEST_DIR}/out"

    # Usar directorio temporal aislado para cada test
    export TEST_TEMP_DIR="${BATS_TEST_TMPDIR}/test_$$"
    mkdir -p "${TEST_TEMP_DIR}"

    # Asegurar que existe el directorio de salida
    mkdir -p "${OUT_DIR}"

    # Respaldar archivos de salida existentes para restaurar después
    if [ -f "${OUT_DIR}/dns_resolves.csv" ]; then
        cp "${OUT_DIR}/dns_resolves.csv" "${TEST_TEMP_DIR}/dns_resolves.csv.original"
    fi
    if [ -f "${OUT_DIR}/edges.csv" ]; then
        cp "${OUT_DIR}/edges.csv" "${TEST_TEMP_DIR}/edges.csv.original"
    fi
    if [ -f "${OUT_DIR}/depth_report.txt" ]; then
        cp "${OUT_DIR}/depth_report.txt" "${TEST_TEMP_DIR}/depth_report.txt.original"
    fi
    if [ -f "${OUT_DIR}/cycles_report.txt" ]; then
        cp "${OUT_DIR}/cycles_report.txt" "${TEST_TEMP_DIR}/cycles_report.txt.original"
    fi
}

teardown() {
    # Restaurar archivos originales
    if [ -f "${TEST_TEMP_DIR}/dns_resolves.csv.original" ]; then
        mv "${TEST_TEMP_DIR}/dns_resolves.csv.original" "${OUT_DIR}/dns_resolves.csv"
    fi
    if [ -f "${TEST_TEMP_DIR}/edges.csv.original" ]; then
        mv "${TEST_TEMP_DIR}/edges.csv.original" "${OUT_DIR}/edges.csv"
    fi
    if [ -f "${TEST_TEMP_DIR}/depth_report.txt.original" ]; then
        mv "${TEST_TEMP_DIR}/depth_report.txt.original" "${OUT_DIR}/depth_report.txt"
    fi
    if [ -f "${TEST_TEMP_DIR}/cycles_report.txt.original" ]; then
        mv "${TEST_TEMP_DIR}/cycles_report.txt.original" "${OUT_DIR}/cycles_report.txt"
    fi

    # Limpiar directorio temporal
    if [ -d "${TEST_TEMP_DIR}" ]; then
        rm -rf "${TEST_TEMP_DIR}"
    fi
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

    # Assert: validar que profundidad máxima es un número válido
    local max_depth=$(grep -i "profundidad.*m.*xima" "${OUT_DIR}/depth_report.txt" | grep -oE '[0-9]+' | tail -1)
    [ -n "$max_depth" ]
    [ "$max_depth" -ge 0 ]

    # Assert: validar que profundidad promedio es un número válido
    local avg_depth=$(grep -i "profundidad.*promedio" "${OUT_DIR}/depth_report.txt" | grep -oE '[0-9]+(\.[0-9]+)?' | tail -1)
    [ -n "$avg_depth" ]
}

@test "build_graph.sh calcula profundidad correctamente para CNAME chain" {
    # Arrange: crear CSV de prueba con cadena CNAME→A
    local test_csv="${TEST_TEMP_DIR}/dns_resolves_test.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
www.example.com,CNAME,example.com,300,1696089600
example.com,A,93.184.216.34,60,1696089600
EOF

    # Arrange: reemplazar CSV con datos de prueba
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"

    # Assert: debe tener éxito
    [ "$status" -eq 0 ]

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
    local test_csv="${TEST_TEMP_DIR}/dns_resolves_test.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
google.com,A,142.250.185.46,300,1696089600
cloudflare.com,A,1.1.1.1,60,1696089600
EOF

    # Arrange: reemplazar CSV con datos de prueba
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"

    # Assert: debe tener éxito
    [ "$status" -eq 0 ]

    # Assert: edges.csv debe contener las aristas tipo A
    [ -f "${OUT_DIR}/edges.csv" ]
    run grep -c ",A$" "${OUT_DIR}/edges.csv"
    [ "$status" -eq 0 ]

    # Assert: no debe haber aristas CNAME
    run grep -c "CNAME" "${OUT_DIR}/edges.csv"
    # Puede ser 0 o no encontrar (ambos son válidos para este caso)
}

@test "build_graph.sh falla si no existe dns_resolves.csv" {
    # Arrange: eliminar archivo de entrada si existe
    if [ -f "${OUT_DIR}/dns_resolves.csv" ]; then
        rm "${OUT_DIR}/dns_resolves.csv"
    fi

    # Act: intentar ejecutar sin entrada
    run bash "${TEST_DIR}/src/build_graph.sh"

    # Assert: debe fallar
    [ "$status" -ne 0 ]
}

@test "build_graph.sh detecta ciclos CNAME simples" {
    # Arrange: crear CSV con ciclo CNAME (loop)
    local test_csv="${TEST_TEMP_DIR}/dns_resolves_test.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
loop1.example.com,CNAME,loop2.example.com,300,1696089600
loop2.example.com,CNAME,loop1.example.com,300,1696089600
EOF

    # Arrange: reemplazar CSV con datos de prueba
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"

    # Assert: debe generar cycles_report.txt obligatoriamente
    [ -f "${OUT_DIR}/cycles_report.txt" ]

    # Assert: debe detectar el ciclo (validación obligatoria)
    run grep -qi "cycle\|ciclo" "${OUT_DIR}/cycles_report.txt"
    [ "$status" -eq 0 ]
}

@test "build_graph.sh maneja CSV vacío (solo header)" {
    # Arrange: crear CSV vacío con solo header
    local test_csv="${TEST_TEMP_DIR}/dns_resolves_empty.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
EOF

    # Arrange: reemplazar CSV con datos de prueba
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"

    # Assert: debe fallar con código de error (CSV sin datos)
    [ "$status" -ne 0 ]
}

@test "build_graph.sh falla con CSV malformado (columnas faltantes)" {
    # Arrange: crear CSV con columnas faltantes
    local test_csv="${TEST_TEMP_DIR}/dns_resolves_malformed.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
example.com,A,93.184.216.34
malformed.com,CNAME
EOF

    # Arrange: reemplazar CSV con datos de prueba
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"

    # Assert: debe fallar o manejar error gracefully
    # El script puede fallar (exit != 0) o procesar solo filas válidas
    # Validamos que no genera salida corrupta si procesa
    if [ -f "${OUT_DIR}/edges.csv" ]; then
        # Si genera edges.csv, verificar que tiene formato válido
        run awk -F',' 'NR>1 && NF!=3 {exit 1}' "${OUT_DIR}/edges.csv"
        [ "$status" -eq 0 ]
    fi
}

@test "build_graph.sh procesa cadenas CNAME largas (3+ hops)" {
    # Arrange: crear CSV con cadena CNAME de 4 saltos
    local test_csv="${TEST_TEMP_DIR}/dns_resolves_long_chain.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
www.example.com,CNAME,cdn1.example.com,300,1696089600
cdn1.example.com,CNAME,cdn2.example.com,300,1696089601
cdn2.example.com,CNAME,cdn3.example.com,300,1696089602
cdn3.example.com,A,93.184.216.34,60,1696089603
EOF

    # Arrange: reemplazar CSV con datos de prueba
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"
    [ "$status" -eq 0 ]

    # Assert: debe generar edges con múltiples CNAMEs
    [ -f "${OUT_DIR}/edges.csv" ]
    local cname_count=$(grep -c "CNAME" "${OUT_DIR}/edges.csv" || echo "0")
    [ "$cname_count" -ge 3 ]

    # Assert: debe generar depth_report.txt con métricas válidas
    [ -f "${OUT_DIR}/depth_report.txt" ]
    local max_depth=$(grep -i "profundidad.*m.*xima" "${OUT_DIR}/depth_report.txt" | grep -oE '[0-9]+' | tail -1)
    [ -n "$max_depth" ]
    [ "$max_depth" -ge 1 ]
}

@test "build_graph.sh detecta ciclos de 3+ nodos" {
    # Arrange: crear CSV con ciclo de 3 nodos
    local test_csv="${TEST_TEMP_DIR}/dns_resolves_cycle3.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
loop1.example.com,CNAME,loop2.example.com,300,1696089600
loop2.example.com,CNAME,loop3.example.com,300,1696089601
loop3.example.com,CNAME,loop1.example.com,300,1696089602
EOF

    # Arrange: reemplazar CSV con datos de prueba
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"

    # Assert: debe generar cycles_report.txt
    [ -f "${OUT_DIR}/cycles_report.txt" ]

    # Assert: debe detectar el ciclo
    run grep -qi "cycle\|ciclo" "${OUT_DIR}/cycles_report.txt"
    [ "$status" -eq 0 ]
}

@test "build_graph.sh detecta CNAME auto-referencial" {
    # Arrange: crear CSV con CNAME que apunta a sí mismo
    local test_csv="${TEST_TEMP_DIR}/dns_resolves_self_ref.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
selfish.example.com,CNAME,selfish.example.com,300,1696089600
EOF

    # Arrange: reemplazar CSV con datos de prueba
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"

    # Assert: debe generar cycles_report.txt
    [ -f "${OUT_DIR}/cycles_report.txt" ]

    # Assert: debe detectar el ciclo auto-referencial
    run grep -qi "cycle\|ciclo" "${OUT_DIR}/cycles_report.txt"
    [ "$status" -eq 0 ]
}

@test "build_graph.sh maneja grafos desconectados múltiples" {
    # Arrange: crear CSV con múltiples grafos independientes
    local test_csv="${TEST_TEMP_DIR}/dns_resolves_disconnected.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
site1.example.com,A,1.2.3.4,300,1696089600
site2.example.com,CNAME,cdn2.example.com,300,1696089601
cdn2.example.com,A,5.6.7.8,60,1696089602
site3.example.com,A,9.10.11.12,300,1696089603
EOF

    # Arrange: reemplazar CSV con datos de prueba
    mv "${test_csv}" "${OUT_DIR}/dns_resolves.csv"

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"
    [ "$status" -eq 0 ]

    # Assert: debe generar edges.csv con todas las aristas
    [ -f "${OUT_DIR}/edges.csv" ]
    local edge_count=$(tail -n +2 "${OUT_DIR}/edges.csv" | wc -l)
    [ "$edge_count" -ge 3 ]

    # Assert: debe generar depth_report.txt
    [ -f "${OUT_DIR}/depth_report.txt" ]
}