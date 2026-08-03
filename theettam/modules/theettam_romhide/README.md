# Theettam ROM Prop Hide

Standalone Magisk / KernelSU / SukiSU / APatch module for peridot (VoltageOS).

At each boot it uses `resetprop` to:

- **Delete** Custom-ROM identity properties that leak the VoltageOS footprint:
  `ro.modversion`, `ro.voltage.*`, `org.voltage.version`.
- **Normalise** `ro.build.flavor` (`voltage_peridot-user` → `peridot_global-user`).
- **Delete** `sys.oem_unlock_allowed`, whose presence contradicts a locked /
  verified-boot state and reads as a coherence Danger to policy scanners.

`resetprop` edits the live property trie only; ordinary apps cannot read the raw
`/dev/__properties__` layout, so reflection + getprop + native reads stay
consistent with no property-area residue.

**Reversible:** uninstall the module and reboot to restore stock behaviour.

## Notes / scope
- Does **not** touch verified-boot, StrongBox/TEE, or Play Integrity paths.
- ROM-baked signatures (LineageOS `libstagefright` symbol, `hal_lineage`
  sepolicy) are **not** addressable from a module — they need a ROM rebuild.
