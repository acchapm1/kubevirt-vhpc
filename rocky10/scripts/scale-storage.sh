#!/bin/bash
set -e

DESIRED=${1:-1}
ROCKY_IMAGE_URL="${2:-https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2}"
NAMESPACE="hpc-cluster"

# Count current storage nodes
CURRENT=$(kubectl get vms -n $NAMESPACE -l kubevirt.io/role=storage --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ -z "$CURRENT" ] || [ "$CURRENT" -eq 0 ]; then
    CURRENT=1  # Default is just "storage"
fi

echo "Current storage nodes: $CURRENT"
echo "Desired storage nodes: $DESIRED"

if [ "$DESIRED" -le "$CURRENT" ]; then
    echo "Already have $CURRENT storage nodes. To scale down, delete VMs manually."
    exit 0
fi

# Create additional storage nodes
for i in $(seq $((CURRENT + 1)) $DESIRED); do
    echo "Creating storage$i..."

    cat <<EOF | kubectl apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: storage$i
  namespace: $NAMESPACE
  labels:
    kubevirt.io/vm: storage$i
    kubevirt.io/role: storage
spec:
  running: true
  dataVolumeTemplates:
  - metadata:
      name: storage${i}-disk
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
        storageClassName: hpc-local
  template:
    metadata:
      labels:
        kubevirt.io/vm: storage$i
    spec:
      domain:
        cpu:
          cores: 1
        resources:
          requests:
            memory: 2Gi
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
          name: storage${i}-disk
      - name: cloudinitdisk
        cloudInitNoCloud:
          secretRef:
            name: cloud-init-storage
      - name: nfsdata
        persistentVolumeClaim:
          claimName: storage${i}-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage${i}-data
  namespace: $NAMESPACE
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: hpc-local
EOF

done

echo "Done. Wait 2-5 minutes for VMs to start."
echo "Check status: just status"
