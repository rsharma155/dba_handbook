# Portable package - how to share

This package is self-contained. **Do not rely on any `D:\...` or machine-specific path.**

## Share with others

1. Zip the **entire** package folder (the parent of `docs/` - keep the folder structure).
2. Recipient unzips to any location (Desktop, USB, network share, etc.).
3. Open `Compat160_Targeted_Fixes.html` from the **root of the unzipped folder**.

## What works offline

| Item | How it works |
|------|----------------|
| HTML View / Copy / Download | Scripts are **embedded** in the HTML - no path needed |
| Open file (Script library) | Relative link to `01_Diagnostics/...sql` etc. (needs full zip) |
| Markdown guides | All under `docs/` (relative to package root) |
| Rebuild HTML | Run `build_html.ps1` from the package root (`$PSScriptRoot`) |

## Rebuild after editing SQL

```powershell
cd <path-to-package-root>
powershell -ExecutionPolicy Bypass -File .\build_html.ps1
```

The build script always uses the folder that contains `build_html.ps1` - never a hard-coded drive letter.
