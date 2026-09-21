#!/bin/bash
set -uo pipefail

STATE=/var/lib/sm8550-suspend-lab
RUN_ROOT=/var/home/armada/sm8550-suspend-lab-candidates
RUN_ID=20260921T155600Z-b9511ca007d6
AGENT=/usr/libexec/armada/sm8550_suspend_lab.py
LOG=/var/home/armada/sm8550-pcie-only-controller.log

exec >>"$LOG" 2>&1
printf 'started=%s\n' "$(date --iso-8601=seconds)"
mkdir -p "$STATE"
touch "$STATE/pcie-only-test-started-02"

rollback() {
    printf 'rollback=%s reason=%s\n' "$(date --iso-8601=seconds)" "$1"
    if [[ -d "$RUN_ROOT" ]]; then
        chown -R armada:armada "$RUN_ROOT"
    fi
    chown armada:armada "$LOG" 2>/dev/null || true
    chmod 0644 "$LOG" 2>/dev/null || true
    /usr/bin/bootc rollback --apply
}

if [[ ! -r "$AGENT" ]]; then
    rollback agent_missing
    exit 1
fi

image_version=$(cat /usr/lib/armada/version 2>/dev/null || true)
dt_status=$(tr -d '\000' < /sys/firmware/devicetree/base/soc@0/pcie@1c00000/status 2>/dev/null || true)
printf 'image_version=%s pcie_dtb_status=%s boot_id=%s\n' \
    "$image_version" "$dt_status" "$(cat /proc/sys/kernel/random/boot_id)"
if [[ "$image_version" != 20260921.pcie-only-dtb-1556 || "$dt_status" != disabled ]]; then
    rollback candidate_verification_failed
    exit 1
fi

/usr/bin/python3 "$AGENT" device start \
    --root "$RUN_ROOT" \
    --run-id "$RUN_ID" \
    --label 'PCIe host disabled from boot, QUP2 unchanged' \
    --mode deep \
    --sleep-seconds 15 \
    --wifi-state preserve \
    --bluetooth-state preserve \
    --trace-profile rpmh-aoss \
    --hypothesis 'Test whether removing only the PCIe host and its EBI request from boot allows firmware-recorded AOSD/CXSD/DDR residency; QUP2 remains enabled.' \
    --changed-variable 'Nova PCIe host DT status changed to disabled; all other candidate settings retained.' \
    --recommendation 'If named residency advances, isolate PCIe/EBI from remaining SH1/ACV/QUP2/LDOE requests. If not, run the UART-only test.' \
    --confidence 'single-cycle positive-control experiment' || {
        rollback runner_launch_failed
        exit 1
    }

status_file="$RUN_ROOT/runs/$RUN_ID/status.json"
state=missing
for attempt in $(seq 1 210); do
    if [[ -r "$status_file" ]]; then
        state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("state", "missing"))' "$status_file" 2>/dev/null || printf missing)
        case "$state" in
            complete|failed) break ;;
        esac
    fi
    sleep 1
done

printf 'run_id=%s final_state=%s\n' "$RUN_ID" "$state"
if [[ -r "$RUN_ROOT/runs/$RUN_ID/result.md" ]]; then
    cat "$RUN_ROOT/runs/$RUN_ID/result.md"
fi
rollback "test_finished_$state"
