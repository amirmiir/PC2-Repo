#!/bin/bash

# resolve_dns.sh - Resolución DNS A/CNAME para construcción de grafo de dependencias
# Autor: Amir
# Fecha: 2025-09-30
#
# Entrada por entorno:
#   DOMAINS_FILE: ruta al archivo con dominios (uno por línea) - OBLIGATORIO
#   DNS_SERVER: servidor DNS a consultar (opcional, por defecto usa el del sistema)
#
# Salida:
#   out/dns_resolves.csv con formato: source,record_type,target,ttl,trace_ts
#   - source: dominio consultado (normalizado, sin punto final)
#   - record_type: tipo de registro (A o CNAME)
#   - target: destino de la resolución (IP para A, dominio para CNAME)
#   - ttl: tiempo de vida en segundos
#   - trace_ts: timestamp de la consulta (epoch)
#
# Códigos de salida:
#   0: SUCCESS - Al menos un dominio se resolvió exitosamente
#   3: DNS_ERROR - No se pudo resolver ningún dominio (fallo crítico)
#   5: CONFIG_ERROR - Error de configuración (DOMAINS_FILE inválido/faltante)
#
# Comportamiento de errores:
#   - Dominios individuales que fallan se registran como WARN pero no detienen la ejecución
#   - Solo se retorna código ≠ 0 si TODOS los dominios fallan o hay error de configuración
#   - Dominios con formato inválido se ignoran (logged como WARN)
#
# Algoritmos implementados:
# - NORMALIZACIÓN: Dominios a minúsculas, sin puntos finales DNS
# - DEDUPLICACIÓN: Por source,record_type,target - mantiene TTL menor (más fresco)
# - TOLERANCIA A FALLOS: Continúa si algunos dominios fallan, solo falla si todos fallan

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Verificar dependencias
check_dependency "dig"

# Verificar variables de entorno obligatorias con validación robusta
if [[ -z "${DOMAINS_FILE:-}" ]]; then
    log "ERROR" "Variable DOMAINS_FILE es obligatoria pero no está definida"
    log "ERROR" "Uso: DOMAINS_FILE=archivo.txt $0"
    exit $EXIT_CONFIG_ERROR
fi

# Validar archivo de dominios con verificación detallada
if [[ ! -f "$DOMAINS_FILE" ]]; then
    log "ERROR" "Archivo de dominios no encontrado: $DOMAINS_FILE"
    exit $EXIT_CONFIG_ERROR
fi

if [[ ! -r "$DOMAINS_FILE" ]]; then
    log "ERROR" "Archivo de dominios no es legible: $DOMAINS_FILE"
    log "ERROR" "Verificar permisos de lectura"
    exit $EXIT_CONFIG_ERROR
fi

# Verificar que el archivo no esté vacío
if [[ ! -s "$DOMAINS_FILE" ]]; then
    log "ERROR" "Archivo de dominios está vacío: $DOMAINS_FILE"
    exit $EXIT_CONFIG_ERROR
fi

log "INFO" "Archivo de dominios validado: $DOMAINS_FILE"

# Configurar servidor DNS si se especifica
DNS_ARGS=()
if [[ -n "${DNS_SERVER:-}" ]]; then
    DNS_ARGS=("@$DNS_SERVER")
    log "INFO" "Usando servidor DNS: $DNS_SERVER"
fi

# Asegurar directorio de salida
ensure_directory "out"

# Archivo de salida
readonly OUTPUT_FILE="out/dns_resolves.csv"

# Función para deduplicar registros manteniendo TTL más reciente
# Deduplicación: misma combinación source,record_type,target mantiene TTL menor (más fresco)
deduplicate_csv() {
    local input_file="$1"
    local temp_file
    temp_file=$(create_temp_file)
    
    # Mantener encabezado
    head -1 "$input_file" > "$temp_file"
    
    # Procesar registros eliminando duplicados por source,record_type,target
    awk -F, '
    NR>1 {
        key = $1","$2","$3
        if (!(key in seen) || $4 < ttl[key]) {
            records[key] = $0
            ttl[key] = $4
            seen[key] = 1
        }
    }
    END {
        for (key in records) {
            print records[key]
        }
    }' "$input_file" | sort >> "$temp_file"
    
    mv "$temp_file" "$input_file"
    log "INFO" "Deduplicación completada"
}

# Función para resolver un dominio y extraer información
# Retorna: 0 si se resuelve exitosamente, 1 si hay error pero no crítico, 3 si error DNS crítico
resolve_domain() {
    local domain="$1"
    local timestamp
    timestamp=$(date +%s)
    
    # Validar formato básico del dominio
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        log "WARN" "Dominio con formato inválido ignorado: $domain"
        return 1  # Error no crítico - continuar con otros dominios
    fi
    
    log "INFO" "Resolviendo dominio: $domain"
    
    # Crear archivo temporal para la salida de dig
    local temp_output
    temp_output=$(create_temp_file)
    
    # Ejecutar dig para obtener registros A y CNAME (separadamente para evitar conflictos)
    # Primero buscar registros A
    if [[ ${#DNS_ARGS[@]} -gt 0 ]]; then
        dig "${DNS_ARGS[@]}" +noall +answer "$domain" A > "$temp_output" 2>/dev/null || true
        dig "${DNS_ARGS[@]}" +noall +answer "$domain" CNAME >> "$temp_output" 2>/dev/null || true
    else
        dig +noall +answer "$domain" A > "$temp_output" 2>/dev/null || true
        dig +noall +answer "$domain" CNAME >> "$temp_output" 2>/dev/null || true
    fi
    
    log "INFO" "Consultas DNS completadas para: $domain"
    
    # Verificar si hay resultados en el archivo temporal
    local records_found=0
    
    # Procesar la salida de dig
    while IFS= read -r line; do
        # Ignorar líneas vacías o comentarios
        [[ -n "$line" && ! "$line" =~ ^[[:space:]]*$ ]] || continue
        
        # Extraer campos: dominio, TTL, clase, tipo, target
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+([0-9]+)[[:space:]]+IN[[:space:]]+([A-Z]+)[[:space:]]+(.+)$ ]]; then
            local source="${BASH_REMATCH[1]}"
            local ttl="${BASH_REMATCH[2]}"
            local record_type="${BASH_REMATCH[3]}"
            local target="${BASH_REMATCH[4]}"
            
            # NORMALIZACIÓN EXPLÍCITA:
            # 1. Remover punto final DNS (ejemplo.com. -> ejemplo.com)
            # 2. Convertir a minúsculas para consistencia
            # 3. Mantener formato original de IPs (no normalizar A records)
            source="${source%.}"          # Remover punto final
            source="${source,,}"          # Convertir a minúsculas
            target="${target%.}"          # Remover punto final del target
            if [[ "$record_type" == "CNAME" ]]; then
                target="${target,,}"      # Solo normalizar CNAME targets
            fi
            
            # Solo procesar registros A y CNAME
            if [[ "$record_type" == "A" || "$record_type" == "CNAME" ]]; then
                echo "$source,$record_type,$target,$ttl,$timestamp"
                log "INFO" "Registro encontrado: $source -> $record_type -> $target (TTL: $ttl)"
                ((records_found++))
            fi
        fi
    done < "$temp_output"
    
    # Verificar si se encontraron registros para este dominio
    if [[ $records_found -eq 0 ]]; then
        log "WARN" "No se encontraron registros A/CNAME para: $domain"
        return 1  # Error no crítico - continuar con otros dominios
    fi
    
    return 0
}

# Función principal
main() {
    log "INFO" "Iniciando resolución DNS para dominios en: $DOMAINS_FILE"
    
    # Crear encabezado del CSV
    echo "source,record_type,target,ttl,trace_ts" > "$OUTPUT_FILE"
    
    local domain_count=0
    local resolved_count=0
    
    # Procesar cada dominio del archivo
    # Deshabilitar set -e temporalmente para permitir que algunos dominios fallen sin detener el script
    set +e
    while IFS= read -r domain; do
        # Ignorar líneas vacías y comentarios
        [[ -n "$domain" && ! "$domain" =~ ^[[:space:]]*# ]] || continue

        # Limpiar espacios en blanco
        domain=$(echo "$domain" | tr -d '[:space:]')
        [[ -n "$domain" ]] || continue

        ((domain_count++))

        # Resolver dominio y agregar al CSV
        local lines_before
        lines_before=$(wc -l < "$OUTPUT_FILE")

        resolve_domain "$domain" >> "$OUTPUT_FILE"

        # Verificar si se agregaron líneas al CSV
        local lines_after
        lines_after=$(wc -l < "$OUTPUT_FILE")
        if [[ $lines_after -gt $lines_before ]]; then
            ((resolved_count++))
        fi

    done < "$DOMAINS_FILE"
    # Reactivar set -e
    set -e
    
    log "INFO" "Procesamiento completado: $resolved_count/$domain_count dominios resueltos"
    
    # Aplicar deduplicación al CSV final
    log "INFO" "Aplicando deduplicación de registros..."
    deduplicate_csv "$OUTPUT_FILE"
    
    log "INFO" "Resultados guardados en: $OUTPUT_FILE"
    
    # Verificar que se generó al menos una resolución válida
    local line_count
    line_count=$(wc -l < "$OUTPUT_FILE")
    
    # Solo fallar si NO se resolvió ningún dominio (todos fallaron)
    if [[ "$line_count" -le 1 ]]; then
        log "ERROR" "FALLO CRÍTICO: No se pudieron resolver ninguno de los $domain_count dominios"
        log "ERROR" "Verificar conectividad de red y validez de los dominios"
        exit $EXIT_DNS_ERROR
    fi
    
    # Si algunos dominios fallaron pero al menos uno se resolvió, continuar
    if [[ $resolved_count -lt $domain_count ]]; then
        local failed_count=$((domain_count - resolved_count))
        log "WARN" "Se resolvieron $resolved_count de $domain_count dominios ($failed_count fallaron)"
        log "WARN" "Continuando con los dominios exitosos"
    fi
    
    log "INFO" "CSV generado exitosamente con $((line_count - 1)) registros DNS"
}

# Ejecutar función principal si el script se ejecuta directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi