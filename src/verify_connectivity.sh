#!/usr/bin/env bash
# src/verify_connectivity.sh
# Verifica conectividad de IPs tipo A usando ss y sondas HTTP/HTTPS con curl
# Metodología: Fail-fast, salidas deterministas en out/
# Códigos de salida:
#   0 = éxito
#   1 = error genérico
#   3 = error de red/conectividad
#   5 = error de configuración

set -euo pipefail

# Configuración de directorios
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly OUT_DIR="${PROJECT_ROOT}/out"

# Archivos de entrada/salida
readonly EDGES_FILE="${OUT_DIR}/edges.csv"
readonly DNS_RESOLVES_FILE="${OUT_DIR}/dns_resolves.csv"
readonly CONNECTIVITY_SS_OUTPUT="${OUT_DIR}/connectivity_ss.txt"
readonly CURL_PROBE_OUTPUT="${OUT_DIR}/curl_probe.txt"

# Variables configurables
readonly CURL_TIMEOUT="${CURL_TIMEOUT:-5}"
readonly CURL_MAX_TIME="${CURL_MAX_TIME:-10}"

# Función de limpieza
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "Error durante verificación de conectividad (código: $exit_code)" >&2
    fi
    exit $exit_code
}

trap cleanup EXIT ERR

# Validación de prerequisitos
validate_prerequisites() {
    # Verificar que existe archivo DNS resolves
    if [ ! -f "${DNS_RESOLVES_FILE}" ]; then
        echo "Error: No existe ${DNS_RESOLVES_FILE}" >&2
        echo "Ejecuta resolve_dns.sh primero" >&2
        exit 5
    fi

    # Verificar que existe edges.csv (opcional pero recomendado)
    if [ ! -f "${EDGES_FILE}" ]; then
        echo "Advertencia: No existe ${EDGES_FILE}, usando dns_resolves.csv directamente" >&2
    fi

    # Verificar herramientas requeridas
    # En macOS, usar netstat en lugar de ss
    if ! command -v ss &> /dev/null && ! command -v netstat &> /dev/null; then
        echo "Error: ni 'ss' ni 'netstat' encontrados" >&2
        exit 5
    fi

    if ! command -v curl &> /dev/null; then
        echo "Error: comando 'curl' no encontrado" >&2
        exit 5
    fi
}

# Extraer IPs tipo A desde edges.csv o dns_resolves.csv
extract_a_records() {
    local ips=()

    # Intentar desde edges.csv primero
    if [ -f "${EDGES_FILE}" ]; then
        # Extraer columna 'to' donde 'kind' es 'A'
        while IFS=, read -r from to kind; do
            if [ "$kind" = "A" ] && [ "$to" != "to" ]; then
                ips+=("$to")
            fi
        done < "${EDGES_FILE}"
    fi

    # Si no hay IPs desde edges, usar dns_resolves.csv
    if [ ${#ips[@]} -eq 0 ]; then
        while IFS=, read -r source record_type target ttl trace_ts; do
            if [ "$record_type" = "A" ] && [ "$target" != "target" ]; then
                ips+=("$target")
            fi
        done < "${DNS_RESOLVES_FILE}"
    fi

    # Eliminar duplicados y ordenar
    printf '%s\n' "${ips[@]}" | sort -u
}

# Verificar conectividad con ss o netstat
verify_with_ss() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    local use_netstat=false

    # Detectar si usar netstat (macOS) o ss (Linux)
    if ! command -v ss &> /dev/null; then
        use_netstat=true
    fi

    {
        echo "==================================================================="
        echo "Reporte de Conectividad con ss/netstat (Socket Statistics)"
        echo "==================================================================="
        echo "Generado: ${timestamp}"
        echo "Herramienta: $(if $use_netstat; then echo 'netstat (macOS)'; else echo 'ss (Linux)'; fi)"
        echo "Objetivo: Verificar estado de sockets y conexiones TCP/UDP activas"
        echo ""
        echo "-------------------------------------------------------------------"
        echo "Estado general de sockets TCP"
        echo "-------------------------------------------------------------------"

        if $use_netstat; then
            # Usar netstat en macOS
            netstat -an -p tcp | head -20
        else
            # Usar ss en Linux
            ss -tan | head -20
        fi

        echo ""
        echo "-------------------------------------------------------------------"
        echo "Conexiones establecidas (ESTAB/ESTABLISHED)"
        echo "-------------------------------------------------------------------"

        if $use_netstat; then
            netstat -an -p tcp | grep ESTABLISHED | head -15
        else
            ss -tan state established | head -15
        fi

        echo ""
        echo "-------------------------------------------------------------------"
        echo "Estadísticas de sockets por protocolo"
        echo "-------------------------------------------------------------------"

        if $use_netstat; then
            echo "TCP sockets:"
            netstat -an -p tcp | grep -c "^tcp" || echo "0"
            echo "UDP sockets:"
            netstat -an -p udp | grep -c "^udp" || echo "0"
        else
            echo "TCP sockets:"
            ss -tan | grep -c "^tcp" || echo "0"
            echo "UDP sockets:"
            ss -uan | grep -c "^udp" || echo "0"
        fi

        echo ""
        echo "-------------------------------------------------------------------"
        echo "Verificación de puertos comunes (HTTP/HTTPS)"
        echo "-------------------------------------------------------------------"

        # Verificar conexiones en puertos HTTP/HTTPS
        echo "Conexiones en puerto 80 (HTTP):"
        if $use_netstat; then
            netstat -an -p tcp | grep "\.80 " | head -5 || echo "  No hay conexiones activas en puerto 80"
        else
            ss -tan | grep ":80 " | head -5 || echo "  No hay conexiones activas en puerto 80"
        fi

        echo ""
        echo "Conexiones en puerto 443 (HTTPS):"
        if $use_netstat; then
            netstat -an -p tcp | grep "\.443 " | head -5 || echo "  No hay conexiones activas en puerto 443"
        else
            ss -tan | grep ":443 " | head -5 || echo "  No hay conexiones activas en puerto 443"
        fi

        echo ""
        echo "-------------------------------------------------------------------"
        echo "IPs destino desde resoluciones DNS"
        echo "-------------------------------------------------------------------"

        # Listar IPs de interés
        local ips
        ips=$(extract_a_records)

        if [ -n "$ips" ]; then
            echo "$ips" | while read -r ip; do
                echo "Buscando conexiones a: $ip"
                local found=false

                if $use_netstat; then
                    if netstat -an | grep -q "$ip"; then
                        netstat -an | grep "$ip" | head -3
                        found=true
                    fi
                else
                    if ss -tan | grep -q "$ip"; then
                        ss -tan | grep "$ip" | head -3
                        found=true
                    fi
                fi

                if ! $found; then
                    echo "  No hay conexiones activas a esta IP"
                fi
            done
        else
            echo "  No se encontraron IPs tipo A para verificar"
        fi

        echo ""
        echo "==================================================================="
        echo "Fin del reporte ss/netstat"
        echo "==================================================================="

    } > "${CONNECTIVITY_SS_OUTPUT}"

    echo "✓ Reporte ss generado: ${CONNECTIVITY_SS_OUTPUT}"
}

# Sondear HTTP/HTTPS con curl
probe_with_curl() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')

    {
        echo "==================================================================="
        echo "Reporte de Sonda HTTP/HTTPS con curl"
        echo "==================================================================="
        echo "Generado: ${timestamp}"
        echo "Objetivo: Verificar accesibilidad HTTP/HTTPS y medir latencia"
        echo "Timeout: ${CURL_TIMEOUT}s (conexión), ${CURL_MAX_TIME}s (total)"
        echo ""

        # Obtener dominios únicos con registros A
        local domains
        domains=$(awk -F, '$2=="A" && NR>1 {print $1}' "${DNS_RESOLVES_FILE}" | sort -u)

        # Probar cada dominio con HTTP y HTTPS
        while read -r domain; do
            [ -z "$domain" ] && continue

            # Obtener IP del dominio
            local ip
            ip=$(awk -F, -v d="$domain" '$1==d && $2=="A" {print $3; exit}' "${DNS_RESOLVES_FILE}")

            echo "-------------------------------------------------------------------"
            echo "Dominio: ${domain} -> IP: ${ip}"
            echo "-------------------------------------------------------------------"

            # Probar HTTPS primero (más común)
            echo ""
            echo "[HTTPS] Probando https://${domain}"

            local start_time=$(date +%s)
            local http_code
            local curl_output

            if curl_output=$(curl -s -o /dev/null -w "%{http_code}" \
                --connect-timeout "${CURL_TIMEOUT}" \
                --max-time "${CURL_MAX_TIME}" \
                -L "https://${domain}" 2>&1); then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))

                echo "  Status: ${curl_output}"
                echo "  Protocolo: HTTPS (puerto 443, TLS/SSL)"
                echo "  Tiempo de respuesta: ${duration}s"

                case "${curl_output}" in
                    200) echo "  Resultado: OK - Servidor respondió correctamente" ;;
                    301|302|303|307|308) echo "  Resultado: Redirección detectada" ;;
                    400|401|403|404) echo "  Resultado: Error del cliente (${curl_output})" ;;
                    500|502|503|504) echo "  Resultado: Error del servidor (${curl_output})" ;;
                    000) echo "  Resultado: No se pudo conectar (timeout o rechazo)" ;;
                    *) echo "  Resultado: Código HTTP ${curl_output}" ;;
                esac
            else
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))

                echo "  Status: Error de conexión"
                echo "  Protocolo: HTTPS (puerto 443)"
                echo "  Tiempo transcurrido: ${duration}s"
                echo "  Resultado: No se pudo establecer conexión HTTPS"
            fi

            # Probar HTTP (fallback)
            echo ""
            echo "[HTTP] Probando http://${domain}"

            start_time=$(date +%s)

            if curl_output=$(curl -s -o /dev/null -w "%{http_code}" \
                --connect-timeout "${CURL_TIMEOUT}" \
                --max-time "${CURL_MAX_TIME}" \
                -L "http://${domain}" 2>&1); then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))

                echo "  Status: ${curl_output}"
                echo "  Protocolo: HTTP (puerto 80, sin cifrado)"
                echo "  Tiempo de respuesta: ${duration}s"

                case "${curl_output}" in
                    200) echo "  Resultado: OK - Servidor respondió correctamente" ;;
                    301|302|303|307|308) echo "  Resultado: Redirección detectada (probablemente a HTTPS)" ;;
                    400|401|403|404) echo "  Resultado: Error del cliente (${curl_output})" ;;
                    500|502|503|504) echo "  Resultado: Error del servidor (${curl_output})" ;;
                    000) echo "  Resultado: No se pudo conectar (timeout o rechazo)" ;;
                    *) echo "  Resultado: Código HTTP ${curl_output}" ;;
                esac
            else
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))

                echo "  Status: Error de conexión"
                echo "  Protocolo: HTTP (puerto 80)"
                echo "  Tiempo transcurrido: ${duration}s"
                echo "  Resultado: No se pudo establecer conexión HTTP"
            fi

            echo ""
        done <<< "$domains"

        echo "==================================================================="
        echo "Fin del reporte curl"
        echo "==================================================================="

    } > "${CURL_PROBE_OUTPUT}"

    echo "✓ Reporte curl generado: ${CURL_PROBE_OUTPUT}"
}

# Main
main() {
    echo "=== Verificación de Conectividad ===" >&2
    echo "" >&2

    # Validar prerequisitos
    validate_prerequisites

    # Crear directorio de salida si no existe
    mkdir -p "${OUT_DIR}"

    # Ejecutar verificaciones
    echo "Ejecutando verificación con ss..." >&2
    verify_with_ss

    echo "" >&2
    echo "Ejecutando sondas HTTP/HTTPS con curl..." >&2
    probe_with_curl

    echo "" >&2
    echo "✓ Verificación de conectividad completada" >&2
    echo "  - ${CONNECTIVITY_SS_OUTPUT}" >&2
    echo "  - ${CURL_PROBE_OUTPUT}" >&2

    exit 0
}

# Ejecutar solo si se invoca directamente
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
