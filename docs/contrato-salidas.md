# Contrato de Salidas

Este documento define el formato, ubicación y método de validación de todos los archivos generados por el sistema de mapeo de dependencias DNS.

## Ubicación de Archivos

Todos los archivos de salida se generan en el directorio `out/` del proyecto. Este directorio debe crearse automáticamente durante la ejecución si no existe.

## Archivos Generados - Sprint 1

### dns_resolves.csv

**Propósito**: Registro normalizado de resoluciones DNS A/CNAME con TTL y timestamp.

**Formato**: CSV con encabezado
```
source,record_type,target,ttl,trace_ts
```

**Descripción de columnas**:
- `source`: Dominio consultado (sin punto final)
- `record_type`: Tipo de registro (`A` o `CNAME`)
- `target`: Destino (IP para A, dominio para CNAME)
- `ttl`: Tiempo de vida en segundos (valor numérico entero)
- `trace_ts`: Timestamp Unix de la consulta

**Ejemplo de contenido válido**:
```csv
source,record_type,target,ttl,trace_ts
google.com,A,142.250.0.113,50,1759195656
www.github.com,CNAME,github.com,3600,1759195657
github.com,A,140.82.121.4,60,1759195658
```

**Validación con herramientas de texto**:

Verificar formato (5 columnas por fila, TTL numérico):
```bash
awk -F',' 'NR>1 && NF==5 && $4 ~ /^[0-9]+$/ {count++} END {print "Registros válidos:", count}' out/dns_resolves.csv
```

Verificar tipos de registro permitidos (solo A o CNAME):
```bash
awk -F',' 'NR>1 && $2!="A" && $2!="CNAME" {print "Error línea " NR; exit 1}' out/dns_resolves.csv
```

Detectar duplicados (misma combinación source,record_type,target):
```bash
awk -F',' 'NR>1 {key=$1","$2","$3; if(seen[key]++) print "DUPLICADO:", $0}' out/dns_resolves.csv
```

Verificar que hay al menos una resolución:
```bash
line_count=$(wc -l < out/dns_resolves.csv)
[ "$line_count" -gt 1 ] && echo "CSV contiene datos"
```

## Archivos Generados - Sprint 2

### edges.csv

**Propósito**: Lista de aristas (edges) del grafo de dependencias DNS que representa las relaciones entre dominios e IPs.

**Formato**: CSV con encabezado
```
from,to,kind
```

**Descripción de columnas**:
- `from`: Nodo origen (dominio)
- `to`: Nodo destino (dominio CNAME o IP final)
- `kind`: Tipo de relación (`CNAME` o `A`)

**Lógica de construcción de aristas**:
- Para registros A: `dominio -> IP` (kind=A)
- Para registros CNAME: `dominio -> cname_destino` (kind=CNAME)

**Ejemplo de contenido válido**:
```csv
from,to,kind
google.com,142.250.0.113,A
google.com,142.250.0.102,A
www.github.com,github.com,CNAME
github.com,140.82.121.4,A
```

**Características**:
- Generado a partir de `dns_resolves.csv` (no consulta red)
- Determinista: mismo CSV de entrada produce mismo edge list
- Una fila por cada relación DNS encontrada
- Múltiples registros A para un dominio generan múltiples aristas

**Validación con herramientas de texto**:

Verificar formato (3 columnas obligatorias):
```bash
awk -F',' 'NR>1 && NF==3 {count++} END {print "Aristas válidas:", count}' out/edges.csv
```

Verificar que `kind` sea solo A o CNAME:
```bash
# Verificar que no hay valores inválidos en columna kind
awk -F',' 'NR>1 && ($3 == "A" || $3 == "CNAME") {valid++} NR>1 {total++} END {if (valid == total) print "OK: todos los kind son válidos"; else print "ERROR: hay kind inválidos"}' out/edges.csv
```

Contar tipos de aristas:
```bash
awk -F',' 'NR>1 {print $3}' out/edges.csv | sort | uniq -c
```

Verificar que `from` y `to` existen en dns_resolves.csv:
```bash
# Extraer nodos del edge list
awk -F',' 'NR>1 {print $1; print $2}' out/edges.csv | sort -u > /tmp/nodes.txt
# Verificar que corresponden a source/target en dns_resolves.csv
awk -F',' 'NR>1 {print $1; print $3}' out/dns_resolves.csv | sort -u > /tmp/dns_nodes.txt
diff /tmp/nodes.txt /tmp/dns_nodes.txt
```

Verificar que hay al menos una arista:
```bash
line_count=$(wc -l < out/edges.csv)
[ "$line_count" -gt 1 ] && echo "Edge list contiene datos"
```

Verificar que from y to no están vacíos:
```bash
awk -F',' 'NR>1 && ($1=="" || $2=="") {print "Error línea " NR; exit 1}' out/edges.csv
```

Contar aristas por tipo:
```bash
awk -F',' 'NR>1 && $3=="CNAME" {cname++} NR>1 && $3=="A" {a++} END {print "CNAME:", cname, "A:", a}' out/edges.csv
```

### depth_report.txt

**Propósito**: Reporte de profundidad del grafo DNS con métricas estadísticas sobre la longitud de las cadenas de resolución.

**Formato**: Texto legible con secciones delimitadas por líneas `===`

**Estructura del archivo**:
```
===================================================================
Reporte de Profundidad del Grafo DNS
===================================================================

Generado: <timestamp>
Entrada: <archivo_csv_origen>

Métricas:
  - Cadenas analizadas: <N>
  - Profundidad máxima: <max>
  - Profundidad promedio: <avg>

Definición:
  Profundidad = número de saltos desde dominio origen hasta registro A final

Ejemplo:
  ejemplo.com -> cname1.com -> cname2.com -> 1.2.3.4
  Profundidad: 3 (3 aristas en la cadena)

Nota:
  Para dominios con resolución A directa (sin CNAMEs), profundidad = 1

===================================================================
```

**Definición de profundidad**:
- Profundidad = número de saltos/aristas desde dominio origen hasta registro A final
- Para dominios con resolución A directa: profundidad = 1
- Para cadenas CNAME: profundidad = número de CNAMEs + 1 (registro A final)

**Ejemplo de interpretación**:
```
Cadena: www.ejemplo.com -> ejemplo.com -> cdn.ejemplo.com -> 1.2.3.4
Aristas: 3 (2 CNAMEs + 1 A)
Profundidad: 3
```

**Validación con herramientas de texto**:

Verificar que contiene las métricas obligatorias:
```bash
grep -q "Profundidad máxima" out/depth_report.txt && echo "Métrica máxima OK"
grep -q "Profundidad promedio" out/depth_report.txt && echo "Métrica promedio OK"
grep -q "Cadenas analizadas" out/depth_report.txt && echo "Métrica cadenas OK"
```

Extraer métricas para análisis:
```bash
grep "Profundidad máxima" out/depth_report.txt | awk '{print $NF}'
grep "Profundidad promedio" out/depth_report.txt | awk '{print $NF}'
grep "Cadenas analizadas" out/depth_report.txt | awk '{print $NF}'
```

Verificar formato del archivo:
```bash
# Debe tener delimitadores
grep -c "^===" out/depth_report.txt  # Debe ser >= 2
```

Validar que el archivo no está vacío:
```bash
[ -f out/depth_report.txt ] && [ -s out/depth_report.txt ] && echo "Reporte generado correctamente"
```

### cycles_report.txt

**Propósito**: Reporte de ciclos detectados en el grafo DNS.

**Validación**:
```bash
# Si hay ciclos, debe contener palabra clave CYCLE
if grep -q "CYCLE" out/cycles_report.txt; then
    echo "Ciclo detectado correctamente"
fi
```

### connectivity_ss.txt

**Propósito**: Evidencia de verificación de conectividad con `ss` hacia IPs finales.

**Validación**:
```bash
[ -f out/connectivity_ss.txt ] && [ -s out/connectivity_ss.txt ]
```

### curl_probe.txt

**Propósito**: Resultado de sondas HTTP/HTTPS con `curl`.

**Validación**:
```bash
grep -E "(HTTP|https?://)" out/curl_probe.txt
```

## Variables de Entorno Requeridas

### DOMAINS_FILE (Obligatorio)
**Descripción**: Ruta al archivo con dominios a resolver (uno por línea)
**Efecto observable**: El script lee este archivo y procesa cada dominio no comentado
**Ejemplo**: `DOMAINS_FILE=DOMAINS.sample.txt`
**Fallo esperado**: Si no existe o no es legible, el script debe retornar código ≠ 0

### DNS_SERVER (Opcional)
**Descripción**: Servidor DNS específico para consultas
**Efecto observable**: Aparece como `@servidor` en comando dig interno
**Ejemplo**: `DNS_SERVER=1.1.1.1` → `dig @1.1.1.1 +noall +answer dominio A`

## Determinismo y Reproducibilidad

- **Nombre fijo**: `out/dns_resolves.csv` (sobrescribible en corridas posteriores)
- **Idempotencia**: Verificada en Sprint 3 con medición de tiempos
- **Trazabilidad**: Timestamp permite correlacionar con logs del sistema
- **Limpieza**: `make clean` elimina todo el directorio `out/` de forma segura