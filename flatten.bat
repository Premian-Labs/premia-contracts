@ECHO OFF
for %%f in (.\contracts\*.sol) do (
  echo "Flattening: %%f"
  sol-merger --export-plugin SPDXLicenseRemovePlugin %%f .\flattened
)

echo "Success"