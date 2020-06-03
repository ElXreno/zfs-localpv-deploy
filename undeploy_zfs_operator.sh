#!/bin/sh
set -e

kubectl delete -f ./storage-class.yaml
kubectl delete -f ./zfs-operator.yaml
