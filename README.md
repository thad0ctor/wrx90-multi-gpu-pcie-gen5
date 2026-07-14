# Multi-GPU recognition + PCIe Gen 5 on AMD WRX90

Boot and system configuration to get a large number of NVIDIA GPUs fully recognized, and to negotiate **PCIe Gen 5**, on the AMD Ryzen Threadripper PRO **WRX90** platform (tested on an ASUS Pro WS WRX90E-SAGE SE with a mix of Blackwell, Ada and Ampere cards). If your GPUs aren't all enumerated, or Gen5-capable cards come up at a lower link speed, this is the fix.

The solution has five parts — one in firmware, four in the OS:

0. **BIOS/UEFI** — PCIe slot bifurcation (`x8/x8` on split slots) plus Above 4G Decoding and Re-Size BAR. See **[docs/BIOS-bifurcation.md](docs/BIOS-bifurcation.md)**. Do this first; the OS flags below depend on it.
1. **Kernel boot parameters** — reserve enough MMIO/BAR space and stabilize the PCIe links so every GPU enumerates.
2. **Boot-time PCIe Gen 5 retrain** — a small `setpci` service that forces Gen5 on the bridges above Gen5 GPUs (works around a BIOS bifurcation bug).
3. **NVIDIA module options** — mode setting on, `nouveau` blacklisted.
4. **`nvidia-persistenced`** — kept working so persistence mode stays on.

> The kernel flags are general to the WRX90 platform. The **PCIe bridge IDs** in part 2 are specific to your slot layout — you must find your own (instructions below and in the script).

## Tested configuration

Validated on this system. Other WRX90 boards, kernels and driver branches should work too — this is what it was confirmed against, not a hard requirement.

| Component | Version |
|-----------|---------|
| OS | Ubuntu 24.04.4 LTS (Noble) |
| Kernel | 6.17.0-35-generic (HWE) |
| GRUB | 2.12 |
| Motherboard | ASUS Pro WS WRX90E-SAGE SE |
| BIOS | 9936 (2025-09-15) — see [docs/BIOS-bifurcation.md](docs/BIOS-bifurcation.md) |
| CPU | AMD Ryzen Threadripper PRO 7965WX (WRX90) |
| NVIDIA driver | 610.43.02, **Open** kernel module |
| CUDA (runtime/UMD) | 13.3 |
| GPUs | 8 total: 2× RTX PRO 6000 Blackwell, 1× RTX 5090, 2× RTX 3090 Ti, 3× RTX 3090 |

Notes on requirements vs. what was merely tested:
- **NVIDIA Open kernel module 570+ is required** for Blackwell GPUs (RTX PRO 6000 / RTX 5090); the proprietary module won't drive them.
- `pci=hpmemsize=` must exceed the sum of your Gen5/large-BAR GPUs' BAR sizes; `128G` suited the mix above — scale it to your own VRAM.
- The BIOS version matters for the bifurcation behavior part 2 works around; newer/older BIOSes may negotiate Gen5 differently.

## Quick start

```bash
# 1. Edit the bridge IDs for your board:
nano usr/local/bin/pcie-gen5-fix.sh        # set BRIDGES=...  (see comments in the file)

# 2. Install everything (fills in your root UUID + running kernel automatically):
sudo ./apply.sh

# 3. Make it the default boot entry, then reboot:
sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="multigpu-pcie"/' /etc/default/grub
sudo update-grub
sudo reboot
```

Prefer to do it by hand? Every file lives under its real system path in this repo (`etc/…`, `usr/local/bin/…`); copy them into place yourself. `apply.sh` just automates that.

## 1. Kernel boot parameters (the core fix)

The working boot uses a custom GRUB entry with this command line:

```
pci=realloc pci=hpmemsize=128G pcie_aspm=off amd_iommu=on iommu=pt pci=noaer pcie_port_pm=off
```

| Parameter | Purpose |
|-----------|---------|
| `pci=realloc` | Let the kernel reallocate PCI BAR windows so every GPU's BAR fits. Essential with many GPUs. |
| `pci=hpmemsize=128G` | Reserve a large hotplug/MMIO window so big-VRAM cards' **Resizable BAR** can map. **The single most important value** — without it (default `0`), high-memory GPUs may fail to enumerate. Size it comfortably above the sum of your large BARs. |
| `pcie_aspm=off` | Disable PCIe Active State Power Management; prevents link instability. |
| `amd_iommu=on iommu=pt` | Enable the AMD IOMMU in pass-through mode — stable P2P without remap overhead. |
| `pci=noaer` | Silence PCIe Advanced Error Reporting; WRX90 BIOSes often flood correctable AER messages. |
| `pcie_port_pm=off` | Disable PCIe port power management (extra link-stability insurance). |

### The GRUB entry

`etc/grub.d/09_multigpu-pcie` is a drop-in that survives `update-grub` (unlike hand edits to `grub.cfg`). It contains two placeholders you must fill in (`apply.sh` does this for you):

- `__ROOT_UUID__` — `findmnt -no UUID /`
- `__KERNEL_VERSION__` — `uname -r`

Set `GRUB_DEFAULT="multigpu-pcie"` in `/etc/default/grub` and run `sudo update-grub` to boot it by default.

> Alternatively, if you don't want a separate entry, put the same flags into `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` so **all** entries use them. The custom-entry approach is kept here so you can fall back to a stock boot easily.

## 2. Boot-time PCIe Gen 5 retrain

Some WRX90 boards leave Gen5-capable GPUs below Gen5 after POST due to a bifurcation bug. A oneshot service re-programs the PCIe capability registers on the bridges feeding those GPUs and retrains the link.

- Service: `etc/systemd/system/pcie-gen5-fix.service` (runs early, before module load)
- Script: `usr/local/bin/pcie-gen5-fix.sh`

**Find your bridge IDs** (once per machine):

```bash
lspci -tv                          # PCIe tree — note the bridge one level ABOVE each Gen5 GPU
lspci -vv -s <gpu> | grep LnkCap   # confirm the GPU is Gen5 (Speed 32GT/s)
```

The bridge is the "PCI bridge" directly above the GPU (e.g. GPU `c1:00.0` → bridge `c0:01.1`). List every such bridge in the `BRIDGES=` line of the script. The register writes it performs:

- `CAP_EXP+30.W=0005` — Link Control 2: Target Link Speed = Gen5
- `CAP_EXP+10.W=0c60` — Link Control: set Retrain Link bit

## 3. NVIDIA module options

`etc/modprobe.d/`:

- `nvidia-drm.conf` — `options nvidia-drm modeset=1` (kernel mode setting).
- `blacklist-nouveau.conf` — blacklist the open-source `nouveau` driver.
- `nvidia-profiler.conf` — `NVreg_RestrictProfilingToAdminUsers=0` (optional; lets non-root use Nsight/profilers — omit if you don't want that).

Use the NVIDIA **Open** kernel module (570 series or newer); it is required for Blackwell (RTX PRO 6000 / RTX 5090) GPUs.

## 4. nvidia-persistenced

`nvidia-persistenced.service` runs the daemon as a dedicated system user. A driver reinstall/upgrade sometimes drops that user, after which the service fails and persistence mode is off. `usr/local/bin/fix-nvidia-persistenced.sh` recreates the user (exactly as the NVIDIA package's postinst does) and starts the daemon:

```bash
sudo /usr/local/bin/fix-nvidia-persistenced.sh
# or simply: sudo apt install --reinstall nvidia-persistenced
```

Don't edit the unit to `--user root`; a driver update would overwrite it.

## Verifying

```bash
cat /proc/cmdline          # the flags from part 1 are present
nvidia-smi                 # all GPUs enumerated?
nvidia-smi --query-gpu=index,name,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max --format=csv
sudo lspci -vv -s <gpu> | grep -E 'LnkCap|LnkSta'   # negotiated speed/width
systemctl status pcie-gen5-fix.service
nvidia-smi --query-gpu=index,persistence_mode --format=csv
```

## Gotchas

- **Idle downclocking is normal.** At idle NVIDIA GPUs drop the link to Gen1 (2.5 GT/s) to save power, so `lspci` shows `2.5GT/s (downgraded)` even when `pcie.link.gen.max` is 4 or 5. They ramp up under load. Check `pcie.link.gen.max`, or measure while a workload runs — don't judge by the idle reading.
- **x8 width** on some GPUs usually means the physical slot is bifurcated (x8x8) — a board/slot layout limit, not fixable in software.
- Everything depends on booting the custom entry. If a kernel update or menu pick lands you on a stock entry with the default flags, GPUs may not all appear — set `GRUB_DEFAULT="multigpu-pcie"` (or fold the flags into `GRUB_CMDLINE_LINUX_DEFAULT`).

## Layout

```
README.md
docs/BIOS-bifurcation.md                    UEFI bifurcation + large-BAR settings, BIOS download links
apply.sh                                    installer (copies files, fills placeholders, enables services)
etc/grub.d/09_multigpu-pcie                 custom boot entry (placeholders for UUID + kernel)
etc/systemd/system/pcie-gen5-fix.service    boot-time Gen5 retrain service
etc/modprobe.d/nvidia-drm.conf              modeset
etc/modprobe.d/nvidia-profiler.conf         optional profiler access
etc/modprobe.d/blacklist-nouveau.conf       blacklist nouveau
usr/local/bin/pcie-gen5-fix.sh              setpci Gen5 retrain (EDIT bridge IDs)
usr/local/bin/fix-nvidia-persistenced.sh    recreate persistenced user + start daemon
```

## License

MIT — do as you like; no warranty. These touch boot and PCIe registers; understand each change before applying.
