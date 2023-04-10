#!/usr/bin/env nix-shell
#!nix-shell -p gnumake go kubernetes-controller-tools -i bash
set -e

export GOPATH="${GOPATH:-${HOME}/go}"
export PATH="${PATH}:${GOPATH}/bin"

if [ ! -d zfs-localpv ]; then
	git submodule update --init
fi
repopath="$(realpath ./zfs-localpv)"

# See: https://github.com/openebs/zfs-localpv/blob/master/docs/developer-setup.md
mkdir -v -p "${GOPATH}"/src/github.com/openebs
pushd "${GOPATH}"/src/github.com/openebs 2>/dev/null

# Set up zfs-localpv repository
rm -rf zfs-localpv || true
git clone "${repopath}" zfs-localpv
pushd zfs-localpv 2>/dev/null


# Patch scripts and run bootstrap
sed -i 's:#!/bin/bash:#!/usr/bin/env bash:' buildscripts/generate-manifests.sh
sed -i 's:GO111MODULE=on go get \$\$tool: GO111MODULE=on go install \$\$tool@latest:' Makefile
sed -i 's:\:trivialVersions=false,preserveUnknownFields=false::' buildscripts/generate-manifests.sh
make bootstrap # TODO: don't run this every time

# Patch manifests and regenerate the bundle

## Inject /nix/store
patch -p1 <<EOF
diff --git a/deploy/yamls/zfs-driver.yaml b/deploy/yamls/zfs-driver.yaml
index b50db68..c5c67f2 100644
--- a/deploy/yamls/zfs-driver.yaml
+++ b/deploy/yamls/zfs-driver.yaml
@@ -954,8 +954,8 @@ metadata:
 data:
   zfs: |
     #!/bin/sh
-    if [ -x /host/sbin/zfs ]; then
-      chroot /host /sbin/zfs "\$@"
+    if [ -x /host/run/current-system/sw/bin/zfs ]; then
+      chroot /host /run/current-system/sw/bin/zfs "\$@"
     elif [ -x /host/usr/sbin/zfs ]; then
       chroot /host /usr/sbin/zfs "\$@"
     else
@@ -1066,6 +1066,8 @@ spec:
               mountPath: /dev
             - name: encr-keys
               mountPath: /home/keys
+            - name: nix-store
+              mountPath: /nix/store
             - name: chroot-zfs
               mountPath: /sbin/zfs
               subPath: zfs
@@ -1087,6 +1089,9 @@ spec:
           hostPath:
             path: /home/keys
             type: DirectoryOrCreate
+        - name: nix-store
+          hostPath:
+            path: /nix/store
         - name: chroot-zfs
           configMap:
             defaultMode: 0555
EOF

make manifests

p="$(realpath ./deploy/zfs-operator.yaml)"
test -f "${p}"

git diff --color=always ./deploy/zfs-operator.yaml </dev/null | cat

popd 2>/dev/null
popd 2>/dev/null

ln -s -v -f "${p}"
