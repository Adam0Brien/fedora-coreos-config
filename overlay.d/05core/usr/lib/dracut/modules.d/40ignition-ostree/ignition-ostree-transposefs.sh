#!/bin/bash
set -euo pipefail

# This is implementation details of Ignition; in the future, we should figure
# out a way to ask Ignition directly whether there's a filesystem with label
# "root" being set up.
ignition_cfg=/run/ignition.json
rootdisk=/dev/disk/by-label/root
saved_data=/run/ignition-ostree-transposefs
saved_root=${saved_data}/root
partstate_root=/run/ignition-ostree-rootfs-partstate.json

case "${1:-}" in
    detect)
        wipes_root=$(jq '.storage?.filesystems? // [] | map(select(.label == "root" and .wipeFilesystem == true)) | length' "${ignition_cfg}")
        if [ "${wipes_root}" = "0" ]; then
            exit 0
        fi
        echo "Detected rootfs replacement in fetched Ignition config: /run/ignition.json"
        mkdir "${saved_data}"
        # use 80% of RAM: we want to be greedy since the boot breaks anyway, but
        # we still want to leave room for everything else so it hits ENOSPC and
        # doesn't invoke the OOM killer
        mount -t tmpfs tmpfs "${saved_data}" -o size=80%
        ;;
    save)
        mount "${rootdisk}" /sysroot
        echo "Moving rootfs to RAM..."
        cp -a /sysroot "${saved_root}"
        # also store the state of the partition
        lsblk "${rootdisk}" --nodeps --paths --json -b -o NAME,SIZE | jq -c . > "${partstate_root}"
        ;;
    restore)
        # This one is in a private mount namespace since we're not "offically" mounting
        mount "${rootdisk}" /sysroot
        echo "Restoring rootfs from RAM..."
        find "${saved_root}" -mindepth 1 -maxdepth 1 -exec mv -t /sysroot {} \;
        chattr +i $(ls -d /sysroot/ostree/deploy/*/deploy/*/)
        ;;
    cleanup)
        if [ -d "${saved_data}" ]; then
            umount "${saved_data}"
            rm -rf "${saved_data}" "${partstate_root}"
        fi
        ;;
    *)
        echo "Unsupported operation: ${1:-}" 1>&2; exit 1
        ;;
esac