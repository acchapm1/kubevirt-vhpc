# KubeVirt-Based HPC Cluster (Rocky Linux 10)

Virtual HPC cluster using KubeVirt on Kubernetes, running Rocky Linux 10 VMs. Creates a portable training environment with the ability to scale compute and storage nodes.

VM root disks are sourced from the official Rocky 10 GenericCloud qcow2, imported by CDI on first deploy. Override the image with `ROCKY_IMAGE_URL` in the Justfile.

## Overview

This project deploys a 4-node HPC cluster as VMs:
- **head** - Login node (2 vCPU, 4Gi memory)
- **compute1** - Compute node (2 vCPU, 6Gi memory)
- **compute2** - Compute node (2 vCPU, 6Gi memory)
- **storage** - NFS storage node (1 vCPU, 2Gi memory)

## Quick Start

```bash
# Linux
just install-minikube kvm2

# macOS
just install-minikube hyperkit

# Deploy
just install-kubevirt
just install-cdi
just deploy-vms
just copy-ssh-key
just ssh-head
```

See [HOWTO-minikube.md](HOWTO-minikube.md) for detailed instructions.

## Prerequisites

- kubectl (1.25+)
- Just task runner: `brew install just`
- SSH key pair
- 16GB+ RAM, 4+ CPU cores

## Users

| Username | Password   | Access                                    |
|----------|------------|-------------------------------------------|
| rocky    | Sp@rky26   | External SSH to head node, sudo access    |
| root     | root       | All nodes, inter-node SSH from head       |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Kubernetes Cluster (minikube)                           │
│  ┌─────────────────────────────────────────────────┐   │
│  │ hpc-cluster namespace                            │   │
│  │  ┌─────────┐  ┌──────────┐  ┌──────────┐       │   │
│  │  │  head   │  │ compute1 │  │ compute2 │       │   │
│  │  │ 2C/4Gi  │  │  2C/6Gi  │  │  2C/6Gi  │       │   │
│  │  └────┬────┘  └────┬─────┘  └────┬─────┘       │   │
│  │       └────────────┼──────────────┘             │   │
│  │                    │                            │   │
│  │              ┌─────┴─────┐                      │   │
│  │              │  storage  │                      │   │
│  │              │  1C/2Gi   │                      │   │
│  │              └───────────┘                      │   │
│  └─────────────────────────────────────────────────┘   │
│                                                        │
│  SSH: NodePort 30222 ← External Access                │
└─────────────────────────────────────────────────────────┘
```

## Common Commands

```bash
just --list          # Show all commands
just status          # Check cluster status
just get-ssh         # Get connection info
just scale-compute N # Add compute nodes
just teardown        # Delete everything
```

## Scaling

```bash
# Scale to 4 compute nodes
just scale-compute 4

# Scale to 2 storage nodes
just scale-storage 2
```

## Documentation

- [HOWTO-minikube.md](HOWTO-minikube.md) - minikube deployment guide

## Related Projects

- [Docker Compose version](../lci-hpc-docker-vms/) - Original Docker-based implementation
- [KubeVirt](https://kubevirt.io/) - Virtual Machine API for Kubernetes
