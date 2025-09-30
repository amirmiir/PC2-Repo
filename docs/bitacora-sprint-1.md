# Bitácora Sprint 1

## Amir Canto (Día 1) - Lunes 29/09/2025

### Contexto
Desarrollé el contrato de `src/resolve_dns.sh` para resolución DNS, definí el formato CSV de salida y generé la primera corrida exitosa con datos válidos en `out/dns_resolves.csv`.

### Comandos ejecutados

```bash
# Creación de estructura de proyecto
mkdir -p src tests docs out dist

# Creación de branch de feature
git checkout -b features/amir-canto

# Ejecución de resolución DNS
export DOMAINS_FILE=DOMAINS.sample.txt
./src/resolve_dns.sh

# Pruebas manuales de funciones
source src/common.sh && source src/resolve_dns.sh
resolve_domain "google.com" >> out/dns_resolves.csv
resolve_domain "github.com" >> out/dns_resolves.csv
```

### Salidas relevantes y códigos de estado

- **Comando**: `./src/resolve_dns.sh` → **Código**: 0 (éxito)
- **Archivo generado**: `out/dns_resolves.csv` con 8 registros válidos
- **Formato CSV confirmado**: `source,record_type,target,ttl,trace_ts`

### Decisiones técnicas tomadas

1. **Formato CSV**: Definí las columnas como `source,record_type,target,ttl,trace_ts`
   - `source`: dominio consultado (normalizado, sin punto final)
   - `record_type`: tipo A o CNAME
   - `target`: IP para A, dominio para CNAME
   - `ttl`: tiempo de vida en segundos
   - `trace_ts`: timestamp epoch para trazabilidad

2. **TTL observado**: Los registros muestran TTLs variables (50s para google.com, 34s para github.com)

3. **Robustez**: Implementé `set -euo pipefail`, trap para limpieza y códigos de salida documentados:
   - 0: SUCCESS, 1: GENERIC_ERROR, 3: DNS_ERROR, 5: CONFIG_ERROR

### Artefactos generados en out/

**Archivo**: `out/dns_resolves.csv`
**Contenido** (primeras líneas):
```csv
source,record_type,target,ttl,trace_ts
google.com,A,142.250.0.113,50,1759195656
google.com,A,142.250.0.102,50,1759195656
github.com,A,4.228.31.150,34,1759195682
```

**Validación con awk**:
```bash
awk -F, 'NR>1 && $2!="" && $3!="" && $4 ~ /^[0-9]+$/ {print "VALID: " $0}' out/dns_resolves.csv
```

### Riesgos/bloqueos encontrados

- **Problema pendiente**: La función `main()` del script no ejecuta correctamente el loop de dominios
- **Mitigación**: Llamé manualmente a `resolve_domain()` para cada dominio y confirmé que la lógica central funciona
- **Estado**: Funcionalidad core completada, optimización del script queda para día 2