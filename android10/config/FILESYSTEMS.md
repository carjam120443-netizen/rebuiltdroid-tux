# RebuiltDroid Tux — Android 10 Filesystem Layout

This directory describes the Android 10 filesystem components used by the build system.

## Filesystem components

- `system/` — Android framework, system binaries, libraries, permissions, and core system applications.
- `vendor/` — device/vendor-specific binaries, HALs, libraries, and configuration.
- `product/` — product-specific framework configuration and applications.
- `odm/` — device/ODM-specific configuration and hardware components.
- `ramdisk/` — early-boot files used before the main Android filesystem is mounted.

The repository intentionally does **not** store a complete Android 10 proprietary/system image. The build process should obtain a legally redistributable base, extract its filesystem images, and place the extracted contents into these directories before applying RebuiltDroid Tux customizations.

## Expected image sources

The build system can work with filesystem images such as:

- `system.img`
- `vendor.img`
- `product.img`
- `odm.img`
- `ramdisk.img`

Exact images depend on the Android 10 base distribution and target architecture.
