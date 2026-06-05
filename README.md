# Armada

A SteamOS-like Linux distribution for ARM handhelds built on Fedora bootc using
device support from ROCKNIX.

Includes:
* ARM64 Steam
* Latest FEX
* CachyOS Proton 11

> [!WARNING]
> **Prototype software. Use at your own risk.** Armada is under active
> development and is not stable. Booting it requires flashing an ABL which
> could brick your device if done incorrectly.
>
> **There is currently no upgrade path.** To use a new build you will need
> to reflash your SD card, log back into Steam, and redownload your games.
>
> **SSH is enabled with a known default password.** To make debugging easier
> in the prototype phase, the image ships with user `armada` / password `armada`
> and SSH open. **Anyone on your network can log in.** Change the password
> before using Armada on an untrusted network, or treat the device as
> fully exposed.

## Supported devices

| Device | SoC | Status |
|---|---|---|
| AYANEO Pocket EVO | SM8550 | ✅ Developed and tested on hardware |
| Odin 2 Portal | SM8550 | ✅ Supported and tested |
| Odin 2 Mini | SM8550 | ✅ Supported (touchscreen not working) |
| Odin 2 | SM8550 | ⚪ Supported but untested |
| Retroid Pocket 6 | QCS8550 (SM8550) | ⚪ Supported (pending hardware testing) |

## Install

Armada currently boots from SD card. Internal install support is still in
development.

1. Flash the Armada image to SD.

   Use Balena Etcher to flash the latest `armada-YYYYMMDD.img.gz` image to a
   64GB or larger SD card (A2 speed for best results).

2. Flash the ROCKNIX ABL for your device.

   Insert the SD card and boot into Android. Copy the `rocknix_abl` folder to
   the root of your internal storage. Run `backup_abl.sh` as root followed by
   `flash_abl.sh` as root.

3. Boot from SD and set your device model.

   Reboot and hold volume up while powering on the device with the SD card
   inserted. Navigate the menus to set your device model and switch boot mode
   to Linux. Choose Start to boot your device.

4. Wait for Steam first-run setup.

   After the intro animation, the display may be black for up to 60 seconds
   before Steam appears. This is expected on the current SD-card boot path.
   Eventually you will see Steam first-run where you can configure your Wi-Fi
   and login.

## Roadmap

- **Desktop mode:** add support for switching to KDE from Steam
- **Install to internal storage:** currently boots from SD card
- **Update mechanism:** image-based updates with rollback
- **Power / fan control:** integrated with Steam UI where possible
- **Broader device support:** e.g. Odin 3

## Known issues

- **QAM button is unmapped.** Home is mapped to the Steam button currently. 
  Use Home+A to open the Quick Access Menu. Dedicated QAM button support is 
  in development.
- **No true suspend.** Pressing power does a "fake suspend" inspired by ROCKNIX,
  not real S3 sleep, so idle battery drain is higher than it should be.
- **GPU hangs from the Steam UI.** `steamwebhelper` (Steam's Chromium-based UI)
  can occasionally trigger an Adreno/Turnip GPU fault that locks the GPU until
  reboot. Currently under investigation.

## Credits

- **[ROCKNIX](https://github.com/ROCKNIX):** bootloader, device support,
  input mappings, audio profiles, and more.
- **[Bazzite](https://github.com/ublue-os/bazzite)** and the
  **[Universal Blue](https://github.com/ublue-os)** ecosystem: the bootc/image
  build structure, the [image-template](https://github.com/ublue-os/image-template)
  this repo is built from, and Steam/Gamescope session patterns.
- **Fedora** and the **[bootc](https://github.com/bootc-dev/bootc)** project: the
  base image and tooling.

## License

Armada's own code is **GPL-2.0-or-later**. If you modify and distribute it, your
changes stay open under the same terms. Bundled components keep their upstream
licenses. See [`LICENSE.md`](LICENSE.md).
