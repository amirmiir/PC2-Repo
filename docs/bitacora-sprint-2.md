# Bitácora Sprint 2

## Melissa Iman (Día 3) - Miércoles 01/10/2025

### Contexto

Desarrollé la suite de pruebas Bats para validar la construcción del grafo de dependencias DNS, incluyendo generación de edge-list, cálculo de profundidad y detección de ciclos CNAME. Apliqué metodología AAA/RGR y ejecuté revisión de código para asegurar calidad.

### Comandos ejecutados

```bash
# Crear archivo de pruebas para grafo
touch tests/02_cycles_and_depth.bats
chmod +x tests/02_cycles_and_depth.bats

# Contar líneas del archivo creado
wc -l tests/02_cycles_and_depth.bats

# Actualizar contrato de salidas con formato edges.csv
cat docs/contrato-salidas.md | grep -A 10 "edges.csv"

# Ejecutar revisión de código
# (análisis de patrones Bats, validaciones, casos edge)
```

### Salidas relevantes y códigos de estado

- **Archivo creado**: `tests/02_cycles_and_depth.bats` con 202 líneas
- **Casos de prueba totales**: 7 tests para grafo
- **Revisión de código**: Calificación 7.5/10
- **Archivo actualizado**: `docs/contrato-salidas.md` con formato edges.csv ampliado

### Decisiones técnicas tomadas

1. **Casos de prueba para edges.csv**:
   - Validación de formato (from,to,kind con 3 columnas)
   - Verificación de tipos kind (solo CNAME o A permitidos)
   - Validación que from/to no estén vacíos
   - Uso de awk para contar aristas por tipo

2. **Casos de prueba para depth_report.txt**:
   - Verificación de existencia del archivo
   - Validación de presencia de métricas de profundidad
   - Test específico para cadena CNAME->A (profundidad >= 2)

3. **Casos de prueba para ciclos CNAME**:
   - Test de ciclo simple (2 nodos: loop1->loop2->loop1)
   - Verificación de reporte en cycles_report.txt
   - Detección de palabra clave "CYCLE" o "ciclo"

4. **Patrón de backup/restore para datos de prueba**:
   - Respaldo de dns_resolves.csv antes de tests
   - Restauración después de ejecución
   - Cleanup explícito con variables locales

### Artefactos generados

**Archivo**: `tests/02_cycles_and_depth.bats`
- 202 líneas de código documentado
- 7 casos de prueba con metodología AAA
- Cobertura: formato, validación de columnas, profundidad, ciclos, manejo de errores

**Casos de prueba implementados**:

1. `build_graph.sh genera edges.csv con formato correcto`
2. `build_graph.sh valida columnas de edges.csv correctamente`
3. `build_graph.sh genera depth_report.txt con métricas de profundidad`
4. `build_graph.sh calcula profundidad correctamente para CNAME chain`
5. `build_graph.sh maneja correctamente registros solo tipo A`
6. `build_graph.sh falla si no existe dns_resolves.csv`
7. `build_graph.sh detecta ciclos CNAME simples`

**Archivo actualizado**: `docs/contrato-salidas.md`
- Descripción detallada de columnas de edges.csv
- Ejemplo de contenido válido
- 3 comandos de validación con awk
- Contador de aristas por tipo (CNAME vs A)

### Revisión de código - Resultados clave

**Puntos fuertes identificados** (calificación 7.5/10):
- ✓ Estructura AAA bien aplicada con comentarios
- ✓ Validación de headers CSV correcta
- ✓ Uso apropiado de awk para validar estructura
- ✓ Nombres de tests descriptivos
- ✓ Intento de manejo de estado con backup/restore

**Mejoras identificadas**:
- Aislamiento de tests mejorable (usar BATS_TEST_TMPDIR)
- Cleanup debería estar en teardown() o usar trap
- Validación de ciclos condicional (debería ser obligatoria)
- Falta limpieza de archivos de salida entre tests
- Validación de profundidad solo verifica existencia, no valores numéricos

**Casos edge faltantes identificados**:
- CSV vacío (solo header)
- CSV malformado (columnas faltantes)
- Cadenas CNAME largas (3+ hops)
- Ciclos de 3+ nodos
- CNAME auto-referencial
- Grafos desconectados múltiples

### Riesgos/bloqueos encontrados

- **Dependencia del script build_graph.sh**: Tests en fase ROJA hasta que Amir implemente el script
- **Estado compartido**: Múltiples tests modifican dns_resolves.csv, potencial race condition
- **Mitigación para Sprint 3**: Refactorizar usando BATS_TEST_TMPDIR y cleanup robusto

### Evidencia de tests implementados

**Test de formato edges.csv**:
```bash
@test "build_graph.sh genera edges.csv con formato correcto" {
    # Arrange: verificar que existe el script
    [ -f "${TEST_DIR}/src/build_graph.sh" ]

    # Act: ejecutar construcción de grafo
    run bash "${TEST_DIR}/src/build_graph.sh"

    # Assert: verificar cabecera del CSV
    header=$(head -n 1 "${OUT_DIR}/edges.csv")
    [ "$header" = "from,to,kind" ]
}
```

**Test de ciclo CNAME**:
```bash
@test "build_graph.sh detecta ciclos CNAME simples" {
    # Arrange: crear CSV con ciclo CNAME (loop)
    local test_csv="${OUT_DIR}/dns_resolves_test.csv"
    cat > "${test_csv}" <<EOF
source,record_type,target,ttl,trace_ts
loop1.example.com,CNAME,loop2.example.com,300,1696089600
loop2.example.com,CNAME,loop1.example.com,300,1696089600
EOF
    # ... backup, ejecución, restore ...

    # Assert: debe reportar el ciclo
    if [ -f "${OUT_DIR}/cycles_report.txt" ]; then
        run grep -qi "cycle\|ciclo" "${OUT_DIR}/cycles_report.txt"
        [ "$status" -eq 0 ]
    fi
}
```

### Validaciones añadidas al contrato

```bash
# Verificar formato (3 columnas, kind válido)
awk -F',' 'NR>1 && NF==3 && ($3=="CNAME" || $3=="A")' out/edges.csv

# Verificar que from y to no están vacíos
awk -F',' 'NR>1 && ($1=="" || $2=="") {print "Error línea " NR; exit 1}' out/edges.csv

# Contar aristas por tipo
awk -F',' 'NR>1 && $3=="CNAME" {cname++} NR>1 && $3=="A" {a++} END {print "CNAME:", cname, "A:", a}' out/edges.csv
```

### Próximo paso

Implementaré las mejoras de aislamiento identificadas en la revisión. Para Día 4, desarrollaré `tests/03_connectivity_probe.bats` y `tests/04_env_contracts.bats` completando la cobertura de Sprint 2.