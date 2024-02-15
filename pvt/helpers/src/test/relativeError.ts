import { expect } from 'chai';
import { Decimal } from 'decimal.js';
import { BigNumberish, bn, pct } from '../numbers';

export function expectEqualWithError(actual: BigNumberish, expected: BigNumberish, error: BigNumberish = 0.001): void {
  actual = bn(actual);
  expected = bn(expected);
  const acceptedError = pct(expected, error);

  expect(actual).to.be.at.least(expected.sub(acceptedError as any) as any);
  expect(actual).to.be.at.most(expected.add(acceptedError as any) as any);
}

export function expectLessThanOrEqualWithError(
  actual: BigNumberish,
  expected: BigNumberish,
  error: BigNumberish = 0.001
): void {
  actual = bn(actual);
  expected = bn(expected);
  const minimumValue = expected.sub(pct(expected, error) as any);

  expect(actual).to.be.at.most(expected as any);
  expect(actual).to.be.at.least(minimumValue as any);
}

export function expectRelativeError(actual: Decimal, expected: Decimal, maxRelativeError: Decimal): void {
  const lessThanOrEqualTo = actual.dividedBy(expected).sub(1).abs().lessThanOrEqualTo(maxRelativeError);
  expect(lessThanOrEqualTo, 'Relative error too big').to.be.true;
}
