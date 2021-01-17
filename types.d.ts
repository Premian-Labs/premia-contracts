import { BigNumberish } from 'ethers';
import { BytesLike } from '@ethersproject/bytes';

interface IOrderCreateProps {
  maker: string;
  taker: string;
  side: BigNumberish;
  optionContract: string;
  pricePerUnit: BigNumberish;
  optionId: BigNumberish;
  paymentToken: string;
}

interface IOrder {
  maker: string;
  taker: string;
  side: BigNumberish;
  optionContract: string;
  optionId: BigNumberish;
  paymentToken: string;
  pricePerUnit: BigNumberish;
  decimals: BigNumberish;
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
  paymentToken: string;
  pricePerUnit: BigNumberish;
  decimals: BigNumberish;
  expirationTime: BigNumberish;
  salt: BigNumberish;
  amount: BigNumberish;
}
