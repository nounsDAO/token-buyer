import { newMockEvent } from 'matchstick-as';
import { ethereum, Address, BigInt } from '@graphprotocol/graph-ts';
import { PaidBackDebt, RegisteredDebt } from '../generated/Payer/Payer';

export function createPaidBackDebtEvent(
  account: Address,
  amount: BigInt,
  remainingDebt: BigInt,
): PaidBackDebt {
  let paidBackDebtEvent = changetype<PaidBackDebt>(newMockEvent());

  paidBackDebtEvent.parameters = new Array();

  paidBackDebtEvent.parameters.push(
    new ethereum.EventParam('account', ethereum.Value.fromAddress(account)),
  );
  paidBackDebtEvent.parameters.push(
    new ethereum.EventParam('amount', ethereum.Value.fromUnsignedBigInt(amount)),
  );
  paidBackDebtEvent.parameters.push(
    new ethereum.EventParam('remainingDebt', ethereum.Value.fromUnsignedBigInt(remainingDebt)),
  );

  return paidBackDebtEvent;
}

export function createRegisteredDebtEvent(account: Address, amount: BigInt): RegisteredDebt {
  let registeredDebtEvent = changetype<RegisteredDebt>(newMockEvent());

  registeredDebtEvent.parameters = new Array();

  registeredDebtEvent.parameters.push(
    new ethereum.EventParam('account', ethereum.Value.fromAddress(account)),
  );
  registeredDebtEvent.parameters.push(
    new ethereum.EventParam('amount', ethereum.Value.fromUnsignedBigInt(amount)),
  );

  return registeredDebtEvent;
}
