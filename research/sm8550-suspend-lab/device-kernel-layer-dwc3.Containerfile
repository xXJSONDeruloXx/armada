# Ephemeral, device-local DWC3 candidate image recipe.
#
# This is an OCI/bootc image layer, not a loose /boot or /usr/lib/modules
# replacement. The base remains the installed Armada diagnostic image; the
# only kernel-source functional delta is 0910-usb-dwc3-qcom-skip-phy-init.patch.
FROM localhost/armada-rsc:20260901
LABEL org.opencontainers.image.version="20260902.dwc3-5aa8e4c"
LABEL org.opencontainers.image.source="https://github.com/xXJSONDeruloXx/armada-packages/tree/5aa8e4cfb7c6faf3cb22db77fc93519aadff5e92/kernel"
LABEL org.opencontainers.image.revision="5aa8e4cfb7c6faf3cb22db77fc93519aadff5e92"
LABEL ostree.linux="7.2.0"

COPY armada-kernel-7.2.0.tar.zst /tmp/armada-kernel-7.2.0.tar.zst
COPY armada-kernel-7.2.0.tar.zst.sha256 /tmp/armada-kernel-7.2.0.tar.zst.sha256

RUN set -eux; \
    cd /tmp; \
    sha256sum -c armada-kernel-7.2.0.tar.zst.sha256; \
    rm -rf /usr/lib/modules/7.2.0; \
    tar --extract --zstd -f armada-kernel-7.2.0.tar.zst -C /usr; \
    depmod -a 7.2.0 -b /; \
    mkdir -p /var/roothome; \
    dracut --force --no-hostonly --reproducible --kver 7.2.0 \
        --add ostree --add armada-splash --add armada-ostree-fallback \
        /usr/lib/modules/7.2.0/initramfs.img 7.2.0; \
    printf '%s\n' '20260902.dwc3-5aa8e4c' > /usr/lib/armada/version; \
    rm -f armada-kernel-7.2.0.tar.zst armada-kernel-7.2.0.tar.zst.sha256
