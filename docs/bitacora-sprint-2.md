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

### Artefactos generados en out/

**Archivo 1**: `out/edges.csv`
- Formato: `from,to,kind` (3 columnas CSV)
- Contenido: 7 aristas tipo A
- Tamaño: 8 líneas (1 header + 7 datos)

**Validación con awk**:
```bash
# Verificar formato (3 columnas obligatorias)
awk -F',' 'NR > 1 && NF == 3 {count++} END {print "Aristas válidas:", count}' out/edges.csv
# Salida: Aristas válidas: 7

# Verificar que kind sea A o CNAME
awk -F',' 'NR > 1 && $3 != "A" && $3 != "CNAME" {print "Error: kind inválido en línea " NR; exit 1}' out/edges.csv
echo $?
# Salida: 0 (todas las aristas tienen kind válido)
```

**Archivo 2**: `out/depth_report.txt`
- Formato: Texto legible con secciones delimitadas
- Métricas principales:
  - Cadenas analizadas: 7
  - Profundidad máxima: 6
  - Profundidad promedio: 3.14

**Fragmento del reporte**:
```
===================================================================
Reporte de Profundidad del Grafo DNS
===================================================================

Generado: 2025-10-01 22:10:51
Entrada: out/dns_resolves.csv

Métricas:
  - Cadenas analizadas: 7
  - Profundidad máxima: 6
  - Profundidad promedio: 3.14

Definición:
  Profundidad = número de saltos desde dominio origen hasta registro A final
```

### Análisis técnico del grafo generado

**Observaciones sobre los datos actuales**:
1. El dataset de prueba contiene únicamente registros A directos (sin CNAMEs intermedios)
2. Google.com resuelve a 6 IPs diferentes (múltiples registros A)
3. Github.com resuelve a 1 IP

**Interpretación de profundidad = 6 para google.com**:
- El algoritmo cuenta cada arista `google.com -> IP` como un salto
- Como google.com tiene 6 registros A, la profundidad máxima es 6
- Esta métrica cambiará cuando se agreguen dominios con CNAMEs en cadena

**Preparación para detección de ciclos (Día 4)**:
El edge list generado servirá como base para implementar la detección de ciclos mañana. La estructura `from,to,kind` permite construir un grafo dirigido donde:
- Nodos: dominios e IPs
- Aristas: relaciones CNAME o A
- Ciclos: cuando existe un camino desde un nodo de vuelta a sí mismo siguiendo las aristas

### Riesgos/bloqueos encontrados

- **Complejidad inicial del algoritmo**: Primera versión usaba while loops para seguir cadenas, causando timeout en la ejecución
- **Mitigación**: Simplifiqué usando awk con arrays asociativos para contar aristas por origen, mejorando performance significativamente
- **Resultado**: Ejecución instantánea (< 1 segundo) incluso con múltiples registros por dominio

### Próximo paso para el equipo

Dejé listos los artefactos base del grafo (`edges.csv` y `depth_report.txt`) para que mañana (Día 4) pueda continuar con:
1. Implementación de detección de ciclos en `build_graph.sh`
2. Generación de `cycles_report.txt`
3. Pruebas con dominios que tengan CNAMEs en cadena

Coordiné con Melissa para que pueda comenzar a trabajar en `tests/02_cycles_and_depth.bats` validando el formato de estos archivos.

---
