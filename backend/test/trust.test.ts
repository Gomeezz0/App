import assert from 'node:assert/strict';
import { test } from 'node:test';
import { coarsen, policyFor } from '../src/alerts/policy.js';
import { confidence, extendedExpiry, level, shouldRemove, userWeight } from '../src/alerts/trust.js';

test('peso del usuario según reputación y antigüedad', () => {
  assert.equal(userWeight(0, 1), 0.3, 'cuenta nueva');
  assert.equal(userWeight(0, 48), 1);
  assert.equal(userWeight(50, 48), 1.5);
  assert.equal(userWeight(500, 48), 1.5, 'tope superior');
  assert.equal(userWeight(-10, 48), 0.9);
  assert.equal(userWeight(-20, 48), 0, 'cuenta limitada');
});

test('la confianza crece con confirmaciones y cae con negativas', () => {
  const solo = confidence({ reporterWeight: 1, confirmWeight: 0, denyWeight: 0 });
  const two = confidence({ reporterWeight: 1, confirmWeight: 1, denyWeight: 0 });
  const three = confidence({ reporterWeight: 1, confirmWeight: 2, denyWeight: 0 });
  assert.ok(solo < two && two < three);
  assert.equal(level(solo), 'medium');
  assert.equal(level(three), 'high');
  assert.equal(level(confidence({ reporterWeight: 0.3, confirmWeight: 0, denyWeight: 0 })), 'low');
  assert.equal(confidence({ reporterWeight: 1, confirmWeight: 0, denyWeight: 1 }), 0);
});

test('retirada: hacen falta negativas suficientes en absoluto y en proporción', () => {
  assert.equal(shouldRemove({ reporterWeight: 1, confirmWeight: 0, denyWeight: 1 }), false);
  assert.equal(shouldRemove({ reporterWeight: 1, confirmWeight: 0, denyWeight: 1.5 }), true);
  assert.equal(shouldRemove({ reporterWeight: 1, confirmWeight: 4, denyWeight: 2 }), false);
  assert.equal(shouldRemove({ reporterWeight: 1, confirmWeight: 4, denyWeight: 3 }), true);
});

test('la caducidad se prolonga con tope y nunca se acorta', () => {
  const created = new Date('2026-01-01T10:00:00Z');
  const expiry = new Date('2026-01-01T10:45:00Z');
  const at = (iso: string) => extendedExpiry(new Date(iso), created, expiry, 45, 180);
  assert.equal(at('2026-01-01T10:05:00Z').toISOString(), expiry.toISOString(), 'no se acorta');
  assert.equal(at('2026-01-01T10:40:00Z').toISOString(), '2026-01-01T11:02:30.000Z');
  const late = extendedExpiry(new Date('2026-01-01T12:50:00Z'), created, new Date('2026-01-01T12:55:00Z'), 45, 180);
  assert.equal(late.toISOString(), '2026-01-01T13:00:00.000Z', 'tope de vida máxima');
});

test('política por país', () => {
  assert.equal(policyFor('ES', 'speed_camera'), 'exact');
  assert.equal(policyFor('es', 'police'), 'zone');
  assert.equal(policyFor('CH', 'police'), 'disabled');
  assert.equal(policyFor(undefined, 'police'), 'zone');
  assert.equal(policyFor('CH', 'accident'), 'exact', 'los tipos no regulados no se tocan');
  assert.deepEqual(coarsen(40.41678, -3.70379), { lat: 40.415, lon: -3.705 });
});
