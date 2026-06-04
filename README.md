# Virtual HPC Cluster (KubeVirt)

A KubeVirt-on-Kubernetes virtual HPC (High Performance Computing) cluster for
testing, development, and learning purposes. Each variant provides a multi-node
environment with head, compute, and storage nodes running as real virtual
machines.

## What is vHPC?

vHPC (Virtual HPC) creates a complete HPC cluster environment as KubeVirt
virtual machines on a Kubernetes cluster. It simulates a real HPC environment
with:

- **Head Node** - Login/management node with SSH access
- **Compute Nodes** - Scalable processing workers
- **Storage Node** - Shared NFS storage for distributed data

This lets you test HPC workflows, develop parallel applications, and learn
cluster administration without physical hardware. Because the nodes are full
VMs (not containers), the environment behaves much like a bare-metal cluster.

A Docker-based sibling project implementing the same conceptual cluster lives at
[acchapm1/docker-vhpc](https://github.com/acchapm1/docker-vhpc).

## Features

- **Real VMs via KubeVirt** - Full Rocky Linux guests, not containers
- **CDI image import** - Root disks sourced from the official Rocky
  GenericCloud qcow2 and imported by CDI on first deploy
- **Scalable architecture** - Add/remove compute nodes via `just scale-compute`
- **Centralized configuration** - All settings in a single `Justfile`
- **Consistent naming** - Predictable VM and hostname patterns
- **SSH key management** - Passwordless access between nodes
- **Shared storage** - NFS mounts across all nodes

## Available Versions

| Version    | OS              | Directory   |
| ---------- | --------------- | ----------- |
| **Rocky 9**  | Rocky Linux 9   | `rocky9/`  |
| **Rocky 10** | Rocky Linux 10  | `rocky10/` |

The two variants are identical in structure; the only difference is the
`ROCKY_IMAGE_URL` pointing at the Rocky 9 or Rocky 10 GenericCloud qcow2.

## Quick Start

Run everything from a version directory (`rocky9/` or `rocky10/`):

```bash
cd rocky9

just check-prereqs            # verify kubectl, just, minikube, SSH keys
just install-minikube kvm2    # or hyperkit (macOS) / docker
just full-deploy              # generate-config + install-kubevirt + install-cdi + deploy
just copy-ssh-key             # push your SSH key to all VMs
just ssh-head                 # SSH to the head VM via NodePort
just scale-compute 4          # scale to 4 compute nodes
just status                   # nodes + VMs + services
just teardown                 # delete namespace + minikube
```

Run `just` with no arguments to list all recipes. See each version's
`README.md` and `HOWTO.md` for detailed instructions.

## Prerequisites

- kubectl (1.25+)
- [Just](https://github.com/casey/just) task runner: `brew install just`
- minikube (or another Kubernetes cluster with nested-virtualization support)
- An SSH key pair (`~/.ssh/id_ed25519` or `~/.ssh/id_rsa`)
- 16GB+ RAM, 4+ CPU cores

KubeVirt and CDI versions are pinned in the `Justfile` install recipes.

## Repository Layout

```
kubevirt-vhpc/
├── rocky9/    # Rocky Linux 9 variant (Justfile, manifests, ansible, scripts)
└── rocky10/   # Rocky Linux 10 variant (identical structure)
```

## Default Credentials

The cluster ships with dev-only credentials baked into the cloud-init configs:
`rocky` / `Sp@rky26` and `root` / `root`. These are for local testing only —
do not use this configuration in production.

## License

[MIT](LICENSE) © 2026 Alan Chapman
