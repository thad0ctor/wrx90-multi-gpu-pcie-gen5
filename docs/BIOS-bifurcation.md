# BIOS / UEFI configuration (ASUS Pro WS WRX90E-SAGE SE)

The OS-side changes in this repo assume the firmware is configured correctly first. Two things matter on the WRX90E-SAGE SE: **PCIe slot bifurcation** (so physically-split x8/x8 slots enumerate both devices) and the **large-BAR prerequisites** (so high-VRAM GPUs can map their full BAR, which the `pci=hpmemsize=` kernel flag then sizes).

The firmware image itself is **not** included in this repo — it is ASUS proprietary firmware. Download it from the official/mirror sources below.

## BIOS version

Tested against **BIOS 9936** (release date 2025-09-15).

- ASUS official: the board's support/download page on asus.com ("Pro WS WRX90E-SAGE SE" → BIOS & Firmware).
- Community mirror (BIOS 9936, hosted by RTsoft): <https://rtsoft.com/files/Pro-WS-WRX90E-SAGE-SE-ASUS-9936.zip>
- Discussion / context on x8/x8 bifurcation for this board: <https://forum.level1techs.com/t/asus-wrx90e-sage-x8-x8-bifurcation/207260>

The BIOS revision affects how the board negotiates PCIe Gen5 across bifurcated slots, which is exactly the behavior the boot-time `pcie-gen5-fix.sh` retrain works around. If you run a very different BIOS, the bridge behavior (and whether the Gen5 retrain is even needed) may differ.

## PCIe bifurcation — the setting used

Slots that are physically wired as x8/x8 were set to **[x8 x8]** so both devices in the slot enumerate; full-width slots were left at **[x16]** / Auto. This matches the GPUs that show `x8` link width in `nvidia-smi` — that width is the bifurcation, not a fault.

In the UEFI:

1. Enter setup (Del/F2), switch to **Advanced Mode** (F7).
2. Find the per-slot PCIe bifurcation options. On this board they live under the **Advanced** menu (look for "Onboard Devices Configuration" or per-slot "PCIeXX Bifurcation" entries — the exact label/path varies slightly by BIOS revision).
3. Set each physically-split slot to **[x8/x8]** (or the split your riser/card requires — e.g. `[x4/x4/x4/x4]` for a quad-M.2 or quad-GPU carrier). Leave single-device x16 slots on **[x16]** or **[Auto]**.
4. Save & Exit (F10).

> How the slots are wired depends on the CPU lane map and any risers/bifurcation cards in use. Match the BIOS setting to the physical split of each populated slot.

## Large-BAR prerequisites (enable these)

These must be on for high-VRAM GPUs to expose their full BAR; the kernel's `pci=hpmemsize=128G` then reserves MMIO space to map them. Without them, big cards may not fully enumerate regardless of the kernel flags.

- **Above 4G Decoding** — Enabled
- **Re-Size BAR Support** — Enabled (Auto is usually fine)
- **PCIe link speed** — Gen5 / Auto (do not cap it at Gen4/Gen3)

(Also keep SR-IOV / IOMMU settings consistent with the `amd_iommu=on iommu=pt` boot flags if you use IOMMU features.)

## How this ties into the OS config

| Layer | Where | Purpose |
|-------|-------|---------|
| BIOS bifurcation `[x8/x8]` | UEFI Advanced | Makes both devices in a split slot enumerate |
| BIOS Above 4G + Re-Size BAR | UEFI Advanced | Lets large GPUs expose full BAR |
| `pci=hpmemsize=128G` + `pci=realloc` | GRUB entry | Reserves/reallocates MMIO so those BARs map |
| `pcie-gen5-fix.sh` | systemd oneshot | Retrains bridges to Gen5 (BIOS bifurcation-bug workaround) |

See the top-level [README](../README.md) for the OS-side details.
