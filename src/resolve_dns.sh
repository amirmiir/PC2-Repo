#!/bin/bash

# resolve_dns.sh - Resolución DNS A/CNAME para construcción de grafo de dependencias
# Autor: Amir
# Fecha: 2025-09-30
#
# Entrada por entorno:
#   DOMAINS_FILE: ruta al archivo con dominios (uno por línea)
#   DNS_SERVER: servidor DNS a consultar (opcional, por defecto usa el del sistema)
#
# Salida:
#   out/dns_resolves.csv con formato: source,record_type,target,ttl,trace_ts
#   - source: dominio consultado
#   - record_type: tipo de registro (A o CNAME)
#   - target: destino de la resolución (IP para A, dominio para CNAME)
#   - ttl: tiempo de vida en segundos
#   - trace_ts: timestamp de la consulta (epoch)

# Cargar utilidades comunes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Verificar dependencias
check_dependency "dig"

# Verificar variables de entorno obligatorias
if [[ -z "${DOMAINS_FILE:-}" ]]; then
    log "ERROR" "Variable DOMAINS_FILE es obligatoria"
    exit $EXIT_CONFIG_ERROR
fi

# Validar archivo de dominios
validate_file "$DOMAINS_FILE"

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

# Función para resolver un dominio y extraer información
resolve_domain() {
    local domain="$1"
    local timestamp
    timestamp=$(date +%s)
    
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
            
            # Normalizar el source (remover punto final si existe)
            source="${source%.}"
            target="${target%.}"
            
            # Solo procesar registros A y CNAME
            if [[ "$record_type" == "A" || "$record_type" == "CNAME" ]]; then
                echo "$source,$record_type,$target,$ttl,$timestamp"
                log "INFO" "Registro encontrado: $source -> $record_type -> $target (TTL: $ttl)"
            fi
        fi
    done < "$temp_output"
    
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
    while IFS= read -r domain; do
        # Ignorar líneas vacías y comentarios
        [[ -n "$domain" && ! "$domain" =~ ^[[:space:]]*# ]] || continue
        
        # Limpiar espacios en blanco
        domain=$(echo "$domain" | tr -d '[:space:]')
        [[ -n "$domain" ]] || continue
        
        ((domain_count++))
        
        # Resolver dominio y agregar al CSV
        resolve_domain "$domain" >> "$OUTPUT_FILE"
        if [[ $? -eq 0 ]]; then
            ((resolved_count++))
        fi
        
    done < "$DOMAINS_FILE"
    
    log "INFO" "Procesamiento completado: $resolved_count/$domain_count dominios resueltos"
    log "INFO" "Resultados guardados en: $OUTPUT_FILE"
    
    # Verificar que se generó al menos una resolución válida
    local line_count
    line_count=$(wc -l < "$OUTPUT_FILE")
    if [[ "$line_count" -le 1 ]]; then
        log "ERROR" "No se pudieron resolver dominios válidos"
        exit $EXIT_DNS_ERROR
    fi
    
    log "INFO" "CSV generado con $((line_count - 1)) registros"
}

# Ejecutar función principal si el script se ejecuta directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi