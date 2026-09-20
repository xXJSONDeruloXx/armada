# Nova-only diagnostic image for the PCIe suspend-bandwidth experiment.
# Build from this exact installed base; do not use as a production image.
FROM ghcr.io/armada-os/armada@sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88

LABEL ostree.linux="7.2.3"
LABEL org.opencontainers.image.version="20260920.pcie-opp-test-initrd-guard-03"

ARG ARMADA_TEST_KERNEL_SHA256
ARG ARMADA_TEST_DTB_SHA256

COPY vmlinuz /usr/lib/modules/7.2.3/vmlinuz
COPY qcs8550-retroidpocket-rpnova.dtb /usr/lib/modules/7.2.3/dtb/qcom/qcs8550-retroidpocket-rpnova.dtb
COPY preserve-kernel-backup.conf /usr/lib/systemd/system/armada-bootimg-sync.service.d/90-suspend-lab-preserve-kernel-backup.conf
COPY sm8550-pcie-opp-test-rollback.service /usr/lib/systemd/system/
COPY sm8550-pcie-opp-test-rollback.timer /usr/lib/systemd/system/
COPY pcie-opp-test-rollback.marker /usr/lib/armada/suspend-lab/pcie-opp-test-rollback
COPY initrd-guard/ /usr/lib/dracut/modules.d/91armada-pcie-opp-initrd-recovery/

RUN set -eux; \
    test -n "${ARMADA_TEST_KERNEL_SHA256}"; \
    test -n "${ARMADA_TEST_DTB_SHA256}"; \
    printf '%s  %s\n' "${ARMADA_TEST_KERNEL_SHA256}" /usr/lib/modules/7.2.3/vmlinuz | sha256sum -c -; \
    printf '%s  %s\n' "${ARMADA_TEST_DTB_SHA256}" /usr/lib/modules/7.2.3/dtb/qcom/qcs8550-retroidpocket-rpnova.dtb | sha256sum -c -; \
    printf '%s\n' '20260920.pcie-opp-test-initrd-guard-03' > /usr/lib/armada/version; \
    chmod 0755 /usr/lib/dracut/modules.d/91armada-pcie-opp-initrd-recovery/module-setup.sh \
        /usr/lib/dracut/modules.d/91armada-pcie-opp-initrd-recovery/recover.sh; \
    install -d /usr/lib/systemd/system/timers.target.wants; \
    ln -s ../sm8550-pcie-opp-test-rollback.timer \
        /usr/lib/systemd/system/timers.target.wants/sm8550-pcie-opp-test-rollback.timer; \
    mkdir -p /var/roothome; \
    dracut --force --no-hostonly --reproducible --kver 7.2.3 \
        --add ostree \
        --add armada-splash \
        --add armada-ostree-fallback \
        --add armada-pcie-opp-initrd-recovery \
        /usr/lib/modules/7.2.3/initramfs.img 7.2.3; \
    lsinitrd /usr/lib/modules/7.2.3/initramfs.img > /tmp/initramfs.list; \
    for path in \
        usr/libexec/armada/sm8550-pcie-opp-initrd-recover \
        usr/lib/systemd/system/sm8550-pcie-opp-initrd-recover.service \
        usr/lib/systemd/system/sm8550-pcie-opp-initrd-recover.timer \
        usr/lib/armada/suspend-lab/pcie-opp-test-rollback; do \
        awk -v required="$path" '$NF == required { found=1 } END { exit !found }' /tmp/initramfs.list || \
            { echo "ERROR: $path missing from initramfs" >&2; exit 1; }; \
    done; \
    grep -Fq 'usr/lib/systemd/system/basic.target.wants/sm8550-pcie-opp-initrd-recover.timer' /tmp/initramfs.list || \
        { echo 'ERROR: early initrd recovery timer link missing from initramfs' >&2; exit 1; }
