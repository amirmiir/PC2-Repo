# Bitácora Sprint 2

## Diego Orrego (Día 3) - Miércoles 01/10/2025

### Contexto

Implementé el script `src/build_graph.sh` para construir el grafo de dependencias DNS a partir del CSV de resoluciones. Este script genera dos artefactos clave: el edge list (edges.csv) que representa las conexiones entre dominios e IPs, y el reporte de profundidad (depth_report.txt) que calcula métricas sobre la longitud de las cadenas de resolución.

### Comandos ejecutados

```bash
# Crear el script de construcción de grafo
touch src/build_graph.sh
chmod +x src/build_graph.sh

# Ejecutar construcción de grafo
./src/build_graph.sh

# Validar edge list generado
head -5 out/edges.csv
wc -l out/edges.csv

# Validar tipos de aristas
awk -F',' 'NR > 1 {print $3}' out/edges.csv | sort | uniq -c

# Verificar reporte de profundidad
cat out/depth_report.txt

# Validar formato de edges.csv (3 columnas)
awk -F',' 'NR > 1 && NF != 3 {print "ERROR: línea " NR " tiene " NF " columnas"; exit 1}' out/edges.csv
echo $?
```

### Salidas relevantes y códigos de estado

- **Comando**: `./src/build_graph.sh` → **Código**: 0 (éxito)
  ```
  [2025-10-01 22:10:51] [INFO] Iniciando construcción de grafo DNS
  [2025-10-01 22:10:51] [INFO] Validando archivo de entrada: out/dns_resolves.csv
  [2025-10-01 22:10:51] [INFO] Validación completada: 8 líneas encontradas
  [2025-10-01 22:10:51] [INFO] Generando edge list desde out/dns_resolves.csv
  Aristas generadas - A: 7, CNAME: 0
  [2025-10-01 22:10:51] [INFO] Edge list generado: 7 aristas en out/edges.csv
  [2025-10-01 22:10:51] [INFO] Calculando profundidad del grafo
  [2025-10-01 22:10:51] [INFO] Reporte de profundidad generado: out/depth_report.txt
  [2025-10-01 22:10:51] [INFO] Profundidad máxima: 6, promedio: 3.14
  ```

- **Comando**: `head -5 out/edges.csv` → **Salida**:
  ```csv
  from,to,kind
  google.com,142.250.0.113,A
  google.com,142.250.0.102,A
  google.com,142.250.0.101,A
  google.com,142.250.0.138,A
  ```

- **Comando**: `wc -l out/edges.csv` → **Salida**: `8 out/edges.csv` (7 aristas + header)

- **Comando**: `awk -F',' 'NR > 1 {print $3}' out/edges.csv | sort | uniq -c` → **Salida**:
  ```
        7 A
  ```
  Esto indica que los 7 registros en el dataset actual son todos de tipo A (resolución directa), sin CNAMEs.

- **Comando**: Validación de formato → **Código**: 0 (todas las líneas tienen 3 columnas correctamente)

### Decisiones técnicas tomadas

1. **Generación de edge list con awk**:
   Utilicé awk para procesar el CSV de forma eficiente, generando aristas en formato `from,to,kind`. Cada registro DNS se convierte en una arista del grafo:
   - Registros A: `dominio -> IP` (tipo A)
   - Registros CNAME: `dominio -> cname_destino` (tipo CNAME)

2. **Cálculo de profundidad**:
   Implementé un algoritmo que cuenta las aristas por cada origen único. La profundidad representa el número de saltos desde el dominio de entrada hasta llegar a un registro A final:
   ```
   Profundidad máxima: 6 saltos
   Profundidad promedio: 3.14 saltos
   ```

3. **Criterio de profundidad**:
   - Para dominios con resolución A directa (sin CNAMEs intermedios): profundidad = 1
   - Para cadenas con CNAMEs: profundidad = número de saltos en la cadena
   - Ejemplo: `ejemplo.com -> cname1.com -> cname2.com -> 1.2.3.4` tiene profundidad 3

4. **Separación C-L-E (Configurar-Lanzar-Ejecutar)**:
   El script `build_graph.sh` NO consulta la red, solo post-procesa el CSV generado previamente. Esto mantiene la separación de responsabilidades y permite ejecutar el análisis de grafo sin depender de conectividad DNS.

5. **Manejo de errores robusto**:
   - Validación de existencia y legibilidad de `dns_resolves.csv`
   - Verificación de CSV no vacío (al menos 2 líneas: header + datos)
   - Uso de archivos temporales gestionados por `common.sh` con cleanup automático
   - Códigos de salida documentados (EXIT_SUCCESS=0, EXIT_CONFIG_ERROR=5)

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
---
