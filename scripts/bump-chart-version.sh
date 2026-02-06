#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to validate semantic version
validate_version() {
    if [[ ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.+-]+)?$ ]]; then
        return 1
    fi
    return 0
}

# Function to bump version
bump_version() {
    local version=$1
    local bump_type=$2

    IFS='.' read -r major minor patch <<< "$version"

    case $bump_type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            print_error "Invalid bump type: $bump_type"
            exit 1
            ;;
    esac

    echo "${major}.${minor}.${patch}"
}

# Check arguments
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <chart-name> [version|major|minor|patch]"
    echo "Examples:"
    echo "  $0 swirl-search 1.2.3    # Set specific version"
    echo "  $0 swirl-search patch    # Bump patch version"
    echo "  $0 swirl-search minor    # Bump minor version"
    echo "  $0 swirl-search major    # Bump major version"
    exit 1
fi

CHART_NAME=$1
CHART_PATH="charts/${CHART_NAME}"

# Check if chart exists
if [ ! -f "${CHART_PATH}/Chart.yaml" ]; then
    print_error "Chart not found: ${CHART_PATH}"
    exit 1
fi

# Get current version
CURRENT_VERSION=$(grep "^version:" "${CHART_PATH}/Chart.yaml" | awk '{print $2}')
print_info "Current version: ${CURRENT_VERSION}"

# Determine new version
if [ $# -eq 2 ]; then
    VERSION_INPUT=$2

    case $VERSION_INPUT in
        major|minor|patch)
            NEW_VERSION=$(bump_version "$CURRENT_VERSION" "$VERSION_INPUT")
            ;;
        *)
            if validate_version "$VERSION_INPUT"; then
                NEW_VERSION=$VERSION_INPUT
            else
                print_error "Invalid version format: $VERSION_INPUT"
                print_error "Expected format: X.Y.Z or X.Y.Z-suffix"
                exit 1
            fi
            ;;
    esac
else
    # Default to patch bump
    NEW_VERSION=$(bump_version "$CURRENT_VERSION" "patch")
fi

print_info "New version: ${NEW_VERSION}"

# Update Chart.yaml
sed -i.bak "s/^version:.*/version: ${NEW_VERSION}/" "${CHART_PATH}/Chart.yaml"
rm -f "${CHART_PATH}/Chart.yaml.bak"

print_success "Updated ${CHART_PATH}/Chart.yaml to version ${NEW_VERSION}"

# Update appVersion if it matches the old version
APP_VERSION=$(grep "^appVersion:" "${CHART_PATH}/Chart.yaml" | awk '{print $2}' | tr -d '"')
if [ "$APP_VERSION" = "$CURRENT_VERSION" ]; then
    sed -i.bak "s/^appVersion:.*/appVersion: \"${NEW_VERSION}\"/" "${CHART_PATH}/Chart.yaml"
    rm -f "${CHART_PATH}/Chart.yaml.bak"
    print_success "Updated appVersion to ${NEW_VERSION}"
fi

echo ""
print_success "Chart version updated successfully!"
print_info "Next steps:"
echo "  1. Review the changes: git diff ${CHART_PATH}/Chart.yaml"
echo "  2. Commit the changes: git add ${CHART_PATH}/Chart.yaml && git commit -m 'chore: bump ${CHART_NAME} to ${NEW_VERSION}'"
echo "  3. Push to trigger release: git push origin main"