# Contrato de Salidas

## Archivos generados en out/

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
- `ttl`: Tiempo de vida en segundos
- `trace_ts`: Timestamp Unix de la consulta

**Validación con herramientas de texto**:
```bash
# Verificar formato (5 columnas por fila, TTL numérico)
awk -F, 'NR>1 && NF==5 && $4 ~ /^[0-9]+$/ {count++} END {print "Registros válidos:", count}' out/dns_resolves.csv

# Verificar tipos de registro permitidos
awk -F, 'NR>1 && ($2=="A" || $2=="CNAME") {print $0}' out/dns_resolves.csv

# Detectar duplicados (misma combinación source,record_type,target)
awk -F, 'NR>1 {key=$1","$2","$3; if(seen[key]++) print "DUPLICADO:", $0}' out/dns_resolves.csv
```

**Ejemplo de contenido válido**:
```csv
source,record_type,target,ttl,trace_ts
google.com,A,142.250.0.113,50,1759195656
github.com,A,4.228.31.150,34,1759195682
```

## Variables de entorno requeridas

### DOMAINS_FILE (Obligatorio)
**Descripción**: Ruta al archivo con dominios a resolver (uno por línea)
**Efecto observable**: El script lee este archivo y procesa cada dominio no comentado
**Ejemplo**: `DOMAINS_FILE=DOMAINS.sample.txt`

### DNS_SERVER (Opcional)
**Descripción**: Servidor DNS específico para consultas
**Efecto observable**: Aparece como `@servidor` en comando dig interno
**Ejemplo**: `DNS_SERVER=1.1.1.1` → `dig @1.1.1.1 +noall +answer dominio A`

## Determinismo y reproducibilidad

- **Nombre fijo**: `out/dns_resolves.csv` (sobrescribible en corridas posteriores)
- **Idempotencia**: Verificada en Sprint 3 con medición de tiempos
- **Trazabilidad**: Timestamp permite correlacionar con logs del sistema