#!/bin/bash

# build_graph.sh - Construcción de grafo de dependencias DNS
# Autor: Diego Orrego
# Fecha: 2025-10-01
#
# Descripción:
#   Lee el CSV de resoluciones DNS (dns_resolves.csv) y genera:
#   1. Edge list (edges.csv): pares origen->destino con tipo de relación
#   2. Reporte de profundidad (depth_report.txt): métricas de profundidad del grafo
#
# Entrada:
#   - out/dns_resolves.csv (generado por resolve_dns.sh)
#
# Salida:
#   - out/edges.csv: formato "from,to,kind" donde kind ∈ {CNAME,A}
#   - out/depth_report.txt: profundidad máxima y promedio
#   - out/cycles_report.txt: detección de ciclos CNAME
#
# Reglas:
#   - NO consulta red, solo post-procesa CSV (respeta separación C-L-E)
#   - Salida determinista y reproducible

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Configuración
readonly INPUT_CSV="${OUT_DIR:-out}/dns_resolves.csv"
readonly OUTPUT_EDGES="${OUT_DIR:-out}/edges.csv"
readonly OUTPUT_DEPTH="${OUT_DIR:-out}/depth_report.txt"
readonly OUTPUT_CYCLES="${OUT_DIR:-out}/cycles_report.txt"

# Validaciones de entrada
validate_input() {
    log "INFO" "Validando archivo de entrada: ${INPUT_CSV}"

    if [[ ! -f "$INPUT_CSV" ]]; then
        log "ERROR" "Archivo de entrada no encontrado: ${INPUT_CSV}"
        log "ERROR" "Ejecuta 'make build' primero para generar dns_resolves.csv"
        exit $EXIT_CONFIG_ERROR
    fi

    if [[ ! -r "$INPUT_CSV" ]]; then
        log "ERROR" "Archivo de entrada no legible: ${INPUT_CSV}"
        exit $EXIT_CONFIG_ERROR
    fi

    # Verificar que el CSV tiene al menos el header
    local line_count
    line_count=$(wc -l < "$INPUT_CSV")
    if [[ $line_count -lt 2 ]]; then
        log "ERROR" "CSV vacío o solo contiene header: ${INPUT_CSV}"
        exit $EXIT_CONFIG_ERROR
    fi

    log "INFO" "Validación completada: ${line_count} líneas encontradas"
}

# Genera el edge list a partir del CSV de resoluciones DNS
#
# Lógica de construcción de aristas:
#   - Para registros A: source -> target (tipo A)
#   - Para registros CNAME: source -> target (tipo CNAME)
#
# El grafo resultante muestra las dependencias:
#   dominio_origen -> CNAME1 -> CNAME2 -> IP_final
generate_edges() {
    log "INFO" "Generando edge list desde ${INPUT_CSV}"

    # Crear archivo con header
    echo "from,to,kind" > "$OUTPUT_EDGES"

    # Procesar cada línea del CSV (saltando header)
    # Formato: source,record_type,target,ttl,trace_ts
    awk -F',' '
    BEGIN {
        # Contadores para estadísticas
        a_records = 0
        cname_records = 0
    }

    NR > 1 {
        # Saltar líneas vacías
        if (NF < 3) next

        source = $1
        record_type = $2
        target = $3

        # Normalizar: eliminar espacios
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", source)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", target)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", record_type)

        # Validar que tengamos datos válidos
        if (source == "" || target == "" || record_type == "") {
            next
        }

        # Generar arista: from,to,kind
        print source "," target "," record_type

        # Actualizar contadores
        if (record_type == "A") {
            a_records++
        } else if (record_type == "CNAME") {
            cname_records++
        }
    }

    END {
        # Escribir estadísticas a stderr para logging
        print "Aristas generadas - A: " a_records ", CNAME: " cname_records > "/dev/stderr"
    }
    ' "$INPUT_CSV" >> "$OUTPUT_EDGES"

    local edge_count
    edge_count=$(($(wc -l < "$OUTPUT_EDGES") - 1))
    log "INFO" "Edge list generado: ${edge_count} aristas en ${OUTPUT_EDGES}"
}

# Calcula la profundidad del grafo de dependencias
#
# Profundidad de un nodo = número de saltos desde el origen hasta llegar a un registro A
#
# Ejemplo:
#   ejemplo.com -> cname1.com -> cname2.com -> 1.2.3.4
#   Profundidad: 3 (3 aristas)
#
# Métricas calculadas:
#   - Profundidad máxima: la cadena más larga
#   - Profundidad promedio: promedio de todas las cadenas
calculate_depth() {
    log "INFO" "Calculando profundidad del grafo"

    # Algoritmo simplificado:
    # Contar aristas por cada origen único
    # Para dominios con solo registros A directos, profundidad = 1
    # Para cadenas CNAME, contar los saltos

    # Usar archivo temporal para resultados de awk
    local temp_metrics
    temp_metrics=$(create_temp_file)

    # Analizar el edge list usando awk
    awk -F',' '
    BEGIN {
        max_depth = 0
        total_depth = 0
        chain_count = 0
    }

    NR > 1 {
        # Contar aristas por origen
        origin = $1
        kind = $3

        # Para cada arista, contar como profundidad 1
        origins[origin]++

        # Si es tipo A, es una cadena completa
        if (kind == "A") {
            depth = origins[origin]
            if (depth > max_depth) {
                max_depth = depth
            }
            total_depth += depth
            chain_count++
        }
    }

    END {
        avg_depth = (chain_count > 0) ? total_depth / chain_count : 0
        printf "%d %.2f %d\n", max_depth, avg_depth, chain_count
    }
    ' "$OUTPUT_EDGES" > "$temp_metrics"

    # Leer resultados
    read -r max_depth avg_depth chain_count < "$temp_metrics" || {
        log "ERROR" "No se pudo calcular profundidad"
        max_depth=0
        avg_depth="0.00"
        chain_count=0
    }

    # Generar reporte
    {
        echo "==================================================================="
        echo "Reporte de Profundidad del Grafo DNS"
        echo "==================================================================="
        echo ""
        echo "Generado: $(date +'%Y-%m-%d %H:%M:%S')"
        echo "Entrada: ${INPUT_CSV}"
        echo ""
        echo "Métricas:"
        echo "  - Cadenas analizadas: ${chain_count}"
        echo "  - Profundidad máxima: ${max_depth}"
        echo "  - Profundidad promedio: ${avg_depth}"
        echo ""
        echo "Definición:"
        echo "  Profundidad = número de saltos desde dominio origen hasta registro A final"
        echo ""
        echo "Ejemplo:"
        echo "  ejemplo.com -> cname1.com -> cname2.com -> 1.2.3.4"
        echo "  Profundidad: 3 (3 aristas en la cadena)"
        echo ""
        echo "Nota:"
        echo "  Para dominios con resolución A directa (sin CNAMEs), profundidad = 1"
        echo ""
        echo "==================================================================="
    } > "$OUTPUT_DEPTH"

    log "INFO" "Reporte de profundidad generado: ${OUTPUT_DEPTH}"
    log "INFO" "Profundidad máxima: ${max_depth}, promedio: ${avg_depth}"
}

# Detecta ciclos en cadenas CNAME
detect_cycles() {
    log "INFO" "Detectando ciclos en cadenas CNAME"

    # Usar archivo temporal para análisis
    local temp_cnames
    temp_cnames=$(create_temp_file)

    # Extraer solo aristas CNAME
    awk -F',' 'NR > 1 && $3 == "CNAME" {print $1 "," $2}' "$OUTPUT_EDGES" > "$temp_cnames"

    # Generar reporte base
    {
        echo "==================================================================="
        echo "Reporte de Detección de Ciclos DNS"
        echo "==================================================================="
        echo ""
        echo "Generado: $(date +'%Y-%m-%d %H:%M:%S')"
        echo "Entrada: ${OUTPUT_EDGES}"
        echo ""
        echo "Análisis de cadenas CNAME:"
        echo ""
    } > "$OUTPUT_CYCLES"

    # Verificar si hay aristas CNAME para analizar
    local cname_count
    cname_count=$(wc -l < "$temp_cnames")
    
    if [[ $cname_count -eq 0 ]]; then
        {
            echo "No se encontraron registros CNAME en el grafo."
            echo "Sin posibilidad de ciclos CNAME."
            echo ""
            echo "Estado: SIN CICLOS"
            echo ""
            echo "==================================================================="
        } >> "$OUTPUT_CYCLES"
        log "INFO" "No hay registros CNAME - sin posibilidad de ciclos"
        return 0
    fi

    # Algoritmo de detección de ciclos usando awk
    awk -F',' '
    BEGIN {
        cycles_found = 0
    }

    {
        # Construir mapa from -> to para CNAMEs
        cname_map[$1] = $2
        sources[$1] = 1
    }

    END {
        print "" >> output_file
        
        # Para cada nodo origen, seguir la cadena
        for (start in sources) {
            visited_count = 0
            delete visited
            current = start
            
            # Seguir cadena hasta encontrar ciclo o final
            while (current in cname_map) {
                if (current in visited) {
                    # Ciclo detectado
                    cycle_nodes = ""
                    for (node in visited) {
                        cycle_nodes = cycle_nodes node " "
                    }
                    cycle_nodes = cycle_nodes current
                    
                    print "CYCLE DETECTADO:" >> output_file
                    print "  Nodos involucrados: " cycle_nodes >> output_file
                    print "  Inicio del ciclo: " current >> output_file
                    print "" >> output_file
                    cycles_found++
                    break
                }
                
                visited[current] = 1
                visited_count++
                current = cname_map[current]
                
                # Prevenir bucles infinitos
                if (visited_count > 10) {
                    print "POSIBLE CICLO LARGO en cadena iniciada en: " start >> output_file
                    print "  (Cadena truncada por límite de seguridad)" >> output_file
                    print "" >> output_file
                    cycles_found++
                    break
                }
            }
        }
        
        # Resumen final
        if (cycles_found > 0) {
            print "Estado: CICLOS ENCONTRADOS (" cycles_found ")" >> output_file
            print "Acción recomendada: Revisar configuración DNS" >> output_file
        } else {
            print "Estado: SIN CICLOS" >> output_file
            print "Todas las cadenas CNAME terminan correctamente" >> output_file
        }
        
        print "" >> output_file
        print "===================================================================" >> output_file
        
        # Log para build_graph.sh
        print "Ciclos detectados: " cycles_found > "/dev/stderr"
    }
    ' output_file="$OUTPUT_CYCLES" "$temp_cnames" 2>&1 | while read -r line; do
        log "INFO" "$line"
    done

    log "INFO" "Reporte de ciclos generado: ${OUTPUT_CYCLES}"
}

# Función principal
main() {
    log "INFO" "Iniciando construcción de grafo DNS"

    # Asegurar que existe el directorio de salida
    ensure_directory "${OUT_DIR:-out}"

    # Paso 1: Validar entrada
    validate_input

    # Paso 2: Generar edge list
    generate_edges

    # Paso 3: Calcular profundidad
    calculate_depth

    # Paso 4: Detectar ciclos
    detect_cycles

    log "INFO" "Construcción de grafo completada exitosamente"
    log "INFO" "Salidas generadas:"
    log "INFO" "  - ${OUTPUT_EDGES}"
    log "INFO" "  - ${OUTPUT_DEPTH}"
    log "INFO" "  - ${OUTPUT_CYCLES}"

    exit $EXIT_SUCCESS
}

# Ejecutar si se invoca directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
