$ErrorActionPreference = 'Stop'

# Chocolatey removes the unpacked bundle itself; the Start Menu shortcut was
# created outside the package directory, so it has to be removed here.
$shortcut = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Alera.lnk'
if (Test-Path $shortcut) {
  Remove-Item $shortcut -Force
}
