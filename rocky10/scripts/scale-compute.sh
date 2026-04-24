#!/bin/bash
set -e

DESIRED=${1:-2}
ROCKY_IMAGE_URL="${2:-https://dl.rockylinux.org/pub/rocky/10/images/x86_64/Rocky-10-GenericCloud-Base.latest.x86_64.qcow2}"
NAMESPACE="hpc-cluster"

# Count current compute nodes
CURRENT=$(kubectl get vms -n $NAMESPACE -l kubevirt.io/role=compute --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ -z "$CURRENT" ] || [ "$CURRENT" -eq 0 ]; then
    CURRENT=2  # Default is compute1 + compute2
fi

echo "Current compute nodes: $CURRENT"
echo "Desired compute nodes: $DESIRED"

if [ "$DESIRED" -le "$CURRENT" ]; then
    echo "Already have $CURRENT compute nodes. To scale down, delete VMs manually."
    exit 0
fi

# Create additional compute nodes
for i in $(seq $((CURRENT + 1)) $DESIRED); do
    echo "Creating compute$i..."

    cat <<EOF | kubectl apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: compute$i
  namespace: $NAMESPACE
  labels:
    kubevirt.io/vm: compute$i
    kubevirt.io/role: compute
spec:
  running: true
  dataVolumeTemplates:
  - metadata:
      name: compute${i}-disk
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
        kubevirt.io/vm: compute$i
    spec:
      domain:
        cpu:
          cores: 2
        resources:
          requests:
            memory: 6Gi
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
          name: compute${i}-disk
      - name: cloudinitdisk
        cloudInitNoCloud:
          secretRef:
            name: cloud-init-compute
EOF

done

echo "Done. Wait 2-5 minutes for VMs to start."
echo "Check status: just status"
