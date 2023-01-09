export async function getEvent(tx: any, event: string) {
  let receipt = await tx.wait();
  return receipt.events?.filter((x: any) => {
    return x.event == event;
  });
}

export async function getEventArgs(tx: any, event: string) {
  return [(await getEvent(tx, event)).map((x: any) => x?.args)];
}
