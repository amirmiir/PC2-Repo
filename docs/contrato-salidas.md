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

**Propósito**: Lista de aristas del grafo de dependencias DNS.

**Formato**: CSV con encabezado
```
from,to,kind
```

**Validación**:
```bash
awk -F',' 'NR>1 && NF==3 && ($3=="CNAME" || $3=="A")' out/edges.csv
```

### depth_report.txt

**Propósito**: Reporte de profundidad máxima y promedio del grafo.

**Validación**:
```bash
grep -q "Profundidad máxima" out/depth_report.txt
grep -q "Profundidad promedio" out/depth_report.txt
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