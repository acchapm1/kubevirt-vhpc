#!/bin/bash
set -e

# Configuration variables passed from Justfile
VARIANT="${1:-hpc}"
SSH_PORT="${2:-30222}"
COMPUTE_NODES="${3:-2}"
STORAGE_NODES="${4:-1}"
COMPUTE_MEMORY="${5:-6Gi}"
STORAGE_SIZE="${6:-50Gi}"
HEAD_CPU="${7:-2}"
HEAD_MEMORY="${8:-4Gi}"
STORAGE_CPU="${9:-1}"
STORAGE_MEMORY="${10:-2Gi}"
COMPUTE_CPU="${11:-2}"
ROCKY_IMAGE_URL="${12:-https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2}"

NAMESPACE="${VARIANT}-cluster"
HEAD_NAME="head"
STORAGE_NAME="storage"
COMPUTE_PREFIX="compute"

echo "=== Generating Kubernetes manifests from templates ==="
echo "Configuration:"
echo "  Variant: ${VARIANT}"
echo "  Namespace: ${NAMESPACE}"
echo "  Compute nodes: ${COMPUTE_NODES}"
echo "  Storage nodes: ${STORAGE_NODES}"
echo "  Compute memory: ${COMPUTE_MEMORY}"
echo "  Storage size: ${STORAGE_SIZE}"
echo "  Rocky image: ${ROCKY_IMAGE_URL}"
echo ""

mkdir -p generated

# Generate namespace
cat > generated/namespace.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    name: ${NAMESPACE}
EOF

# Generate head VM (rootdisk = CDI DataVolume sourced from Rocky qcow2)
cat > generated/head-vm.yaml << EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${HEAD_NAME}
  namespace: ${NAMESPACE}
  labels:
    kubevirt.io/vm: ${HEAD_NAME}
    kubevirt.io/role: head
spec:
  running: true
  dataVolumeTemplates:
  - metadata:
      name: ${HEAD_NAME}-disk
    spec:
      source:
        http:
          url: ${ROCKY_IMAGE_URL}
      storage:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
        storageClassName: ${VARIANT}-local
  template:
    metadata:
      labels:
        kubevirt.io/vm: ${HEAD_NAME}
    spec:
      domain:
        cpu:
          cores: ${HEAD_CPU}
        resources:
          requests:
            memory: ${HEAD_MEMORY}
        devices:
          disks:
          - disk:
              bus: virtio
            name: rootdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - name: default
            masquerade: {}
      networks:
      - name: default
        pod: {}
      volumes:
      - name: rootdisk
        dataVolume:
          name: ${HEAD_NAME}-disk
      - name: cloudinitdisk
        cloudInitNoCloud:
          secretRef:
            name: cloud-init-${HEAD_NAME}
EOF

# Generate compute VMs (rootdisk per VM = CDI DataVolume sourced from Rocky qcow2)
echo "# Compute node VMs - ${COMPUTE_NODES} nodes" > generated/compute-vms.yaml
for i in $(seq 1 ${COMPUTE_NODES}); do
cat >> generated/compute-vms.yaml << VMEOF
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${COMPUTE_PREFIX}${i}
  namespace: ${NAMESPACE}
  labels:
    kubevirt.io/vm: ${COMPUTE_PREFIX}${i}
    kubevirt.io/role: compute
spec:
  running: true
  dataVolumeTemplates:
  - metadata:
      name: ${COMPUTE_PREFIX}${i}-disk
    spec:
      source:
        http:
          url: ${ROCKY_IMAGE_URL}
      storage:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
        storageClassName: ${VARIANT}-local
  template:
    metadata:
      labels:
        kubevirt.io/vm: ${COMPUTE_PREFIX}${i}
    spec:
      domain:
        cpu:
          cores: ${COMPUTE_CPU}
        resources:
          requests:
            memory: ${COMPUTE_MEMORY}
        devices:
          disks:
          - disk:
              bus: virtio
            name: rootdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - name: default
            masquerade: {}
      networks:
      - name: default
        pod: {}
      volumes:
      - name: rootdisk
        dataVolume:
          name: ${COMPUTE_PREFIX}${i}-disk
      - name: cloudinitdisk
        cloudInitNoCloud:
          secretRef:
            name: cloud-init-${COMPUTE_PREFIX}
VMEOF
done

# Generate storage VM (rootdisk = CDI DataVolume; nfsdata stays a plain PVC since it's empty scratch space)
cat > generated/storage-vm.yaml << EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${STORAGE_NAME}
  namespace: ${NAMESPACE}
  labels:
    kubevirt.io/vm: ${STORAGE_NAME}
    kubevirt.io/role: storage
spec:
  running: true
  dataVolumeTemplates:
  - metadata:
      name: ${STORAGE_NAME}-disk
    spec:
      source:
        http:
          url: ${ROCKY_IMAGE_URL}
      storage:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 10Gi
        storageClassName: ${VARIANT}-local
  template:
    metadata:
      labels:
        kubevirt.io/vm: ${STORAGE_NAME}
    spec:
      domain:
        cpu:
          cores: ${STORAGE_CPU}
        resources:
          requests:
            memory: ${STORAGE_MEMORY}
        devices:
          disks:
          - disk:
              bus: virtio
            name: rootdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          - disk:
              bus: virtio
            name: nfsdata
          interfaces:
          - name: default
            masquerade: {}
      networks:
      - name: default
        pod: {}
      volumes:
      - name: rootdisk
        dataVolume:
          name: ${STORAGE_NAME}-disk
      - name: cloudinitdisk
        cloudInitNoCloud:
          secretRef:
            name: cloud-init-${STORAGE_NAME}
      - name: nfsdata
        persistentVolumeClaim:
          claimName: ${STORAGE_NAME}-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${STORAGE_NAME}-data
  namespace: ${NAMESPACE}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: ${STORAGE_SIZE}
  storageClassName: ${VARIANT}-local
EOF

# Generate services
cat > generated/services.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: ssh-${HEAD_NAME}
  namespace: ${NAMESPACE}
  labels:
    kubevirt.io/vm: ${HEAD_NAME}
spec:
  type: NodePort
  selector:
    kubevirt.io/vm: ${HEAD_NAME}
  ports:
  - name: ssh
    port: 22
    targetPort: 22
    nodePort: ${SSH_PORT}
  externalTrafficPolicy: Cluster
EOF

echo ""
echo "=== Configuration generated in generated/ directory ==="
echo "Generated files:"
ls -la generated/
echo ""
echo "Review the files, then run: just full-deploy"
