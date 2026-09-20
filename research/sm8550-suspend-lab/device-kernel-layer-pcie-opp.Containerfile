# Nova-only diagnostic image for the PCIe suspend-bandwidth experiment.
# Build from this exact installed base; do not use as a production image.
FROM ghcr.io/armada-os/armada@sha256:5fe995d5fedf5034ee42a8f0e54dbd2d08e0c85adb9e3f88cfd52e55636eeb88

LABEL ostree.linux="7.2.3"
LABEL org.opencontainers.image.version="20260920.pcie-opp-test-01"

ARG ARMADA_TEST_KERNEL_SHA256
ARG ARMADA_TEST_DTB_SHA256

COPY vmlinuz /usr/lib/modules/7.2.3/vmlinuz
COPY qcs8550-retroidpocket-rpnova.dtb /usr/lib/modules/7.2.3/dtb/qcom/qcs8550-retroidpocket-rpnova.dtb
COPY preserve-kernel-backup.conf /usr/lib/systemd/system/armada-bootimg-sync.service.d/90-suspend-lab-preserve-kernel-backup.conf

RUN set -eux; \
    test -n "${ARMADA_TEST_KERNEL_SHA256}"; \
    test -n "${ARMADA_TEST_DTB_SHA256}"; \
    printf '%s  %s\n' "${ARMADA_TEST_KERNEL_SHA256}" /usr/lib/modules/7.2.3/vmlinuz | sha256sum -c -; \
    printf '%s  %s\n' "${ARMADA_TEST_DTB_SHA256}" /usr/lib/modules/7.2.3/dtb/qcom/qcs8550-retroidpocket-rpnova.dtb | sha256sum -c -; \
    printf '%s\n' '20260920.pcie-opp-test-01' > /usr/lib/armada/version
