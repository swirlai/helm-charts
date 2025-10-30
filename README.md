# Helm Charts Repository

This repository contains Helm charts for deploying applications to Kubernetes clusters.
All charts follow best practices and are maintained using the Gitflow branching model.

## Using This Chart Repository

Add this Helm repository to your local Helm installation:
```bash 
helm repo add swirl https://swirlai.github.io/helm-charts/
helm repo update
```

Search for available charts:
```bash
helm search repo swirl
```

Install the Swirl Search Chart:
```bash
helm install my-swirl swirl/swirl-search -f custom-values.yaml --namespace swirl --create-namespace
```

View chart information:
```bash
helm show chart swirl/swirl-search
```

Show all Information including values:
```bash
helm show all swirl/swirl-search
```


## Repository Structure

- `charts/`: Helm chart directories
- `docs/`: Documentation and release guides
- `scripts/`: Utility scripts for development and testing
- `.github/workflows/`: CI/CD automation workflows

## Available Charts

### swirl-search
AI-powered search platform for Azure Kubernetes Service (AKS)

- **Version**: 1.0.0
- **App Version**: stable
- **Documentation**: [charts/swirl-search/README.md](charts/swirl-search/README.md)
- **Source**: https://github.com/swirlai/swirl-search

## Development

### Prerequisites
- Helm 3.x
- kubectl
- Access to a Azure AKS Kubernetes cluster

### Local Testing
* Lint the chart `helm lint charts/swirl-search/`
* Render templates locally  `helm template my-swirl charts/swirl-search/`
* Dry run installation  `helm install my-swirl charts/swirl-search/ --dry-run --debug`
# Chart Release Process

This document describes how charts are released and published from this repository.

## Repository Information

- **Chart Repository URL**: https://swirlai.github.io/helm-charts/
- **GitHub Repository**: https://github.com/swirlai/helm-charts
- **Charts Location**: `charts/` directory
- **Published via**: GitHub Pages (gh-pages branch)
