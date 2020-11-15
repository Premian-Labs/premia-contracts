@ECHO OFF
for %%f in (.\contracts\*.sol) do (
  echo "Flattening: %%f"
  truffle-flattener %%f --output .\flattened\%%~nf.sol
)

echo "Success"
PAUSE