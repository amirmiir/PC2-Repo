#!/bin/bash

# common.sh - Utilidades comunes y lineamientos de robustez
# Autor: Amir
# Fecha: 2025-09-30

# Configuración de robustez
set -euo pipefail

# Códigos de salida estándar del proyecto
readonly EXIT_SUCCESS=0
readonly EXIT_GENERIC_ERROR=1
readonly EXIT_NETWORK_ERROR=2
readonly EXIT_DNS_ERROR=3
readonly EXIT_HTTP_ERROR=4
readonly EXIT_CONFIG_ERROR=5

# Variables globales para limpieza
declare -a TEMP_FILES=()

# Función de limpieza al salir
cleanup() {
    local exit_code=$?
    
    # Limpiar archivos temporales
    for temp_file in "${TEMP_FILES[@]:-}"; do
        if [[ -f "$temp_file" ]]; then
            rm -f "$temp_file"
        fi
    done
    
    exit $exit_code
}

# Configurar trap para limpieza
trap cleanup EXIT SIGINT SIGTERM

# Función para logging con timestamp
log() {
    local level="$1"
    shift
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" >&2
}

# Función para verificar dependencias
check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log "ERROR" "Comando requerido no encontrado: $cmd"
        exit $EXIT_CONFIG_ERROR
    fi
}

# Función para crear archivo temporal seguro
create_temp_file() {
    local temp_file
    temp_file=$(mktemp)
    TEMP_FILES+=("$temp_file")
    echo "$temp_file"
}

# Función para validar que un archivo existe y es legible
validate_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log "ERROR" "Archivo no encontrado: $file"
        exit $EXIT_CONFIG_ERROR
    fi
    if [[ ! -r "$file" ]]; then
        log "ERROR" "Archivo no legible: $file"
        exit $EXIT_CONFIG_ERROR
    fi
}

# Función para crear directorio si no existe
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log "INFO" "Directorio creado: $dir"
    fi
}