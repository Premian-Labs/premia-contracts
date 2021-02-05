import { BigNumberish } from 'ethers';
import { BytesLike } from '@ethersproject/bytes';

interface IOrderCreateProps {
  maker: string;
  side: BigNumberish;
  isDelayedWriting: boolean;
  optionContract: string;
  pricePerUnit: BigNumberish;
  optionId: BigNumberish;
  paymentToken: string;
}

interface IOrder {
  maker: string;
  side: BigNumberish;
  isDelayedWriting: boolean;
  optionContract: string;
  optionId: BigNumberish;
  paymentToken: string;
  pricePerUnit: BigNumberish;
  expirationTime: BigNumberish;
  salt: BigNumberish;
  decimals: BigNumberish;
}

interface IOrderCreated {
  hash: BytesLike;
  maker: string;
  side: BigNumberish;
  isDelayedWriting: boolean;
  optionContract: string;
  optionId: BigNumberish;
  paymentToken: string;
  pricePerUnit: BigNumberish;
  expirationTime: BigNumberish;
  salt: BigNumberish;
  amount: BigNumberish;
  decimals: BigNumberish;
}
