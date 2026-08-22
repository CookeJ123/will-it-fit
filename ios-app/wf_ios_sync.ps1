# wf_ios_sync.ps1 — refresh the iOS app's web payload after web changes.
# Run from anywhere on the Windows PC: rebuilds the product, copies it into
# www/, and syncs www/ into the native project (ios/App/App/public).
$ErrorActionPreference = 'Stop'
$proj = Split-Path -Parent $MyInvocation.MyCommand.Path   # ...\Will It Fit\ios-app
$wf   = Split-Path -Parent $proj                          # ...\Will It Fit

Write-Host '1/3 build_product.py'
Push-Location $wf
python build_product.py
Pop-Location

Write-Host '2/3 copy web payload -> www/'
Copy-Item "$wf\product-standalone.html" "$proj\www\index.html" -Force
Copy-Item "$wf\pwa\manifest.webmanifest" "$proj\www\" -Force
New-Item -ItemType Directory -Force "$proj\www\icons" | Out-Null
Copy-Item "$wf\pwa\icons\*" "$proj\www\icons\" -Force

Write-Host '3/3 npx cap copy ios'
Push-Location $proj
if (-not (Test-Path "$proj\node_modules")) { npm install --no-audit --no-fund }
npx cap copy ios
Pop-Location
Write-Host 'Done. Commit/AirDrop the ios-app folder to the Mac and rebuild there.'
