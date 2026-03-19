#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and git workspace
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
GIT_WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null)

# Default values
DRY_RUN=false
UPDATE_INDEX=true
OUTPUT_DIR="${GIT_WORKSPACE}/.cr-release-packages"
SKIP_DEPS=false
SKIP_LINT=false

# Print functions
print_info() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Usage function
function usage {
    cat << EOF
Usage: $0 -c <chart_name> [OPTIONS]

Local Helm Chart Release Tool
Packages charts and optionally updates the local Helm repository index.

Required:
  -c <chart_name>    Name of the chart to release (e.g., swirl-search)

Optional:
  -o <output_dir>    Output directory for packaged charts (default: .cr-release-packages)
  -n                 Dry run - validate but don't package
  -s                 Skip dependency update
  -l                 Skip lint validation
  -i                 Skip index update
  -h                 Show this help message

Examples:
  # Package chart with all validations
  $0 -c swirl-search

  # Package without updating dependencies
  $0 -c swirl-search -s

  # Dry run to validate chart
  $0 -c swirl-search -n

  # Package to custom directory
  $0 -c swirl-search -o ./releases

Environment:
  Chart repository: ${GIT_WORKSPACE}
  Charts location:  ${GIT_WORKSPACE}/charts
  Default output:   ${OUTPUT_DIR}

EOF
    if [ -n "$1" ]; then
        print_error "$1"
    fi
    exit 1
}

# Parse arguments
while getopts "c:o:nsilh" flag; do
    case "${flag}" in
        c) CHART_NAME=${OPTARG};;
        o) OUTPUT_DIR=${OPTARG};;
        n) DRY_RUN=true;;
        s) SKIP_DEPS=true;;
        i) UPDATE_INDEX=false;;
        l) SKIP_LINT=true;;
        h) usage;;
        \?) usage "Invalid option: -${OPTARG}";;
        :) usage "Option -${OPTARG} requires an argument.";;
    esac
done

# Validate required arguments
if [ -z "$CHART_NAME" ]; then
    usage "Please provide chart name with -c option"
fi

# Validate git workspace
if [ -z "$GIT_WORKSPACE" ]; then
    print_error "Not in a git repository"
    exit 1
fi

# Setup paths
CHART_DIR="${GIT_WORKSPACE}/charts/${CHART_NAME}"
CHART_FILE="${CHART_DIR}/Chart.yaml"
VALUES_FILE="${CHART_DIR}/values.yaml"

# Validate chart exists
if [ ! -f "$CHART_FILE" ]; then
    print_error "Chart not found: ${CHART_FILE}"
    print_info "Available charts:"
    ls -1 "${GIT_WORKSPACE}/charts/" 2>/dev/null || echo "  No charts found"
    exit 1
fi

# Check dependencies
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

if ! command_exists helm; then
    print_error "Helm is not installed. Install with: brew install helm"
    exit 1
fi

if [ "$SKIP_LINT" = false ] && ! command_exists ct; then
    print_warning "chart-testing not found. Skipping ct validation. Install with: brew install chart-testing"
fi

# Extract chart information
CHART_VERSION=$(grep "^version:" "$CHART_FILE" | awk '{print $2}' | tr -d '"')
APP_VERSION=$(grep "^appVersion:" "$CHART_FILE" | awk '{print $2}' | tr -d '"')
CHART_DESCRIPTION=$(grep "^description:" "$CHART_FILE" | sed 's/^description: //' | tr -d '"')

if [ -z "$CHART_VERSION" ]; then
    print_error "Could not extract version from ${CHART_FILE}"
    exit 1
fi

# Print header
echo ""
print_info "═══════════════════════════════════════════════════════════"
print_info "  Helm Chart Release Tool"
print_info "═══════════════════════════════════════════════════════════"
echo ""
echo "  Chart:           ${CHART_NAME}"
echo "  Version:         ${CHART_VERSION}"
echo "  App Version:     ${APP_VERSION}"
echo "  Description:     ${CHART_DESCRIPTION}"
echo "  Chart Path:      ${CHART_DIR}"
echo "  Output Dir:      ${OUTPUT_DIR}"
echo "  Dry Run:         ${DRY_RUN}"
echo ""
print_info "═══════════════════════════════════════════════════════════"
echo ""

# Create output directory
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$OUTPUT_DIR"
    print_success "Output directory ready: ${OUTPUT_DIR}"
fi

# Step 1: Validate Chart.yaml
print_info "Step 1: Validating Chart.yaml..."
if helm show chart "$CHART_DIR" > /dev/null 2>&1; then
    print_success "Chart.yaml is valid"
else
    print_error "Chart.yaml validation failed"
    exit 1
fi

# Step 2: Update dependencies
if [ "$SKIP_DEPS" = false ]; then
    print_info "Step 2: Updating chart dependencies..."
    if [ -f "${CHART_DIR}/Chart.lock" ]; then
        print_warning "Chart.lock exists, updating dependencies"
    fi

    if helm dependency list "$CHART_DIR" 2>/dev/null | grep -q "missing"; then
        print_info "Missing dependencies detected, building..."
        if helm dependency build "$CHART_DIR"; then
            print_success "Dependencies updated"
        else
            print_error "Failed to update dependencies"
            exit 1
        fi
    else
        print_success "No dependencies or all up to date"
    fi
else
    print_warning "Step 2: Skipping dependency update"
fi

# Step 3: Lint chart
if [ "$SKIP_LINT" = false ]; then
    print_info "Step 3: Linting chart with helm lint..."
    if helm lint "$CHART_DIR"; then
        print_success "Helm lint passed"
    else
        print_error "Helm lint failed"
        exit 1
    fi

    # Additional lint with chart-testing if available
    if command_exists ct; then
        print_info "Step 3b: Linting with chart-testing..."
        if ct lint --charts "$CHART_DIR" --validate-maintainers=false 2>/dev/null; then
            print_success "chart-testing lint passed"
        else
            print_warning "chart-testing lint had warnings (non-fatal)"
        fi
    fi
else
    print_warning "Step 3: Skipping lint validation"
fi

# Step 4: Template validation
print_info "Step 4: Validating templates..."
if helm template test "$CHART_DIR" > /dev/null 2>&1; then
    print_success "Template rendering successful"
else
    print_error "Template rendering failed"
    helm template test "$CHART_DIR" || true
    exit 1
fi

# Step 5: Check for existing package
PACKAGE_FILE="${OUTPUT_DIR}/${CHART_NAME}-${CHART_VERSION}.tgz"
if [ -f "$PACKAGE_FILE" ]; then
    print_warning "Package already exists: ${PACKAGE_FILE}"
    read -p "Overwrite? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Aborted by user"
        exit 0
    fi
    rm -f "$PACKAGE_FILE"
fi

# Step 6: Package chart
if [ "$DRY_RUN" = false ]; then
    print_info "Step 5: Packaging chart..."

    if helm package "$CHART_DIR" --destination "$OUTPUT_DIR"; then
        print_success "Chart packaged successfully"
        print_success "Package: ${PACKAGE_FILE}"

        # Show package details
        PACKAGE_SIZE=$(du -h "$PACKAGE_FILE" | cut -f1)
        print_info "Package size: ${PACKAGE_SIZE}"
    else
        print_error "Failed to package chart"
        exit 1
    fi
else
    print_info "Step 5: Dry run - skipping packaging"
fi

# Step 7: Update Helm repository index
if [ "$UPDATE_INDEX" = true ] && [ "$DRY_RUN" = false ]; then
    print_info "Step 6: Updating Helm repository index..."

    INDEX_FILE="${OUTPUT_DIR}/index.yaml"
    REPO_URL="https://swirlai.github.io/helm-charts/"

    if [ -f "$INDEX_FILE" ]; then
        print_info "Merging with existing index..."
        if helm repo index "$OUTPUT_DIR" --url "$REPO_URL" --merge "$INDEX_FILE"; then
            print_success "Index updated successfully"
        else
            print_error "Failed to update index"
            exit 1
        fi
    else
        print_info "Creating new index..."
        if helm repo index "$OUTPUT_DIR" --url "$REPO_URL"; then
            print_success "Index created successfully"
        else
            print_error "Failed to create index"
            exit 1
        fi
    fi

    print_success "Index file: ${INDEX_FILE}"
fi

# Summary
echo ""
print_info "═══════════════════════════════════════════════════════════"
print_success "Release process completed successfully! 🎉"
print_info "═══════════════════════════════════════════════════════════"
echo ""

if [ "$DRY_RUN" = false ]; then
    echo "  📦 Package: ${PACKAGE_FILE}"
    if [ "$UPDATE_INDEX" = true ]; then
        echo "  📋 Index:   ${OUTPUT_DIR}/index.yaml"
    fi
    echo ""
    print_info "Next steps:"
    echo ""
    echo "  1. Test the packaged chart:"
    echo "     helm install test-release ${PACKAGE_FILE}"
    echo ""
    echo "  2. Commit and push to trigger GitHub release:"
    echo "     git add charts/${CHART_NAME}/Chart.yaml"
    echo "     git commit -m 'chore: release ${CHART_NAME} v${CHART_VERSION}'"
    echo "     git push origin main"
    echo ""
    echo "  3. Or install from local package:"
    echo "     helm upgrade --install my-release ${PACKAGE_FILE}"
else
    print_info "Dry run completed - no files were created"
    print_info "Run without -n flag to package the chart"
fi

echo ""
print_info "═══════════════════════════════════════════════════════════"