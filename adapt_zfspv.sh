#!/bin/sh
set -e

export GOPATH="${GOPATH:-${HOME}/go}"
export PATH="${PATH}:${GOPATH}/bin"

# See: https://github.com/openebs/zfs-localpv/blob/master/docs/developer-setup.md
mkdir -v -p "${GOPATH}"/src/github.com/openebs
pushd "${GOPATH}"/src/github.com/openebs 2>/dev/null

# Set up zfs-localpv repository
if [ ! -d zfs-localpv ]; then
	git clone https://github.com/openebs/zfs-localpv.git
	pushd zfs-localpv
else
	pushd zfs-localpv 2>/dev/null
	git fetch
	git reset --hard origin/master
fi

# Patch scripts and run bootstrap
sed -i 's:#!/bin/bash:#!/usr/bin/env bash:' buildscripts/generate-manifests.sh
make bootstrap # TODO: don't run this every time

# Patch manifests and regenerate the bundle

## zfs-driver.yaml uses hardcoded paths. Perhaps only relevant on Ubuntu?
zfs_lib_dir="$(nix-build '<nixos>' --no-build-output --no-out-link -A zfs.lib)/lib"
zfs_bin_dir="$(nix-build '<nixos>' --no-build-output --no-out-link -A zfs)/bin"
sed -i '/path: /s# /lib# @ZFS_LIB@/lib#g' deploy/yamls/zfs-driver.yaml
sed -i '/path: /s# /sbin# @ZFS_BIN@/sbin#g' deploy/yamls/zfs-driver.yaml

## Inject /nix/store
patch -p1 <<EOF
diff -u a/deploy/yamls/zfs-driver.yaml b/deploy/yamls/zfs-driver.yaml
--- a/deploy/yamls/zfs-driver.yaml
+++ b/deploy/yamls/zfs-driver.yaml
@@ -778,6 +778,8 @@ spec:
               mountPath: /dev
             - name: encr-keys
               mountPath: /home/keys
+            - name: nix-store
+              mountPath: /nix/store
             - name: zfs-bin
               mountPath: /sbin/zfs
             - name: libzpool
@@ -804,6 +806,10 @@ spec:
           hostPath:
             path: /home/keys
             type: DirectoryOrCreate
+        - name: nix-store
+          hostPath:
+            path: /nix/store
+            type: Directory
         - name: zfs-bin
           hostPath:
             path: /sbin/zfs
EOF

## Replace libraries
sed -n '/@ZFS_LIB\+@/s/.*:\s\+@ZFS_LIB@\/lib\/\(.*\)/\1/gp' deploy/yamls/zfs-driver.yaml | while read -r lib; do
	# TODO: try to match minor versions
	test -f "${zfs_lib_dir}/${lib}" || {
		echo ">>> Could not find a match for 'lib/${lib}'"
		exit 1
	}
	sed -i 's#@ZFS_LIB@/lib/'"${lib}"'#'"${zfs_lib_dir}/${lib}"'#g' deploy/yamls/zfs-driver.yaml
done

## Replace binaries
sed -n '/@ZFS_BIN\+@/s/.*:\s\+@ZFS_BIN@\/sbin\/\(.*\)/\1/gp' deploy/yamls/zfs-driver.yaml | while read -r bin; do
	
	test -f "${zfs_bin_dir}/${bin}" || {
		echo ">>> Could not find a match for 'sbin/${bin}'"
		exit 1
	}
	sed -i 's#@ZFS_BIN@/sbin/'"${bin}"'#'"${zfs_bin_dir}/${bin}"'#g' deploy/yamls/zfs-driver.yaml
done

make manifests

p="$(realpath ./deploy/zfs-operator.yaml)"
test -f "${p}"

git diff --color=always ./deploy/zfs-operator.yaml </dev/null | cat

popd 2>/dev/null
popd 2>/dev/null

ln -s -v -f "${p}"
