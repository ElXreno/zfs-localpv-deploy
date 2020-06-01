#!/bin/sh
set -e

if [ ! -f ./zfs-operator.yaml ]; then
	./adapt_zfspv.sh
fi

# Apply manifests
kubectl apply -f ./zfs-operator.yaml
kubectl get pods -n kube-system -l role=openebs-zfs

# sc.yaml
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-zfspv
parameters:
  recordsize: "4k"
  compression: "off"
  dedup: "off"
  fstype: "zfs"
  poolname: "zfspv-pool"
provisioner: zfs.csi.openebs.io
EOF

# pvc.yaml
kubectl apply -f - <<EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: csi-zfspv
spec:
  storageClassName: openebs-zfspv
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 9Gi
EOF
