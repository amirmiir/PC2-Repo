# Makefile para proyecto DNS - Mapa de dependencias DNS con detección de ciclos
# Cumple con 12-Factor (I, III, V) y separación Configurar-Lanzar-Ejecutar

# Variables de entorno por defecto (pueden sobrescribirse)
DOMAINS_FILE ?= DOMAINS.sample.txt
DNS_SERVER ?= 1.1.1.1
RELEASE ?= 0.1.0

# Directorios
SRC_DIR := src
TEST_DIR := tests
OUT_DIR := out
DIST_DIR := dist
DOCS_DIR := docs

# Herramientas requeridas
REQUIRED_TOOLS := dig curl ss awk sed sort uniq tee find

# Targets .PHONY (no generan archivos)
.PHONY: all tools build test run clean help

# Target por defecto
all: tools build

# ==============================================================================
# TARGET: help - Muestra descripción de todos los targets disponibles
# ==============================================================================
help:
	@echo "==================================================================="
	@echo "  Makefile - Proyecto DNS: Mapa de dependencias con detección"
	@echo "  de ciclos"
	@echo "==================================================================="
	@echo ""
	@echo "Targets disponibles:"
	@echo ""
	@echo "  make tools      Verifica que todas las herramientas requeridas"
	@echo "                  estén instaladas (dig, curl, ss, awk, etc.)"
	@echo ""
	@echo "  make build      Genera artefactos intermedios en out/ sin"
	@echo "                  ejecutar el proyecto completo (C-L-E: Configurar)"
	@echo ""
	@echo "  make test       Ejecuta la suite de pruebas Bats y muestra"
	@echo "                  resultados consolidados"
	@echo ""
	@echo "  make run        Ejecuta el flujo completo del proyecto con"
	@echo "                  las variables de entorno configuradas"
	@echo ""
	@echo "  make clean      Elimina archivos generados en out/ y dist/"
	@echo "                  de forma segura"
	@echo ""
	@echo "  make help       Muestra esta ayuda"
	@echo ""
	@echo "==================================================================="
	@echo "Variables de entorno configurables:"
	@echo ""
	@echo "  DOMAINS_FILE    Archivo con lista de dominios (actual: $(DOMAINS_FILE))"
	@echo "  DNS_SERVER      Servidor DNS a consultar (actual: $(DNS_SERVER))"
	@echo "  RELEASE         Etiqueta de versión para empaquetado (actual: $(RELEASE))"
	@echo ""
	@echo "==================================================================="
	@echo "Ejemplo de uso:"
	@echo ""
	@echo "  make tools"
	@echo "  DOMAINS_FILE=mis_dominios.txt make build"
	@echo "  make test"
	@echo "  DNS_SERVER=8.8.8.8 make run"
	@echo ""
	@echo "==================================================================="

# ==============================================================================
# TARGET: tools - Verifica herramientas requeridas
# ==============================================================================
tools:
	@echo "==================================================================="
	@echo "Verificando herramientas requeridas..."
	@echo "==================================================================="
	@$(foreach tool,$(REQUIRED_TOOLS), \
		which $(tool) > /dev/null 2>&1 || \
		(echo "ERROR: Herramienta '$(tool)' no encontrada. Por favor instálela." && exit 1);)
	@echo ""
	@echo "✓ Todas las herramientas requeridas están instaladas:"
	@$(foreach tool,$(REQUIRED_TOOLS), \
		echo "  ✓ $(tool): $$(which $(tool))";)
	@echo ""
	@echo "==================================================================="

# ==============================================================================
# TARGET: build - Genera artefactos sin ejecutar (Configurar-Lanzar-Ejecutar)
# ==============================================================================
build: tools
	@echo "==================================================================="
	@echo "Construyendo artefactos en $(OUT_DIR)/..."
	@echo "==================================================================="
	@echo ""
	@echo "Variables activas:"
	@echo "  DOMAINS_FILE = $(DOMAINS_FILE)"
	@echo "  DNS_SERVER   = $(DNS_SERVER)"
	@echo ""
	@# Crear directorio de salida si no existe
	@mkdir -p $(OUT_DIR)
	@# Verificar que existe el archivo de dominios
	@if [ ! -f "$(DOMAINS_FILE)" ]; then \
		echo "ERROR: Archivo de dominios '$(DOMAINS_FILE)' no encontrado."; \
		echo "Especifique DOMAINS_FILE válido o use el archivo de ejemplo."; \
		exit 1; \
	fi
	@# Ejecutar script de resolución DNS
	@echo "Ejecutando resolución DNS..."
	@DOMAINS_FILE=$(DOMAINS_FILE) DNS_SERVER=$(DNS_SERVER) $(SRC_DIR)/resolve_dns.sh
	@echo ""
	@echo "==================================================================="
	@echo "Build completado. Artefactos generados en $(OUT_DIR)/"
	@echo "==================================================================="
	@ls -lh $(OUT_DIR)/

# ==============================================================================
# TARGET: test - Ejecuta suite de pruebas Bats
# ==============================================================================
test: tools
	@echo "==================================================================="
	@echo "Ejecutando suite de pruebas Bats..."
	@echo "==================================================================="
	@echo ""
	@if ! command -v bats >/dev/null 2>&1; then \
		echo "ERROR: Bats no está instalado."; \
		echo "Instale Bats: https://bats-core.readthedocs.io/"; \
		exit 1; \
	fi
	@# Ejecutar todos los tests en el directorio tests/
	@if [ -d "$(TEST_DIR)" ] && [ -n "$$(find $(TEST_DIR) -name '*.bats' 2>/dev/null)" ]; then \
		bats $(TEST_DIR)/*.bats; \
	else \
		echo "ADVERTENCIA: No se encontraron pruebas en $(TEST_DIR)/"; \
	fi
	@echo ""
	@echo "==================================================================="
	@echo "Suite de pruebas completada"
	@echo "==================================================================="

# ==============================================================================
# TARGET: run - Ejecuta el flujo completo del proyecto
# ==============================================================================
run: build
	@echo ""
	@echo "==================================================================="
	@echo "Ejecutando flujo completo del proyecto..."
	@echo "==================================================================="
	@echo ""
	@# TODO: En sprints futuros se agregará build_graph.sh y verify_connectivity.sh
	@echo "Estado actual: Resolución DNS completada."
	@echo "Próximos pasos (sprints 2-3): construcción de grafo, detección"
	@echo "de ciclos y verificación de conectividad."
	@echo ""
	@echo "==================================================================="
	@echo "Ejecución completada"
	@echo "==================================================================="

# ==============================================================================
# TARGET: clean - Limpia archivos generados
# ==============================================================================
clean:
	@echo "==================================================================="
	@echo "Limpiando archivos generados..."
	@echo "==================================================================="
	@echo ""
	@if [ -d "$(OUT_DIR)" ]; then \
		echo "Eliminando contenido de $(OUT_DIR)/..."; \
		rm -rf $(OUT_DIR)/*; \
		echo "✓ $(OUT_DIR)/ limpiado"; \
	fi
	@if [ -d "$(DIST_DIR)" ]; then \
		echo "Eliminando contenido de $(DIST_DIR)/..."; \
		rm -rf $(DIST_DIR)/*; \
		echo "✓ $(DIST_DIR)/ limpiado"; \
	fi
	@echo ""
	@echo "==================================================================="
	@echo "Limpieza completada"
	@echo "==================================================================="