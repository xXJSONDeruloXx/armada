#!/bin/bash

check() {
    return 255
}

depends() {
    echo systemd bash
    return 0
}

install() {
    inst_multiple blkid cp findmnt mkdir mount mv sha256sum sleep sync systemctl umount
    inst_script "$moddir/recover.sh" \
        /usr/libexec/armada/sm8550-pcie-opp-initrd-recover
    inst_simple "$moddir/recover.service" \
        "$systemdsystemunitdir/sm8550-pcie-opp-initrd-recover.service"
    inst_simple "$moddir/recover.timer" \
        "$systemdsystemunitdir/sm8550-pcie-opp-initrd-recover.timer"
    inst_simple "$moddir/marker" \
        /usr/lib/armada/suspend-lab/pcie-opp-test-rollback

    mkdir -p "$initdir/$systemdsystemunitdir/dracut-pre-mount.service.d"
    printf '[Unit]\nWants=sm8550-pcie-opp-initrd-recover.timer\n' \
        > "$initdir/$systemdsystemunitdir/dracut-pre-mount.service.d/pcie-opp-recover.conf"
}
