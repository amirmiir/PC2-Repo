# Makefile para proyecto DNS - Mapa de dependencias DNS con detección de ciclos
# Cumple con 12-Factor (I, III, V) y separación Configurar-Lanzar-Ejecutar

# Variables de entorno por defecto (pueden sobrescribirse)
DOMAINS_FILE ?= DOMAINS.sample.txt
DNS_SERVER ?= 1.1.1.1
MAX_DEPTH ?= 10
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
.PHONY: all tools build test run pack clean help

# ==============================================================================
# TARGETS CON CACHE INCREMENTAL - Solo rebuilding si cambian dependencias
# ==============================================================================

# Target para dns_resolves.csv - depende del archivo de dominios y script
$(OUT_DIR)/dns_resolves.csv: $(DOMAINS_FILE) $(SRC_DIR)/resolve_dns.sh $(SRC_DIR)/common.sh
	@echo "==================================================================="
	@echo "Generando $(OUT_DIR)/dns_resolves.csv (caché incremental)"
	@echo "==================================================================="
	@mkdir -p $(OUT_DIR)
	@# Verificar que existe el archivo de dominios
	@if [ ! -f "$(DOMAINS_FILE)" ]; then \
		echo "ERROR: Archivo de dominios '$(DOMAINS_FILE)' no encontrado."; \
		echo "Especifique DOMAINS_FILE válido o use el archivo de ejemplo."; \
		exit 1; \
	fi
	@echo "Variables activas:"
	@echo "  DOMAINS_FILE = $(DOMAINS_FILE)"
	@echo "  DNS_SERVER   = $(DNS_SERVER)"
	@echo ""
	@DOMAINS_FILE=$(DOMAINS_FILE) DNS_SERVER=$(DNS_SERVER) $(SRC_DIR)/resolve_dns.sh || { \
		echo "ADVERTENCIA: resolve_dns.sh retornó código $$?"; \
		echo "Verificando si se generaron artefactos..."; \
		if [ -f "$(OUT_DIR)/dns_resolves.csv" ]; then \
			echo "CSV generado, continuando..."; \
		else \
			echo "ERROR: No se generó CSV"; \
			exit 1; \
		fi; \
	}

# Target para edges.csv y depth_report.txt - dependen de dns_resolves.csv y build_graph.sh
$(OUT_DIR)/edges.csv $(OUT_DIR)/depth_report.txt: $(OUT_DIR)/dns_resolves.csv $(SRC_DIR)/build_graph.sh $(SRC_DIR)/common.sh
	@echo "==================================================================="
	@echo "Generando grafo DNS (edges.csv + depth_report.txt)"
	@echo "==================================================================="
	@$(SRC_DIR)/build_graph.sh

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
	@echo "  make pack       Genera paquete reproducible en dist/ etiquetado"
	@echo "                  con RELEASE para distribución"
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
	@echo "  MAX_DEPTH       Limite de profundidad para proteccion (actual: $(MAX_DEPTH))"
	@echo "  RELEASE         Etiqueta de version para empaquetado (actual: $(RELEASE))"
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
	@echo "OK - Todas las herramientas requeridas están instaladas:"
	@$(foreach tool,$(REQUIRED_TOOLS), \
		echo "  OK $(tool): $$(which $(tool))";)
	@echo ""
	@echo "==================================================================="

# ==============================================================================
# TARGET: build - Genera artefactos sin ejecutar (Configurar-Lanzar-Ejecutar)
# ==============================================================================
build: tools $(OUT_DIR)/dns_resolves.csv $(OUT_DIR)/edges.csv $(OUT_DIR)/depth_report.txt
	@echo ""
	@echo "==================================================================="
	@echo "Build completado con caché incremental"
	@echo "==================================================================="
	@echo ""
	@echo "Artefactos generados en $(OUT_DIR)/:"
	@ls -lh $(OUT_DIR)/
	@echo ""
	@echo "Nota: Los archivos solo se regeneran si cambian sus dependencias"
	@echo "- dns_resolves.csv: se regenera si cambia $(DOMAINS_FILE) o scripts DNS" 
	@echo "- edges.csv + depth_report.txt: se regeneran si cambia dns_resolves.csv o build_graph.sh"

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
# TARGET: pack - Genera paquete reproducible para distribución
# ==============================================================================
pack: build
	@echo "==================================================================="
	@echo "Generando paquete reproducible: dist/proyecto12-v$(RELEASE).tar.gz"
	@echo "==================================================================="
	@echo ""
	@mkdir -p $(DIST_DIR)
	@# Crear estructura de paquete con contenido reproducible
	@echo "Preparando contenido del paquete..."
	@echo "- Código fuente (src/)"
	@echo "- Archivos de configuración y documentación"
	@echo "- Artefactos generados (out/)"
	@echo "- Suite de pruebas (tests/)"
	@echo ""
	@# Crear el paquete con orden determinista
	@tar -czf $(DIST_DIR)/proyecto12-v$(RELEASE).tar.gz \
		--exclude='.git*' \
		--exclude='$(DIST_DIR)' \
		--transform 's,^,proyecto12-v$(RELEASE)/,' \
		$(SRC_DIR)/ $(TEST_DIR)/ $(OUT_DIR)/ $(DOCS_DIR)/ \
		Makefile DOMAINS.sample.txt 2>/dev/null || true
	@echo ""
	@echo "Paquete generado exitosamente:"
	@ls -lh $(DIST_DIR)/proyecto12-v$(RELEASE).tar.gz
	@echo ""
	@echo "Contenido del paquete:"
	@tar -tzf $(DIST_DIR)/proyecto12-v$(RELEASE).tar.gz | head -20
	@echo ""
	@echo "==================================================================="
	@echo "Empaquetado completado - RELEASE: $(RELEASE)"
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
		echo "OK $(OUT_DIR)/ limpiado"; \
	fi
	@if [ -d "$(DIST_DIR)" ]; then \
		echo "Eliminando contenido de $(DIST_DIR)/..."; \
		rm -rf $(DIST_DIR)/*; \
		echo "OK $(DIST_DIR)/ limpiado"; \
	fi
	@echo ""
	@echo "==================================================================="
	@echo "Limpieza completada"
	@echo "==================================================================="