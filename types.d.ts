import { BigNumberish } from 'ethers';
import { BytesLike } from '@ethersproject/bytes';

interface IOrderCreateProps {
  maker: string;
  taker: string;
  side: number;
  optionContract: string;
  pricePerUnit: BigNumberish;
  optionId: BigNumberish;
}

interface IOrder {
  maker: string;
  taker: string;
  side: BigNumberish;
  optionContract: string;
  optionId: BigNumberish;
  pricePerUnit: BigNumberish;
  expirationTime: BigNumberish;
  salt: BigNumberish;
}

interface IOrderCreated {
  hash: BytesLike;
  maker: string;
  taker: string;
  side: BigNumberish;
  optionContract: string;
  optionId: BigNumberish;
  pricePerUnit: BigNumberish;
  expirationTime: BigNumberish;
  salt: BigNumberish;
  amount: BigNumberish;
}
