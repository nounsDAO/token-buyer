import { BigInt, log } from '@graphprotocol/graph-ts';
import { PaidBackDebt, RegisteredDebt } from '../generated/Payer/Payer';
import { Debt, DebtChange } from '../generated/schema';

export function handleRegisteredDebt(event: RegisteredDebt): void {
  // Update debt
  let debt = Debt.load(event.params.account);

  if (debt == null) {
    debt = new Debt(event.params.account);
    debt.amount = BigInt.fromI32(0);
  }

  debt.amount = debt.amount.plus(event.params.amount);
  debt.save();

  // Create DebtChange
  const debtChange = new DebtChange(
    event.transaction.hash.toHex() + '-' + event.logIndex.toString(),
  );
  debtChange.address = event.params.account;
  debtChange.amount = event.params.amount;
  debtChange.blockTimestamp = event.block.timestamp;
  debtChange.save();
}

export function handlePaidBackDebt(event: PaidBackDebt): void {
  // Update Debt
  let debt = Debt.load(event.params.account);

  if (debt == null) {
    log.error('[handlePaidBackDebt] Debt #{} not found. Hash: {}', [
      event.params.account.toHexString(),
      event.transaction.hash.toHex(),
    ]);
    return;
  }

  debt.amount = debt.amount.minus(event.params.amount);
  debt.save();

  // Create DebtChange
  const debtChange = new DebtChange(
    event.transaction.hash.toHex() + '-' + event.logIndex.toString(),
  );
  debtChange.address = event.params.account;
  debtChange.amount = event.params.amount.neg();
  debtChange.blockTimestamp = event.block.timestamp;
  debtChange.save();
}
