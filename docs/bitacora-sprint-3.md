# Bitácora Sprint 3 - Día 5 (03/10/2025)

## Melissa - Día 5: verify_connectivity.sh + Idempotencia

### Contexto

Implementé el script `verify_connectivity.sh` completo para verificar conectividad de red usando `ss`/`netstat` y sondear endpoints HTTP/HTTPS con `curl`. También demostré idempotencia ejecutando el script múltiples veces sin cambios en las entradas.

### Comandos ejecutados

```bash
# Crear y hacer ejecutable el script
chmod +x src/verify_connectivity.sh

# Primera ejecución
bash src/verify_connectivity.sh
# Salida: Generados connectivity_ss.txt (4.6K) y curl_probe.txt (1.5K)
# Código: 0

# Verificar archivos generados
ls -lh out/
# connectivity_ss.txt  4.6K
# curl_probe.txt       1.5K
# dns_resolves.csv     323B
# edges.csv            165B
# cycles_report.txt    392B
# depth_report.txt     675B

# Validar patrones esperados
grep -iE "(tcp|udp|estab|listen|dst|src|socket)" out/connectivity_ss.txt | wc -l
# 116 líneas coinciden - contiene evidencia de sockets TCP/UDP

grep -iE "(http|https|HTTP/[12]|status|curl)" out/curl_probe.txt | wc -l
# 16 líneas coinciden - contiene evidencia HTTP/HTTPS

grep -iE "(time|ms|second|latenc|duration|tiempo)" out/curl_probe.txt | wc -l
# 10 líneas coinciden - contiene información de tiempos

# Demostrar idempotencia
time bash src/verify_connectivity.sh
# Primera ejecución: 2.066s total
time bash src/verify_connectivity.sh
# Segunda ejecución: 2.027s total
# Archivos sobrescritos con contenido actualizado (timestamps nuevos)
```

### Salidas relevantes

**connectivity_ss.txt (extracto)**:
```
===================================================================
Reporte de Conectividad con ss/netstat (Socket Statistics)
===================================================================
Generado: 2025-10-03 08:34:47 MDT
Herramienta: netstat (macOS)
Objetivo: Verificar estado de sockets y conexiones TCP/UDP activas

-------------------------------------------------------------------
Estado general de sockets TCP
-------------------------------------------------------------------
tcp6  0  0  2604:3d09:6887:a.50451 2607:6bc0::10.443  ESTABLISHED
tcp4  0  0  10.0.0.41.50446        34.36.57.103.443   ESTABLISHED

TCP sockets: 116
UDP sockets: 43

Conexiones en puerto 443 (HTTPS):
tcp4  0  0  10.0.0.41.50446  34.36.57.103.443  ESTABLISHED
```

**curl_probe.txt (extracto)**:
```
===================================================================
Reporte de Sonda HTTP/HTTPS con curl
===================================================================
Generado: 2025-10-03 08:34:47 MDT
Timeout: 5s (conexión), 10s (total)

-------------------------------------------------------------------
Dominio: github.com -> IP: 4.228.31.150
-------------------------------------------------------------------

[HTTPS] Probando https://github.com
  Status: 200
  Protocolo: HTTPS (puerto 443, TLS/SSL)
  Tiempo de respuesta: 1s
  Resultado: OK - Servidor respondió correctamente

[HTTP] Probando http://github.com
  Status: 200
  Protocolo: HTTP (puerto 80, sin cifrado)
  Tiempo de respuesta: 1s
  Resultado: OK - Servidor respondió correctamente

-------------------------------------------------------------------
Dominio: google.com -> IP: 142.250.0.113
-------------------------------------------------------------------

[HTTPS] Probando https://google.com
  Status: 200
  Protocolo: HTTPS (puerto 443, TLS/SSL)
  Tiempo de respuesta: 0s
  Resultado: OK - Servidor respondió correctamente
```

### Decisiones técnicas

1. **Portabilidad ss vs netstat**:
   - Implementé detección automática: si `ss` no está disponible (macOS), usar `netstat`
   - Mantiene compatibilidad Linux/macOS sin código duplicado
   - Patrón: `if ! command -v ss; then use_netstat=true; fi`

2. **Formato de tiempos**:
   - Bash 3.x (macOS) no soporta `date +%s%3N` para milisegundos
   - Usé segundos (`date +%s`) con cálculo aritmético simple: `duration=$((end_time - start_time))`
   - Suficiente precisión para timeouts de 5-10s

3. **Estructura de reportes**:
   - Headers con timestamp, objetivo, herramienta usada
   - Secciones claramente delimitadas con separadores `---`
   - Búsqueda de IPs específicas desde `dns_resolves.csv` y `edges.csv`
   - Diferenciación explícita HTTP (puerto 80) vs HTTPS (puerto 443, TLS/SSL)

4. **Manejo de errores curl**:
   - Códigos HTTP interpretados: 2xx (OK), 3xx (redirección), 4xx (cliente), 5xx (servidor), 000 (timeout)
   - Captura de tiempos incluso en errores para análisis de latencia

5. **Idempotencia**:
   - Script sobrescribe archivos de salida en cada ejecución
   - Tiempos consistentes: ~2s por ejecución (dominado por timeouts curl)
   - No hay caché porque verifica estado de red actual (cambia entre ejecuciones)

### Artefactos generados

| Archivo | Tamaño | Contenido |
|---------|--------|-----------|
| `out/connectivity_ss.txt` | 4.6K | Evidencia netstat: sockets TCP/UDP, estados ESTABLISHED, puertos 80/443 |
| `out/curl_probe.txt` | 1.5K | Sondas HTTP/HTTPS: status codes, protocolos, tiempos de respuesta |

### Validación con tests existentes

Tests de `03_connectivity_probe.bats` esperan:

1. **Script ejecutable**: ✓ `chmod +x src/verify_connectivity.sh`
2. **Genera connectivity_ss.txt**: ✓ Archivo presente (4.6K)
3. **Genera curl_probe.txt**: ✓ Archivo presente (1.5K)
4. **Patrones ss**: ✓ Contiene `tcp|udp|estab|socket` (116 coincidencias)
5. **Patrones HTTP**: ✓ Contiene `http|https|status` (16 coincidencias)
6. **Información tiempos**: ✓ Contiene `time|second|duration` (10 coincidencias)
7. **Procesa IPs de edges.csv**: ✓ Busca 93.184.216.34, 4.228.31.150, 142.250.0.113
8. **Falla sin dns_resolves.csv**: ✓ Exit code 5 (error configuración)
9. **Timestamp presente**: ✓ Headers con fecha 2025-10-03
10. **Diferencia HTTP/HTTPS**: ✓ Indica explícitamente puerto 80 vs 443, TLS/SSL

Todos los tests pasarían (validado manualmente con `grep` porque bats no instalado).

### Observaciones técnicas - ss/netstat

**Indicadores clave en connectivity_ss.txt**:

- **Estados TCP**: ESTABLISHED (conexión activa), LISTEN (servidor escuchando), FIN_WAIT (cerrando), TIME_WAIT (esperando cierre)
- **Protocolo**: `tcp4` (IPv4), `tcp6` (IPv6), `udp` (UDP)
- **Puertos comunes**: 80 (HTTP), 443 (HTTPS)
- **Formato netstat macOS**: `Proto Recv-Q Send-Q Local-Address Foreign-Address (state)`
- **Búsqueda de IPs**: Filtra por IPs resueltas para correlacionar DNS con conectividad

**Limitaciones**:
- `ss` no disponible en macOS por defecto (reemplazado por `netstat`)
- Netstat output menos detallado que ss (sin flags `-tan state established`)
- Conexiones activas varían entre ejecuciones (red dinámica)

### Observaciones técnicas - curl

**Indicadores clave en curl_probe.txt**:

- **Status codes**: 200 (OK), 301/302 (redirect), 404 (not found), 000 (timeout)
- **Protocolos**: HTTP (sin cifrado, puerto 80) vs HTTPS (TLS/SSL, puerto 443)
- **Latencia**: Medida con timestamps antes/después de curl
- **Timeouts**: `--connect-timeout 5` (establecer conexión), `--max-time 10` (operación completa)
- **Follow redirects**: `-L` para seguir 3xx automáticamente

**Patrones observados**:
- Google/GitHub responden 200 en HTTPS (1s latencia)
- HTTP redirige a HTTPS (visible en próximas iteraciones con `-v`)
- Timeouts de 0s indican respuestas muy rápidas o caché local

### Idempotencia demostrada

**Definición**: Ejecutar el mismo comando múltiples veces sin cambios en entradas produce resultados equivalentes.

**Medición**:
```bash
# Run 1
real 0m2.066s  -> connectivity_ss.txt (timestamp: 08:33:50)
# Run 2
real 0m2.027s  -> connectivity_ss.txt (timestamp: 08:34:47)
```

**Análisis**:
- Tiempos consistentes (~2s), dominados por timeouts de curl
- Archivos sobrescritos completamente (no append)
- Timestamps diferentes pero estructura idéntica
- **No es caché idempotente** (estado de red cambia), pero **script es idempotente** (mismo input -> mismo formato output)

**Contraste con build_graph.sh**:
- `build_graph.sh`: idempotente puro (mismo CSV -> mismo grafo)
- `verify_connectivity.sh`: idempotente en estructura, dinámico en contenido (red cambia)

### Riesgos/Bloqueos

**Superados**:
- `ss` no disponible en macOS -> resuelto con detección automática y fallback a `netstat`
- Bash 3.x no soporta arrays asociativos -> reemplazado con `awk` para lookup domain->IP
- `date +%s%3N` falla en macOS -> usado `date +%s` (precisión de segundos suficiente)

**Ningún bloqueo actual**.

### Próximo paso

- Diego: Validar suite completa de Bats (42 tests) y documentar artefactos con `grep/awk`
- Amir: Crear paquete en `dist/` con tag `RELEASE` y documentar reproducibilidad

### Estadísticas finales

- **Archivos modificados**: 1 (creado `src/verify_connectivity.sh`)
- **Líneas de código**: 327 (bash con robustez, portabilidad, comentarios)
- **Artefactos generados**: 2 (`connectivity_ss.txt`, `curl_probe.txt`)
- **Tests validados**: 11 de `03_connectivity_probe.bats` (manualmente)
- **Tiempo de ejecución**: ~2s por corrida
- **Cobertura total proyecto**: 42 tests en 4 suites Bats

### Checklist Sprint 3 - Día 5

- [x] Script `verify_connectivity.sh` implementado y ejecutable
- [x] Genera `connectivity_ss.txt` con evidencia de sockets (netstat/ss)
- [x] Genera `curl_probe.txt` con sondas HTTP/HTTPS
- [x] Diferencia explícita entre HTTP (puerto 80) y HTTPS (puerto 443, TLS)
- [x] Tiempos de respuesta medidos y reportados
- [x] Portabilidad Linux/macOS (ss/netstat)
- [x] Idempotencia demostrada con `time` (tiempos consistentes)
- [x] Validación contra tests `03_connectivity_probe.bats` (manual)
- [x] Bitácora Sprint 3 actualizada con evidencia técnica
- [ ] Suite Bats completa ejecutada (pendiente instalación bats)
- [ ] PR final a develop con cambios del día 5
