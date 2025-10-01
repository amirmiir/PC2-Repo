# Proyecto DNS - Mapa de Dependencias con Detección de Ciclos

Sistema de resolución y análisis de dependencias DNS que construye un grafo de relaciones A/CNAME, detecta ciclos, reporta TTLs y verifica conectividad mediante sondas HTTP/HTTPS.

---

## Descripción General

Este proyecto implementa un pipeline automatizado para:

- Resolver registros DNS (A/CNAME) mediante `dig`
- Construir un grafo de dependencias entre dominios
- Detectar ciclos y encadenamientos excesivos de CNAME
- Reportar valores de TTL (Time To Live)
- Verificar conectividad a IPs finales mediante `ss`
- Realizar sondas HTTP/HTTPS con `curl`

Todo el flujo está orquestado mediante **Make** (12-Factor I/III/V), siguiendo el principio de **Configurar-Lanzar-Ejecutar**, y cuenta con una suite completa de pruebas automatizadas con **Bats** (metodología AAA/RGR).

---

## Requisitos del Sistema

### Herramientas Requeridas

El proyecto requiere las siguientes utilidades instaladas en el sistema:

- `dig` - Consultas DNS
- `curl` - Sondas HTTP/HTTPS
- `ss` - Verificación de sockets/conectividad
- `awk` - Procesamiento de texto
- `sed` - Transformación de texto
- `sort` - Ordenamiento
- `uniq` - Eliminación de duplicados
- `tee` - Duplicación de flujos
- `find` - Búsqueda de archivos
- `bats` - Framework de testing (opcional para tests)

Para verificar que todas las herramientas estén disponibles:

```bash
make tools
```

---

## Variables de Entorno

El proyecto sigue la metodología **12-Factor (Factor III)** y es completamente configurable mediante variables de entorno, sin necesidad de modificar código.

### Tabla de Variables y Efectos Observables

| Variable | Obligatoria | Valor por Defecto | Efecto Observable | Evidencia |
|----------|-------------|-------------------|-------------------|-----------|
| `DOMAINS_FILE` | ✓ Sí | `DOMAINS.sample.txt` | Especifica la ruta del archivo con lista de dominios (uno por línea). El script lee este archivo para determinar qué dominios resolver. | Verificable con `wc -l "$DOMAINS_FILE"` y en logs de ejecución |
| `DNS_SERVER` | No | `1.1.1.1` | Define el servidor DNS a consultar. Aparece como `@${DNS_SERVER}` en las consultas `dig`. Permite probar contra diferentes resolvers (ej: `8.8.8.8`, `208.67.222.222`). | Visible en trazas de `dig` con `dig @${DNS_SERVER} ...` en `out/` |
| `RELEASE` | No | `0.1.0` | Etiqueta de versión para el empaquetado en `dist/`. Determina el nombre del archivo `.tar.gz` generado. | Nombre del paquete: `dist/proyecto12-v${RELEASE}.tar.gz` |
| `MAX_DEPTH` | No | `10` (futuro) | Límite de profundidad para cadenas CNAME. Previene loops infinitos y encadenamientos excesivos. | Reportado en `out/cycles_report.txt` y logs de error cuando se excede |
| `BUDGET_MS` | No | `5000` (futuro) | Umbral en milisegundos para sondas `curl`. Marca como ALERTA o FALLO si se supera el tiempo. | Anotaciones en `out/curl_probe.txt` indicando si se superó el límite |

### Ejemplos de Uso

```bash
# Usar archivo de dominios personalizado
DOMAINS_FILE=mis_dominios.txt make build

# Cambiar servidor DNS
DNS_SERVER=8.8.8.8 make run

# Especificar versión de release
RELEASE=1.0.0 make pack

# Combinar múltiples variables
DOMAINS_FILE=prod.txt DNS_SERVER=1.1.1.1 MAX_DEPTH=15 make run
```

---

## Estructura del Proyecto

```
proyecto12-dns-grafo/
├── src/                          # Scripts Bash (en español, comentados)
│   ├── resolve_dns.sh            # Resolución DNS → CSV con A/CNAME+TTL
│   ├── build_graph.sh            # Construcción de grafo y detección de ciclos (Sprint 2)
│   ├── verify_connectivity.sh    # Verificación ss + sonda curl (Sprint 2)
│   └── common.sh                 # Helpers compartidos, set -euo pipefail, trap
├── tests/                        # Suite de pruebas Bats (AAA/RGR)
│   ├── 01_resolve_basic.bats     # Pruebas de resolución básica
│   ├── 02_cycles_and_depth.bats  # Pruebas de ciclos y profundidad (Sprint 2)
│   ├── 03_connectivity_probe.bats # Pruebas de conectividad (Sprint 2)
│   └── 04_env_contracts.bats     # Validación de contratos de variables (Sprint 3)
├── docs/                         # Documentación y bitácoras
│   ├── README.md                 # Este archivo
│   ├── contrato-salidas.md       # Contrato formal de archivos generados
│   ├── bitacora-sprint-1.md      # Registro Sprint 1
│   ├── bitacora-sprint-2.md      # Registro Sprint 2 (futuro)
│   └── bitacora-sprint-3.md      # Registro Sprint 3 (futuro)
├── out/                          # Artefactos y evidencias generadas
│   ├── dns_resolves.csv          # Resoluciones normalizadas
│   ├── edges.csv                 # Edge-list del grafo (Sprint 2)
│   ├── depth_report.txt          # Reporte de profundidad (Sprint 2)
│   ├── cycles_report.txt         # Detección de ciclos (Sprint 2)
│   ├── connectivity_ss.txt       # Evidencia de ss (Sprint 2)
│   └── curl_probe.txt            # Evidencia de curl (Sprint 2)
├── dist/                         # Paquetes reproducibles
│   └── proyecto12-v*.tar.gz      # Paquete etiquetado por RELEASE (Sprint 3)
├── Makefile                      # Orquestación (tools, build, test, run, pack, clean, help)
├── DOMAINS.sample.txt            # Archivo de ejemplo con dominios
└── README.md                     # Documentación raíz
```

---

## Uso del Makefile

El proyecto se controla completamente mediante `make`. Todos los targets principales están disponibles:

### Targets Disponibles

#### `make help`
Muestra ayuda detallada de todos los targets y variables configurables.

```bash
make help
```

#### `make tools`
Verifica que todas las herramientas requeridas estén instaladas. Falla con mensajes claros si falta alguna utilidad.

```bash
make tools
```

**Efecto:** Lista todas las herramientas requeridas y sus rutas. Sale con código ≠ 0 si falta alguna.

#### `make build`
**Fase: Configurar** (Configurar-Lanzar-Ejecutar)

Genera artefactos intermedios en `out/` **sin ejecutar** el proyecto completo. Solo transforma entradas en salidas (resolución DNS → CSV).

```bash
make build
```

**Efecto:** Crea `out/dns_resolves.csv` con resoluciones normalizadas. No ejecuta verificaciones de conectividad ni sondas.

#### `make test`
Ejecuta la suite completa de pruebas Bats y muestra resultados consolidados.

```bash
make test
```

**Efecto:** Corre todos los archivos `.bats` en `tests/` y reporta casos pasados/fallidos.

#### `make run`
**Fase: Ejecutar** (Configurar-Lanzar-Ejecutar)

Ejecuta el flujo completo del proyecto: resolución, construcción de grafo, detección de ciclos y verificación de conectividad.

```bash
make run
```

**Efecto:** Genera todos los artefactos en `out/` incluyendo grafos, reportes de ciclos y sondas HTTP/HTTPS (sprints 2-3).

#### `make pack`
Crea un paquete reproducible en `dist/` etiquetado con `RELEASE`.

```bash
RELEASE=1.0.0 make pack
```

**Efecto:** Genera `dist/proyecto12-v1.0.0.tar.gz` con todo el código fuente y artefactos (Sprint 3).

#### `make clean`
Limpia archivos generados en `out/` y `dist/` de forma segura.

```bash
make clean
```

**Efecto:** Elimina contenido de `out/` y `dist/` sin afectar código fuente.

---

## Flujo de Trabajo Típico

### 1. Verificar Herramientas
```bash
make tools
```

### 2. Generar Artefactos (sin ejecutar todo)
```bash
DOMAINS_FILE=DOMAINS.sample.txt make build
```

### 3. Ejecutar Pruebas
```bash
make test
```

### 4. Ejecutar Flujo Completo
```bash
DNS_SERVER=1.1.1.1 make run
```

### 5. Inspeccionar Resultados
```bash
ls -lh out/
cat out/dns_resolves.csv
```

### 6. Empaquetar Proyecto
```bash
RELEASE=1.0.0 make pack
```

---

## Contrato de Salidas

Consultar **`docs/contrato-salidas.md`** para detalles sobre:

- Formatos exactos de archivos generados
- Comandos de validación con `awk/grep`
- Estructura de CSVs y reportes
- Códigos de salida y manejo de errores

---

## Pruebas Automatizadas

El proyecto utiliza **Bats** (Bash Automated Testing System) con metodología **AAA (Arrange-Act-Assert)** y **RGR (Rojo-Verde-Refactor)**.

### Ejecutar Suite Completa
```bash
make test
```

### Ejecutar Test Específico
```bash
bats tests/01_resolve_basic.bats
```

### Cobertura de Pruebas
- ✓ Resolución DNS básica (A/CNAME)
- ✓ Casos negativos (NXDOMAIN, dominios inválidos)
- ✓ Parseo de TTL
- ✓ Detección de ciclos (Sprint 2)
- ✓ Verificación de conectividad (Sprint 2)
- ✓ Contratos de variables de entorno (Sprint 3)

---

## Códigos de Salida

Los scripts utilizan códigos de salida consistentes para facilitar debugging:

| Código | Significado |
|--------|-------------|
| `0` | Éxito |
| `1` | Error genérico |
| `3` | Error de DNS (NXDOMAIN, timeout) |
| `4` | Error HTTP/conectividad |
| `5` | Error de configuración (variables faltantes, archivos inválidos) |

---

## Desarrollo y Contribución

### Ramas
- `main` - Rama principal estable
- `develop` - Rama de integración
- `features/*` - Ramas de features por alumno

### Commits
Todos los commits deben ser:
- **En español**
- **Descriptivos** (evitar "update", "wip", "fix")
- **Pequeños y enfocados** (cambios atómicos)

### Pull Requests
Cada PR debe incluir:
- Descripción de qué/por qué/cómo
- Evidencias de ejecución (fragmentos de `out/`)
- Checklist de revisión

---

## Equipo

- **Amir Canto** (40%) - Pipeline DNS + Grafo
- **Melissa Iman** (30%) - Pruebas Bats + Documentación
- **Diego Orrego** (30%) - Make + Variables de entorno + Conectividad