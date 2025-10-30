# Chart Release Process

This document describes how charts are released and published in this repository.

## Automatic Releases

### Trigger
Charts are automatically released when changes are pushed to the `main` branch that affect files in the `charts/` directory.

### Process
1. **Version Detection**: The workflow detects changed charts by comparing versions with previously released versions.
2. **Packaging**: Charts are packaged using `helm package`.
3. **GitHub Release**: A GitHub release is created with the chart package as an asset.
4. **Index Update**: The `index.yaml` file is updated and published to GitHub Pages.
5. **GitHub Pages**: The chart repository is accessible via GitHub Pages.

## Manual Releases

### Via GitHub UI
1. Go to **Actions** → **Manual Chart Release**
2. Click **Run workflow**
3. Optionally specify:
    - Chart name (leave empty to release all charts)
    - Version number (leave empty to use current Chart.yaml version)
4. Click **Run workflow**

### Via Command Line

#### Bump Version and Release
```bash
# Bump patch version (1.2.3 → 1.2.4)
./scripts/bump-chart-version.sh swirl-search patch

# Bump minor version (1.2.3 → 1.3.0)
./scripts/bump-chart-version.sh swirl-search minor

# Bump major version (1.2.3 → 2.0.0)
./scripts/bump-chart-version.sh swirl-search major

# Set specific version
./scripts/bump-chart-version.sh swirl-search 2.1.0

# Commit and push
git add charts/swirl-search/Chart.yaml
git commit -m "chore: bump swirl-search to v2.1.0"
git push origin main
```