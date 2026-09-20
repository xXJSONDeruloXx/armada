# Post-apply device reachability check

Captured 2026-09-20 17:16 UTC after requesting application of the staged PCIe
OPP diagnostic deployment; follow-up connectivity checks ran at 17:19 UTC.

## Apply request

The command `sudo -n bootc switch --from-downloaded --apply` returned
`Staged deployment will now be applied on reboot`, and its SSH connection then
closed. This confirms the request was accepted, not that the candidate booted.
No subsequent command reached the device.

## Follow-up observations

- SSH to `armada` (`192.168.0.20`, TCP/22), with a 6-second connect timeout,
  returned `Operation timed out`.
- Two ICMP pings to `192.168.0.20` received no response; a 3-second TCP/22
  connection attempt timed out.
- `adb devices -l` listed no device.
- `system_profiler SPUSBDataType -detailLevel mini` returned no attached USB
  devices. A 7-second `_ssh._tcp` mDNS browse found only this Mac.
- The neighbor table retained a prior MAC entry for `192.168.0.20`, but the
  device did not answer; the stale entry does not establish reachability.
- At 17:19 UTC, SSH via the default route returned `No route to host`. The
  selected `en0` route was `REJECT` with an incomplete ARP entry. A separate
  route lookup scoped to `en1` selected the Wi-Fi interface; `ping -b en1`
  reported `Host is down`, and SSH with `BindInterface=en1` returned
  `Host is down` as well.

The candidate boot, bootc rollback state, Wi-Fi, and current ESP contents are
unknown. No second reboot, suspend, or other device mutation was attempted.

## Recovery copy

The off-device ESP archive remains present at
`/Volumes/NovaKernelBuild/backups/nova-esp-20260920T1634Z/boot-esp-kernel-pair.tar`,
mode 0600, SHA-256
`0760f9acf1399a98186233800185b8a37a781247c0a10f12b98999da409eee16`. Its
extracted stock `KERNEL` and `KERNEL.BAK` were previously verified against the
device's pre-test hashes. This is a manual recovery copy, not proof that the
current device can boot or that the current ESP is unchanged.

## Next gate

Reestablish network or USB/physical access. Before another suspend test, read
the live boot ID, kernel/version, bootc booted/staged/rollback deployments,
Wi-Fi state, ESP image hashes, and candidate BTF. If the candidate did not
boot cleanly, use the documented rollback/recovery path rather than repeating
the apply blindly.
