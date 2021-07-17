import fs from 'fs';

export function generatePoolAbi() {
  const poolExercise = require('./abi/PoolExercise.json');
  const poolIO = require('./abi/PoolIO.json');
  const poolView = require('./abi/PoolView.json');
  const poolWrite = require('./abi/PoolWrite.json');

  const finalAbi: any[] = poolExercise;
  const registered: string[] = finalAbi
    .filter((el) => el.name)
    .map((el) => el.name);

  for (const abi of [poolIO, poolView, poolWrite]) {
    for (const el of abi) {
      if (!el.name || registered.includes(el.name)) continue;

      registered.push(el.name);
      finalAbi.push(el);
    }
  }

  fs.writeFileSync('./abi/Pool.json', JSON.stringify(finalAbi, null, 2));
}
