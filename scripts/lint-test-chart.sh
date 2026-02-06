#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

problems=()
# Check and install dependencies
print_info "Checking dependencies..."

if ! command_exists brew; then
    problems+=("Homebrew is not installed. Please install it first.")
fi

if ! command_exists helm; then
    problems+=("Helm not found. Please Install: brew install helm")
fi

if ! command_exists ct; then
    problems+=("chart-testing  not found. Please Install: brew install chart-testing")
fi

if ! command_exists kubeconform; then
    problems+=("kubeconform not found. Please Install: brew install kubeconform")
fi

if ! command_exists kind; then
    problems+=("kind not found. Please Install: brew install kind")
fi

if ! command_exists kubectl; then
    problems+=("kubectl not found. Please Install: brew install kubectl")
fi

if ! command_exists yamllint; then
    problems+=("yamllint not found. Please Install: brew install yamllint")
fi

if [ ${#problems[@]} -ne 0 ]; then
    print_error "The following dependencies are missing:"
    for problem in "${problems[@]}"; do
        echo "  - $problem"
    done
    exit 1
fi

echo ""
print_info "Starting chart validation..."
echo ""

# Navigate to project root
cd "$(dirname "$0")/.."

# 1. Helm Lint
print_info "Running helm lint on all charts..."
LINT_FAILED=0
for chart in charts/*/; do
    if [ -f "${chart}Chart.yaml" ]; then
        echo "  Linting $(basename "$chart")..."
        if helm lint "$chart"; then
            print_success "Lint passed for $(basename "$chart")"
        else
            print_error "Lint failed for $(basename "$chart")"
            LINT_FAILED=1
        fi
    fi
done

if [ $LINT_FAILED -eq 1 ]; then
    print_error "Helm lint failed!"
    exit 1
fi

echo ""

# 2. Kubeconform validation
print_info "Running kubeconform validation on all charts..."
KUBECONFORM_FAILED=0
for chart in charts/*/; do
    if [ -f "${chart}Chart.yaml" ]; then
        echo "  Validating $(basename "$chart") manifests..."
        if helm template "$chart" | kubeconform -strict -summary; then
            print_success "Kubeconform validation passed for $(basename "$chart")"
        else
            print_error "Kubeconform validation failed for $(basename "$chart")"
            KUBECONFORM_FAILED=1
        fi
    fi
done

if [ $KUBECONFORM_FAILED -eq 1 ]; then
    print_error "Kubeconform validation failed!"
    exit 1
fi

echo ""

# 3. Chart-testing lint
print_info "Running chart-testing lint..."
if ct lint --all --validate-maintainers=false; then
    print_success "chart-testing lint passed"
else
    print_error "chart-testing lint failed!"
    exit 1
fi

echo ""
print_success "All tests completed successfully! 🎉"