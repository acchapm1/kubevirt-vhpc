# HPC Cluster with KubeVirt on minikube (Rocky Linux 10)

Deploy a virtual HPC cluster using KubeVirt on minikube. VM rootdisks are imported from the Rocky 10 GenericCloud qcow2 by CDI on first deploy.

## Overview

This guide deploys a 4-node HPC cluster as VMs:
- **head** - Login node (2 vCPU, 4Gi memory)
- **compute1** - Compute node (2 vCPU, 6Gi memory)
- **compute2** - Compute node (2 vCPU, 6Gi memory)
- **storage** - NFS storage node (1 vCPU, 2Gi memory)

## Quick Start

```bash
# 1. Start minikube (choose your driver: kvm2, hyperkit, or docker)
just install-minikube docker

# 2. Full deployment (installs KubeVirt, CDI, and deploys VMs)
just full-deploy

# 3. Copy SSH key and connect
just copy-ssh-key
just ssh-head
```

**Note:** KubeVirt installation takes 2-3 minutes. VMs take 3-10 minutes to boot.

## Prerequisites

### Hardware
- 16GB+ RAM required
- 4+ CPU cores required
- 100GB+ disk space

### Software
- **kubectl** - Install from: https://kubernetes.io/docs/tasks/tools/
- **Just** - Install: `brew install just` or see https://github.com/casey/just

### Platform-Specific Requirements

**Linux:**
- KVM2 driver required
- Check: `ls -la /dev/kvm`
- Install: `sudo apt install libvirt-daemon-system qemu-kvm` (Debian/Ubuntu)
- Add user to kvm group: `sudo usermod -aG kvm $USER`

**macOS:**
- hyperkit driver or Docker Desktop
- Install hyperkit: `brew install hyperkit`
- Note: Uses Virtualization.framework on Apple Silicon
- **Docker Desktop users:** Ensure Docker has at least 8GB memory allocated (Settings > Resources > Memory)
  - Default minikube uses 16GB, but you can reduce it by editing the Justfile if needed

### SSH Key

Generate an SSH key pair before deploying:

**Linux:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "your_email@example.com"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

**macOS:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "your_email@example.com"
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

## Installation

### Step 1: Check Prerequisites

**Linux:**
```bash
# Check KVM is available
ls -la /dev/kvm

# Check user is in kvm group
groups | grep kvm
```

**macOS:**
```bash
# Check hyperkit
which hyperkit || brew install hyperkit
```

### Step 2: Start minikube

**Linux (KVM2 driver):**
```bash
just install-minikube kvm2
```

**macOS (hyperkit driver):**
```bash
just install-minikube hyperkit
```

**macOS (Docker driver - alternative):**
```bash
just install-minikube docker
```

**Note:** If you get "Docker Desktop has only XXXXMB memory" error:
1. Open Docker Desktop → Settings → Resources → Memory
2. Increase to at least 8192 MB (8GB) or more
3. Click "Apply & Restart"
4. Re-run the command

Wait for minikube to start (2-5 minutes).

### Step 3: Install KubeVirt

```bash
just install-kubevirt
```

Wait for KubeVirt to become available (2-3 minutes).

### Step 4: Install CDI

```bash
just install-cdi
```

Wait for CDI to become available (1-2 minutes).

### Step 5: Deploy VMs

**Option A: Use generated configuration (recommended)**
```bash
just generate-config   # Generate manifests from templates
just deploy-generated  # Deploy using generated manifests
```

**Option B: Use static manifests (legacy)**
```bash
just deploy-vms
```

**Wait time:** 3-10 minutes for VMs to boot.

### Step 6: Check Status

```bash
just status
```

Wait until all VMIs show "Running":
```
NAME        AGE     PHASE     IP
compute1    5m      Running   10.244.0.5
compute2    5m      Running   10.244.0.6
head        5m      Running   10.244.0.4
storage     5m      Running   10.244.0.7
```

### Step 7: Copy SSH Key to VMs

```bash
just copy-ssh-key
```

### Step 8: Get Connection Info

```bash
just get-ssh
```

### Step 9: Connect to Head Node

```bash
just ssh-head
```

Or get the minikube IP:
```bash
minikube ip
ssh rocky@$(minikube ip) -p 30222
```

Password: `Sp@rky26`

## SSH Access

### From Your Host Machine

```bash
# Get minikube IP
MINIKUBE_IP=$(minikube ip)

# As rocky user
ssh rocky@$MINIKUBE_IP -p 30222

# As root user
ssh root@$MINIKUBE_IP -p 30222
```

### From Head Node to Other Nodes

After SSHing to head as root:
```bash
ssh root@compute1
ssh root@compute2
ssh root@storage
```

### Using sudo

```bash
ssh rocky@$(minikube ip) -p 30222
sudo -i    # Password: Sp@rky26
```

## Scaling

### Add More Compute Nodes

```bash
# Scale to 4 compute nodes total
just scale-compute 4

# Scale to 8 compute nodes
just scale-compute 8
```

### Verify Scaling

```bash
just get-ips
```

## Common Commands

```bash
just --list          # Show all commands
just status          # Check cluster status
just get-ssh         # Get connection info
just get-ips         # Get VM IP addresses
just ssh-head        # SSH to head node
just delete-vms      # Delete VMs only
just teardown        # Full cleanup

# Minikube-specific
minikube status      # Check minikube
minikube dashboard   # Open web UI
minikube ssh         # SSH to minikube node
```

## Users

| Username | Password   | Access                                    |
|----------|------------|-------------------------------------------|
| rocky    | Sp@rky26   | External SSH to head node, sudo access    |
| root     | root       | All nodes, inter-node SSH from head       |

## Persistence

- **Persistent:** VM disks survive restarts
- **Lost on:** `just delete-vms` or `just teardown`

## Troubleshooting

### minikube Won't Start

**Linux - KVM issues:**
```bash
# Check libvirtd is running
sudo systemctl status libvirtd

# Check KVM permissions
ls -la /dev/kvm
sudo usermod -aG kvm $USER
# Log out and back in
```

**macOS - hyperkit issues:**
```bash
# Try Docker driver instead
minikube start --driver=docker --memory 16384 --cpus 4
```

### VMs Not Starting

```bash
# Check minikube resources
minikube status

# Check KubeVirt
kubectl get kubevirt -n kubevirt

# Check VM details
kubectl describe vm head -n hpc-cluster
kubectl describe vmi head -n hpc-cluster
```

### SSH Connection Refused

1. Wait longer - VMs take 3-10 minutes to boot
2. Get correct IP: `minikube ip`
3. Check service: `kubectl get svc ssh-head -n hpc-cluster`
4. Re-run: `just copy-ssh-key`

### Insufficient Resources

```bash
# Stop and delete current minikube
minikube stop
minikube delete

# Start with more resources
minikube start --driver=kvm2 --memory 24576 --cpus 6 --disk-size 150g
```

### CDI Issues

```bash
# Check CDI status
kubectl get cdi

# Check CDI pods
kubectl get pods -n cdi

# Restart CDI
kubectl rollout restart deployment cdi-deployment -n cdi
```

### Performance Issues

**Linux:** Ensure KVM is working:
```bash
lsmod | grep kvm
```

**macOS:** Consider:
- Using Docker driver for better compatibility
- Increasing Docker Desktop resources
- Using Apple Virtualization (M1/M2)

## Notes

- **Linux with KVM2:** Best performance
- **macOS with hyperkit:** Good performance
- **macOS with Docker:** Better compatibility, moderate performance
- **Apple Silicon:** Use Docker driver or QEMU

## Teardown

```bash
# Delete VMs only
just delete-vms

# Delete everything
just teardown
```

## Next Steps

- Configure with Ansible: `just ansible-run`
- Scale compute nodes: `just scale-compute 4`
- View the full plan: `cat README.md`
