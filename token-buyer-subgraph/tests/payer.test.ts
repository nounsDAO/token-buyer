import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll,
  afterEach,
  beforeEach,
} from 'matchstick-as/assembly/index';
import { Address, BigInt } from '@graphprotocol/graph-ts';
import { handlePaidBackDebt, handleRegisteredDebt } from '../src/payer';
import { createPaidBackDebtEvent, createRegisteredDebtEvent } from './payer-utils';
import { Debt, DebtChange } from '../generated/schema';

const BN6 = BigInt.fromI32(10).pow(6);
const user1 = Address.fromString('0x0000000000000000000000000000000000000001');
const amount = BigInt.fromI32(1_000_000).times(BN6);

describe('Debt', () => {
  beforeEach(() => {
    handleRegisteredDebt(createRegisteredDebtEvent(user1, amount));
  });

  afterEach(() => {
    clearStore();
  });

  test('Creates a new Debt entity on RegisteredDebtEvent', () => {
    assert.fieldEquals('Debt', user1.toHexString(), 'amount', '1000000000000');
  });

  test('Adds to existing Debt on RegisteredDebtEvent', () => {
    let amount2 = BigInt.fromI32(2_000_000).times(BN6);

    handleRegisteredDebt(createRegisteredDebtEvent(user1, amount2));

    assert.fieldEquals('Debt', user1.toHexString(), 'amount', '3000000000000');
  });

  test('Removes from debt on PaidBackDebt', () => {
    let amount2 = BigInt.fromI32(300_000).times(BN6);

    handlePaidBackDebt(createPaidBackDebtEvent(user1, amount2, BigInt.zero()));

    assert.fieldEquals('Debt', user1.toHexString(), 'amount', '700000000000');
  });
});

describe('DebtChange', () => {
  test('RegisteredDebt', () => {
    let event = createRegisteredDebtEvent(user1, amount);
    let id = event.transaction.hash.toHex() + '-' + event.logIndex.toString();

    handleRegisteredDebt(event);

    assert.fieldEquals('DebtChange', id, 'address', user1.toHexString());
    assert.fieldEquals('DebtChange', id, 'amount', amount.toString());
    assert.fieldEquals('DebtChange', id, 'blockTimestamp', event.block.timestamp.toString());
  });

  test('PaidBackDebt', () => {
    // Registering debt first to avoid errors because entity doesn't exist for user1
    handleRegisteredDebt(createRegisteredDebtEvent(user1, amount));

    let amount2 = BigInt.fromI32(300_000).times(BN6);
    let event = createPaidBackDebtEvent(user1, amount2, BigInt.zero());
    let id = event.transaction.hash.toHex() + '-' + event.logIndex.toString();

    handlePaidBackDebt(event);

    assert.fieldEquals('DebtChange', id, 'address', user1.toHexString());
    assert.fieldEquals('DebtChange', id, 'amount', '-300000000000');
    assert.fieldEquals('DebtChange', id, 'blockTimestamp', event.block.timestamp.toString());
  });

  afterEach(() => {
    clearStore();
  });
});
