#!/bin/sh
set -e

if [ ! -f ./zfs-operator.yaml ]; then
	./adapt_zfspv.sh
fi

# Apply manifests
kubectl apply -f ./zfs-operator.yaml
kubectl apply -f ./storage-class.yaml
kubectl patch storageclass openebs-zfspv -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

kubectl get pods -n kube-system -l role=openebs-zfs
