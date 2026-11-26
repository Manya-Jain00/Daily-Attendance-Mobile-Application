// Tests for ../firestore.rules, run against the local Firestore emulator.
// Run with:  npm test   (from this folder; needs Java on PATH)
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  where,
  serverTimestamp,
  setDoc,
  updateDoc,
  deleteDoc,
  writeBatch,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-daily-attendance',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const settings = {
  officeStart: '09:30',
  officeEnd: '18:30',
  lateAfter: '09:45',
  halfDayBelowHours: 4,
  supervisorEditDays: 7,
};

/** The test people, by mobile number (E.164), which is how profiles are kept. */
const P = {
  ceo1: '+919000000001',
  ceo2: '+919000000002',
  sup1: '+919000000011',
  sup2: '+919000000012',
  sup3: '+919000000013',
  gone1: '+919000000021',
  intruder: '+919000000031',
  new: '+919000000041',
  new1: '+919000000042',
  newsup: '+919000000051',
  nobody: '+919000000061',
  victim: '+919000000071',
  owner: '+919000000081',
  rival: '+919000000082',
  'm-ravi': '+919000000091',
  'm-sita': '+919000000092',
  acc1: '+919000000101',
  newacc: '+919000000102',
};

/** Firestore as someone logged in by phone (SMS code) with this number. */
const as = (phone) =>
  env.authenticatedContext(`uid-${phone}`, { phone_number: phone }).firestore();

/** The batch the app writes when a director sets up a new company. */
function signUpBatch(db, phone, companyId, overrides = {}) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'companies', companyId), {
    name: 'Acme',
    createdBy: phone,
    createdAt: serverTimestamp(),
    settings,
    ...overrides.company,
  });
  batch.set(doc(db, 'users', phone), {
    companyId,
    role: 'director',
    name: 'Boss',
    phone,
    teamIds: [],
    active: true,
    createdAt: serverTimestamp(),
    ...overrides.user,
  });
  return batch;
}

/** Seeds data directly, bypassing the rules. */
async function seed(fn) {
  await env.withSecurityRulesDisabled((ctx) => fn(ctx.firestore()));
}

async function seedCompany() {
  await seed(async (db) => {
    await setDoc(doc(db, 'companies', 'c1'), {
      name: 'Acme',
      createdBy: P.ceo1,
      settings,
    });
    await setDoc(doc(db, 'companies', 'c2'), {
      name: 'Other firm',
      createdBy: P.ceo2,
      settings,
    });
    const user = (companyId, role, extra = {}) => ({
      companyId,
      role,
      name: 'Someone',
      teamIds: [],
      active: true,
      ...extra,
    });
    const add = (id, companyId, role, extra = {}) =>
      setDoc(doc(db, 'users', id), { ...user(companyId, role, extra), phone: id });
    await add(P.ceo1, 'c1', 'director');
    await add(P.sup1, 'c1', 'supervisor');
    await add(P.gone1, 'c1', 'supervisor', { active: false });
    await add(P.ceo2, 'c2', 'director');
    await add(P.sup2, 'c2', 'supervisor');
    await setDoc(doc(db, 'companies', 'c1', 'teams', 't1'), { name: 'Sales' });
  });
}

describe('company set-up by a new director', () => {
  test('a new login can create a company with itself as director', async () => {
    await assertSucceeds(signUpBatch(as(P.new), P.new, 'newco').commit());
  });

  test('the company alone, without the director profile, is refused', async () => {
    const db = as(P.new);
    await assertFails(
      setDoc(doc(db, 'companies', 'newco'), {
        name: 'Acme',
        createdBy: P.new,
        createdAt: serverTimestamp(),
        settings,
      }),
    );
  });

  test('a director profile alone, without a company, is refused', async () => {
    const db = as(P.new);
    await assertFails(
      setDoc(doc(db, 'users', P.new), {
        companyId: 'newco',
        role: 'director',
        name: 'Boss',
        phone: P.new,
        teamIds: [],
        active: true,
        createdAt: serverTimestamp(),
      }),
    );
  });

  test("can't join an existing company as its director", async () => {
    await seedCompany();
    const db = as(P.intruder);
    await assertFails(
      setDoc(doc(db, 'users', P.intruder), {
        companyId: 'c1',
        role: 'director',
        name: 'Intruder',
        phone: P.intruder,
        teamIds: [],
        active: true,
        createdAt: serverTimestamp(),
      }),
    );
    // Not even by rewriting the company in the same batch.
    await assertFails(signUpBatch(db, P.intruder, 'c1').commit());
  });

  test('someone already in a company cannot create a second one', async () => {
    await seedCompany();
    await assertFails(signUpBatch(as(P.sup1), P.sup1, 'newco').commit());
  });

  test('the profile must be under the login’s own number', async () => {
    await assertFails(
      signUpBatch(as(P.new), P.new, 'newco', {
        user: { phone: P.new1 },
      }).commit(),
    );
    const db = as(P.new);
    const batch = signUpBatch(db, P.new, 'newco');
    batch.set(doc(db, 'users', P.victim), {
      companyId: 'newco',
      role: 'director',
      name: 'X',
      phone: P.victim,
      teamIds: [],
      active: true,
      createdAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('cannot sign up as a supervisor or with teams', async () => {
    await assertFails(
      signUpBatch(as(P.new), P.new, 'newco', {
        user: { role: 'supervisor' },
      }).commit(),
    );
    await assertFails(
      signUpBatch(as(P.new), P.new, 'newco', {
        user: { teamIds: ['t1'] },
      }).commit(),
    );
  });

  test('the company must start with valid settings', async () => {
    await assertFails(
      signUpBatch(as(P.new1), P.new1, 'cNew', {
        company: { settings: { ...settings, supervisorEditDays: 400 } },
      }).commit(),
    );
    await assertFails(
      signUpBatch(as(P.new1), P.new1, 'cNew', { company: { settings: {} } }).commit(),
    );
  });

  test('only phone logins count: an email login can do nothing', async () => {
    await seedCompany();
    const emailOnly = env
      .authenticatedContext('someone', { email: 'boss@test.com' })
      .firestore();
    await assertFails(signUpBatch(emailOnly, P.new, 'newco').commit());
    await assertFails(getDoc(doc(emailOnly, 'companies', 'c1')));
  });

  test('logged-out visitors can do nothing', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(signUpBatch(db, P.new, 'newco').commit());
  });
});

describe('reading profiles', () => {
  beforeEach(seedCompany);

  test('everyone can read their own profile', async () => {
    await assertSucceeds(getDoc(doc(as(P.sup1), 'users', P.sup1)));
    await assertSucceeds(getDoc(doc(as(P.gone1), 'users', P.gone1)));
  });

  test('a login with no profile can check its own (missing) profile', async () => {
    await assertSucceeds(getDoc(doc(as(P.nobody), 'users', P.nobody)));
  });

  test('a director can read profiles in their company only', async () => {
    await assertSucceeds(getDoc(doc(as(P.ceo1), 'users', P.sup1)));
    await assertFails(getDoc(doc(as(P.ceo1), 'users', P.sup2)));
  });

  test("a supervisor can't read other people's profiles", async () => {
    await assertFails(getDoc(doc(as(P.sup1), 'users', P.ceo1)));
  });
});

describe('accountants (Phase 9)', () => {
  beforeEach(seedCompany);

  const newAccountant = (companyId, extra = {}) => ({
    companyId,
    role: 'accountant',
    name: 'New accountant',
    phone: P.newacc,
    teamIds: [],
    active: true,
    createdAt: serverTimestamp(),
    ...extra,
  });

  test('a director adds an accountant to their company, without teams', async () => {
    const db = as(P.ceo1);
    await assertFails(
      setDoc(doc(db, 'users', P.newacc), newAccountant('c1', { teamIds: ['t1'] })),
    );
    await assertFails(setDoc(doc(db, 'users', P.newacc), newAccountant('c2')));
    await assertSucceeds(setDoc(doc(db, 'users', P.newacc), newAccountant('c1')));
    // Supervisors can't add one.
    await assertFails(
      setDoc(doc(as(P.sup1), 'users', P.nobody), {
        ...newAccountant('c1'),
        phone: P.nobody,
      }),
    );
  });

  test('a director renames and deactivates an accountant', async () => {
    const db = as(P.ceo1);
    await assertSucceeds(setDoc(doc(db, 'users', P.newacc), newAccountant('c1')));
    const ref = doc(db, 'users', P.newacc);
    await assertSucceeds(updateDoc(ref, { name: 'Meena', active: false }));
    await assertFails(updateDoc(ref, { teamIds: ['t1'] }));
    await assertFails(updateDoc(ref, { role: 'director' }));
  });

  test("an accountant reads the firm's profiles and data", async () => {
    await seed((db) =>
      setDoc(doc(db, 'users', P.acc1), {
        companyId: 'c1',
        role: 'accountant',
        name: 'Accountant',
        phone: P.acc1,
        teamIds: [],
        active: true,
      }),
    );
    const db = as(P.acc1);
    await assertSucceeds(getDoc(doc(db, 'companies', 'c1')));
    await assertSucceeds(
      getDocs(query(collection(db, 'users'), where('companyId', '==', 'c1'))),
    );
    await assertSucceeds(getDocs(collection(db, 'companies', 'c1', 'attendance')));
    await assertFails(getDoc(doc(db, 'companies', 'c2')));
  });
});

describe('supervisors (Phase 3)', () => {
  beforeEach(seedCompany);

  const newSupervisor = (companyId, phone = P.newsup) => ({
    companyId,
    role: 'supervisor',
    name: 'New supervisor',
    phone,
    teamIds: ['t1'],
    active: true,
    createdAt: serverTimestamp(),
  });

  test('a director can add a supervisor to their company', async () => {
    await assertSucceeds(
      setDoc(doc(as(P.ceo1), 'users', P.newsup), newSupervisor('c1')),
    );
  });

  test("a director can't add a supervisor to another company", async () => {
    await assertFails(
      setDoc(doc(as(P.ceo1), 'users', P.newsup), newSupervisor('c2')),
    );
  });

  test('the profile is kept under a valid mobile number', async () => {
    const db = as(P.ceo1);
    // The number field must match the document it is saved under.
    await assertFails(
      setDoc(doc(db, 'users', P.newsup), newSupervisor('c1', P.nobody)),
    );
    for (const bad of ['9876543210', '+91 98765 43210', 'ravi']) {
      await assertFails(setDoc(doc(db, 'users', bad), newSupervisor('c1', bad)));
    }
    const { phone, ...noPhone } = newSupervisor('c1');
    await assertFails(setDoc(doc(db, 'users', P.newsup), noPhone));
  });

  test('a number already in the app (any firm) cannot be added again', async () => {
    const db = as(P.ceo1);
    await assertFails(setDoc(doc(db, 'users', P.sup2), newSupervisor('c1', P.sup2)));
    await assertFails(setDoc(doc(db, 'users', P.ceo2), newSupervisor('c1', P.ceo2)));
    await assertFails(setDoc(doc(db, 'users', P.sup1), newSupervisor('c1', P.sup1)));
  });

  test('the added supervisor can log in and read their profile and firm', async () => {
    await assertSucceeds(
      setDoc(doc(as(P.ceo1), 'users', P.newsup), newSupervisor('c1')),
    );
    const sup = as(P.newsup);
    await assertSucceeds(getDoc(doc(sup, 'users', P.newsup)));
    await assertSucceeds(getDoc(doc(sup, 'companies', 'c1')));
  });

  test("a director can't change a supervisor's number", async () => {
    await assertFails(
      updateDoc(doc(as(P.ceo1), 'users', P.sup1), { phone: P.nobody }),
    );
  });

  test("a director can't create another director, and supervisors can't add anyone", async () => {
    await assertFails(
      setDoc(doc(as(P.ceo1), 'users', P.newsup), {
        ...newSupervisor('c1'),
        role: 'director',
      }),
    );
    await assertFails(
      setDoc(doc(as(P.sup1), 'users', P.newsup), newSupervisor('c1')),
    );
  });

  test('a director can change a supervisor’s teams and deactivate them', async () => {
    await assertSucceeds(
      updateDoc(doc(as(P.ceo1), 'users', P.sup1), {
        teamIds: ['t1', 't2'],
        active: false,
      }),
    );
  });

  test("a director can't promote a supervisor or move them to another company", async () => {
    await assertFails(
      updateDoc(doc(as(P.ceo1), 'users', P.sup1), { role: 'director' }),
    );
    await assertFails(
      updateDoc(doc(as(P.ceo1), 'users', P.sup1), { companyId: 'c2' }),
    );
    await assertFails(
      updateDoc(doc(as(P.ceo1), 'users', P.sup2), { active: false }),
    );
  });

  test("users can't change their own profile or delete any", async () => {
    await assertFails(
      updateDoc(doc(as(P.sup1), 'users', P.sup1), { role: 'director' }),
    );
    await assertFails(
      updateDoc(doc(as(P.sup1), 'users', P.sup1), { teamIds: ['t9'] }),
    );
    await assertFails(deleteDoc(doc(as(P.ceo1), 'users', P.sup1)));
  });

  test('a deactivated director loses their powers', async () => {
    await seed((db) => updateDoc(doc(db, 'users', P.ceo1), { active: false }));
    await assertFails(
      setDoc(doc(as(P.ceo1), 'users', P.newsup), newSupervisor('c1')),
    );
    await assertFails(getDoc(doc(as(P.ceo1), 'companies', 'c1')));
  });
});

describe('companies and their data', () => {
  beforeEach(seedCompany);

  test('active members can read their own company only', async () => {
    await assertSucceeds(getDoc(doc(as(P.ceo1), 'companies', 'c1')));
    await assertSucceeds(getDoc(doc(as(P.sup1), 'companies', 'c1')));
    await assertFails(getDoc(doc(as(P.gone1), 'companies', 'c1')));
    await assertFails(getDoc(doc(as(P.ceo1), 'companies', 'c2')));
    await assertFails(getDoc(doc(as(P.nobody), 'companies', 'c1')));
  });

  test('the director can rename the company and change settings', async () => {
    await assertSucceeds(
      updateDoc(doc(as(P.ceo1), 'companies', 'c1'), {
        name: 'Acme Pvt Ltd',
        'settings.lateAfter': '10:00',
      }),
    );
  });

  test('settings must have the fields and limits of the Settings screen', async () => {
    const ref = doc(as(P.ceo1), 'companies', 'c1');
    const save = (extra) =>
      updateDoc(ref, { name: 'Acme', settings: { ...settings, ...extra } });
    // What the app writes: the whole settings map, including half hours.
    await assertSucceeds(save({ halfDayBelowHours: 4.5, supervisorEditDays: 0 }));
    await assertSucceeds(save({ halfDayBelowHours: 12, supervisorEditDays: 31 }));
    // Out of range, wrong type, bad time, missing or extra fields.
    await assertFails(save({ supervisorEditDays: 32 }));
    await assertFails(save({ supervisorEditDays: -1 }));
    await assertFails(save({ supervisorEditDays: '7' }));
    await assertFails(save({ supervisorEditDays: 7.5 }));
    await assertFails(save({ halfDayBelowHours: 0 }));
    await assertFails(save({ halfDayBelowHours: 13 }));
    await assertFails(save({ lateAfter: '9:45' }));
    await assertFails(save({ officeEnd: '24:00' }));
    await assertFails(save({ note: 'x' }));
    const { supervisorEditDays, ...missing } = settings;
    await assertFails(updateDoc(ref, { settings: missing }));
    await assertFails(updateDoc(ref, { settings: 'none' }));
  });

  test("supervisors can't change the company; nobody can change its creator", async () => {
    await assertFails(
      updateDoc(doc(as(P.sup1), 'companies', 'c1'), { name: 'Mine now' }),
    );
    await assertFails(
      updateDoc(doc(as(P.ceo1), 'companies', 'c1'), { createdBy: P.sup1 }),
    );
    await assertFails(deleteDoc(doc(as(P.ceo1), 'companies', 'c1')));
  });
});

describe('teams', () => {
  beforeEach(seedCompany);

  const team = (name) => ({ name, createdAt: serverTimestamp() });

  test('the director adds, renames and deletes teams', async () => {
    const db = as(P.ceo1);
    const ref = doc(db, 'companies', 'c1', 'teams', 't2');
    await assertSucceeds(getDoc(doc(db, 'companies', 'c1', 'teams', 't1')));
    await assertSucceeds(setDoc(ref, team('Legal')));
    await assertSucceeds(updateDoc(ref, { name: 'Legal & Compliance' }));
    await assertSucceeds(deleteDoc(ref));
  });

  test('a team is just a valid name', async () => {
    const ref = doc(as(P.ceo1), 'companies', 'c1', 'teams', 't2');
    await assertFails(setDoc(ref, team('')));
    await assertFails(setDoc(ref, team('x'.repeat(101))));
    await assertFails(setDoc(ref, { ...team('Legal'), supervisorIds: [P.sup1] }));
    await assertFails(setDoc(ref, { name: 'Legal' })); // no createdAt
    await assertFails(
      updateDoc(doc(as(P.ceo1), 'companies', 'c1', 'teams', 't1'), {
        extra: 1,
      }),
    );
  });

  test('deleting a team and taking it off its supervisors in one batch', async () => {
    await seed((db) =>
      updateDoc(doc(db, 'users', P.sup1), { teamIds: ['t1', 't9'] }),
    );
    const db = as(P.ceo1);
    const batch = writeBatch(db);
    batch.delete(doc(db, 'companies', 'c1', 'teams', 't1'));
    batch.update(doc(db, 'users', P.sup1), { teamIds: ['t9'] });
    await assertSucceeds(batch.commit());
  });

  test("supervisors can't change teams (yet)", async () => {
    const db = as(P.sup1);
    await assertFails(
      setDoc(doc(db, 'companies', 'c1', 'teams', 't2'), team('Mine')),
    );
    await assertFails(deleteDoc(doc(db, 'companies', 'c1', 'teams', 't1')));
  });

  test('the director can list the company’s supervisors', async () => {
    const { collection, getDocs, query, where } = await import(
      'firebase/firestore'
    );
    const db = as(P.ceo1);
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'users'),
          where('companyId', '==', 'c1'),
          where('role', '==', 'supervisor'),
        ),
      ),
    );
    // ...but not everyone's.
    await assertFails(getDocs(collection(db, 'users')));
    await assertFails(
      getDocs(query(collection(db, 'users'), where('companyId', '==', 'c2'))),
    );
  });

  test("another firm's director can't touch them", async () => {
    const db = as(P.ceo2);
    await assertFails(getDoc(doc(db, 'companies', 'c1', 'teams', 't1')));
    await assertFails(
      setDoc(doc(db, 'companies', 'c1', 'teams', 't2'), team('Hack')),
    );
    await assertFails(deleteDoc(doc(db, 'companies', 'c1', 'teams', 't1')));
  });

  test('top-level collections other than users are closed', async () => {
    await assertFails(setDoc(doc(as(P.ceo1), 'attendance', 'a1'), { x: 1 }));
  });
});

describe('employees and monthly lists (Phase 4)', () => {
  /** 'YYYY-MM' for this month (UTC, as the rules see it) plus [offset]. */
  const monthKey = (offset = 0) => {
    const now = new Date();
    const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + offset, 1));
    return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
  };

  beforeEach(async () => {
    await seedCompany();
    await seed(async (db) => {
      // sup1 looks after Sales (t1) and Accounts (t2); sup3 only Legal (t3).
      await setDoc(doc(db, 'companies', 'c1', 'teams', 't2'), {
        name: 'Accounts',
      });
      await setDoc(doc(db, 'companies', 'c1', 'teams', 't3'), {
        name: 'Legal',
      });
      await updateDoc(doc(db, 'users', P.sup1), { teamIds: ['t1', 't2'] });
      await setDoc(doc(db, 'users', P.sup3), {
        companyId: 'c1',
        companyCode: 'ACME22',
        role: 'supervisor',
        name: 'Other supervisor',
        teamIds: ['t3'],
        active: true,
      });
      await updateDoc(doc(db, 'users', P.gone1), { teamIds: ['t1'] });
      await setDoc(doc(db, 'companies', 'c1', 'employees', 'E1'), {
        empId: 'E1',
        name: 'Asha',
        designation: 'Clerk',
        active: true,
      });
      await setDoc(doc(db, 'companies', 'c1', 'rosters', `t3_${monthKey()}`), {
        teamId: 't3',
        month: monthKey(),
        empIds: ['E1'],
      });
    });
  });

  const employee = (empId, extra = {}) => ({
    empId,
    name: 'New person',
    designation: 'Helper',
    active: true,
    createdAt: serverTimestamp(),
    ...extra,
  });
  const empRef = (db, id) => doc(db, 'companies', 'c1', 'employees', id);

  const roster = (teamId, month, empIds = ['E1'], extra = {}) => ({
    teamId,
    month,
    empIds,
    updatedAt: serverTimestamp(),
    ...extra,
  });
  const rosterRef = (db, teamId, month) =>
    doc(db, 'companies', 'c1', 'rosters', `${teamId}_${month}`);

  test('every member can read the teams, staff list and monthly lists', async () => {
    const { collection, getDocs, query, where } = await import(
      'firebase/firestore'
    );
    for (const uid of [P.sup1, P.sup3, P.ceo1]) {
      const db = as(uid);
      await assertSucceeds(getDocs(collection(db, 'companies', 'c1', 'teams')));
      await assertSucceeds(
        getDocs(collection(db, 'companies', 'c1', 'employees')),
      );
      await assertSucceeds(
        getDocs(
          query(
            collection(db, 'companies', 'c1', 'rosters'),
            where('month', '>=', monthKey(-12)),
            where('month', '<=', monthKey()),
          ),
        ),
      );
    }
  });

  test('only the director adds, edits and deactivates employees', async () => {
    const edit = { name: 'Asha Rao', designation: 'Senior clerk', active: false };
    // Supervisors can't, not even on their own teams.
    await assertFails(setDoc(empRef(as(P.sup3), 'E2'), employee('E2')));
    await assertFails(updateDoc(empRef(as(P.sup3), 'E1'), edit));
    await assertFails(updateDoc(empRef(as(P.sup1), 'E1'), { active: false }));
    // Nor a director of another company.
    await assertFails(setDoc(empRef(as(P.ceo2), 'E2'), employee('E2')));
    const db = as(P.ceo1);
    await assertSucceeds(setDoc(empRef(db, 'E2'), employee('E2')));
    await assertSucceeds(updateDoc(empRef(db, 'E1'), edit));
  });

  test('an employee record must be valid', async () => {
    const db = as(P.ceo1);
    // The Emp ID is the document id, upper case.
    await assertFails(setDoc(empRef(db, 'E2'), employee('E3')));
    await assertFails(setDoc(empRef(db, 'e2'), employee('e2')));
    await assertFails(setDoc(empRef(db, '-2'), employee('-2')));
    await assertFails(setDoc(empRef(db, 'E2'), employee('E2', { name: '' })));
    await assertFails(
      setDoc(empRef(db, 'E2'), employee('E2', { designation: 5 })),
    );
    await assertFails(
      setDoc(empRef(db, 'E2'), employee('E2', { active: false })),
    );
    await assertFails(
      setDoc(empRef(db, 'E2'), employee('E2', { teamIds: ['t1'] })),
    );
    const { createdAt, ...noDate } = employee('E2');
    await assertFails(setDoc(empRef(db, 'E2'), noDate));
    // The Emp ID never changes; an existing record can't be overwritten.
    await assertFails(updateDoc(empRef(db, 'E1'), { empId: 'E9' }));
    await assertFails(setDoc(empRef(db, 'E1'), employee('E1')));
  });

  test('nobody deletes employees or lists', async () => {
    await assertFails(deleteDoc(empRef(as(P.sup1), 'E1')));
    await assertFails(deleteDoc(empRef(as(P.ceo1), 'E1')));
    await assertFails(deleteDoc(rosterRef(as(P.sup3), 't3', monthKey())));
    await assertFails(deleteDoc(rosterRef(as(P.ceo1), 't3', monthKey())));
  });

  test("a supervisor saves their own teams' lists for this month or next", async () => {
    const db = as(P.sup1);
    await assertSucceeds(setDoc(rosterRef(db, 't1', monthKey()), roster('t1', monthKey())));
    await assertSucceeds(
      setDoc(rosterRef(db, 't2', monthKey(1)), roster('t2', monthKey(1), [])),
    );
    // Changing a saved list.
    await assertSucceeds(
      setDoc(rosterRef(db, 't1', monthKey()), roster('t1', monthKey(), ['E1', 'E2'])),
    );
    // Not another supervisor's team.
    await assertFails(setDoc(rosterRef(db, 't3', monthKey()), roster('t3', monthKey())));
    // Not long past or far ahead.
    await assertFails(setDoc(rosterRef(db, 't1', monthKey(-3)), roster('t1', monthKey(-3))));
    await assertFails(setDoc(rosterRef(db, 't1', monthKey(3)), roster('t1', monthKey(3))));
  });

  test('a list must be valid', async () => {
    const db = as(P.sup1);
    const m = monthKey();
    // The id must be {teamId}_{month}.
    await assertFails(setDoc(rosterRef(db, 't1', m), roster('t2', m)));
    await assertFails(setDoc(doc(db, 'companies', 'c1', 'rosters', 'x'), roster('t1', m)));
    await assertFails(setDoc(rosterRef(db, 't1', '2026-1'), roster('t1', '2026-1')));
    await assertFails(setDoc(rosterRef(db, 't1', m), roster('t1', m, 'E1')));
    await assertFails(
      setDoc(rosterRef(db, 't1', m), roster('t1', m, Array(501).fill('E1'))),
    );
    await assertFails(setDoc(rosterRef(db, 't1', m), roster('t1', m, ['E1'], { note: 1 })));
    const { updatedAt, ...noDate } = roster('t1', m);
    await assertFails(setDoc(rosterRef(db, 't1', m), noDate));
  });

  test('only the director adds a new employee and puts them on a list in one batch', async () => {
    const addAndList = (db) => {
      const batch = writeBatch(db);
      batch.set(empRef(db, 'E5'), employee('E5'));
      batch.set(rosterRef(db, 't1', monthKey()), roster('t1', monthKey(), ['E5']));
      return batch.commit();
    };
    // Adding employees is director-only (Phase 9), so a supervisor's batch is
    // refused as a whole: the list isn't saved either.
    await assertFails(addAndList(as(P.sup1)));
    await assertSucceeds(addAndList(as(P.ceo1)));
  });

  test('the director can correct any list, any month', async () => {
    const db = as(P.ceo1);
    await assertSucceeds(setDoc(rosterRef(db, 't3', monthKey(-5)), roster('t3', monthKey(-5))));
    await assertSucceeds(setDoc(rosterRef(db, 't1', monthKey()), roster('t1', monthKey())));
    // The team must exist.
    await assertFails(setDoc(rosterRef(db, 'nope', monthKey()), roster('nope', monthKey())));
    const { collection, getDocs, query, where } = await import(
      'firebase/firestore'
    );
    // The check the app makes before deleting a team.
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'companies', 'c1', 'rosters'),
          where('teamId', '==', 't1'),
        ),
      ),
    );
  });

  test('deactivated supervisors and other firms are kept out', async () => {
    const m = monthKey();
    await assertFails(getDoc(empRef(as(P.gone1), 'E1')));
    await assertFails(setDoc(empRef(as(P.gone1), 'E2'), employee('E2')));
    await assertFails(updateDoc(empRef(as(P.gone1), 'E1'), { name: 'X' }));
    await assertFails(setDoc(rosterRef(as(P.gone1), 't1', m), roster('t1', m)));
    await assertFails(getDoc(empRef(as(P.ceo2), 'E1')));
    await assertFails(setDoc(empRef(as(P.ceo2), 'E2'), employee('E2')));
    await assertFails(getDoc(rosterRef(as(P.ceo2), 't3', m)));
    await assertFails(setDoc(rosterRef(as(P.ceo2), 't1', m), roster('t1', m)));
    await assertFails(getDoc(empRef(as(P.sup2), 'E1')));
    await assertFails(
      getDoc(doc(as(P.sup2), 'companies', 'c1', 'teams', 't1')),
    );
  });
});

describe('daily attendance (Phase 5)', () => {
  /** 'YYYY-MM-DD' for today (UTC, as the rules see it) plus [offset] days. */
  const dayKey = (offset = 0) => {
    const d = new Date(Date.now() + offset * 86400000);
    return d.toISOString().slice(0, 10);
  };

  beforeEach(async () => {
    await seedCompany();
    await seed(async (db) => {
      // sup1 looks after Sales (t1); sup3 only Legal (t3).
      await setDoc(doc(db, 'companies', 'c1', 'teams', 't3'), {
        name: 'Legal',
      });
      await updateDoc(doc(db, 'users', P.sup1), { teamIds: ['t1'] });
      await updateDoc(doc(db, 'users', P.gone1), { teamIds: ['t1'] });
      await setDoc(doc(db, 'users', P.sup3), {
        companyId: 'c1',
        companyCode: 'ACME22',
        role: 'supervisor',
        name: 'Other supervisor',
        teamIds: ['t3'],
        active: true,
      });
      await setDoc(
        doc(db, 'companies', 'c1', 'attendance', `t3_${dayKey()}`),
        { teamId: 't3', date: dayKey(), entries: {}, markedBy: P.sup3 },
      );
    });
  });

  const sheet = (uid, teamId, date, extra = {}) => ({
    teamId,
    date,
    entries: {
      E1: { status: 'present', inTime: '09:30', outTime: '18:30', minutes: 540, late: false },
      E2: { status: 'absent', workingIn: 't3' },
    },
    markedBy: uid,
    updatedAt: serverTimestamp(),
    ...extra,
  });
  const sheetRef = (db, teamId, date) =>
    doc(db, 'companies', 'c1', 'attendance', `${teamId}_${date}`);
  const save = (uid, teamId, date, extra) =>
    setDoc(sheetRef(as(uid), teamId, date), sheet(uid, teamId, date, extra));

  test("a supervisor saves their own team's sheet for today", async () => {
    await assertSucceeds(save(P.sup1, 't1', dayKey()));
    // Saving again replaces it.
    await assertSucceeds(save(P.sup1, 't1', dayKey(), { entries: {} }));
    // Not another supervisor's team.
    await assertFails(save(P.sup1, 't3', dayKey()));
    await assertFails(save(P.sup3, 't1', dayKey()));
  });

  test('a supervisor corrects the last 7 days, but not older or future days', async () => {
    await assertSucceeds(save(P.sup1, 't1', dayKey(-1)));
    await assertSucceeds(save(P.sup1, 't1', dayKey(-7)));
    await assertFails(save(P.sup1, 't1', dayKey(-10)));
    await assertFails(save(P.sup1, 't1', dayKey(3)));
  });

  test("the edit window follows the company's settings", async () => {
    await seed((db) =>
      updateDoc(doc(db, 'companies', 'c1'), {
        'settings.supervisorEditDays': 1,
      }),
    );
    await assertSucceeds(save(P.sup1, 't1', dayKey(-1)));
    await assertFails(save(P.sup1, 't1', dayKey(-4)));
  });

  test('the director corrects any team, any day', async () => {
    await assertSucceeds(save(P.ceo1, 't1', dayKey(-40)));
    await assertSucceeds(save(P.ceo1, 't3', dayKey()));
  });

  test('a sheet must be valid', async () => {
    const d = dayKey();
    // The id must be {teamId}_{date}.
    await assertFails(setDoc(sheetRef(as(P.sup1), 't1', d), sheet(P.sup1, 't3', d)));
    await assertFails(
      setDoc(doc(as(P.sup1), 'companies', 'c1', 'attendance', 'x'), sheet(P.sup1, 't1', d)),
    );
    await assertFails(save(P.sup1, 't1', '2026-1-5'));
    await assertFails(save(P.sup1, 't1', d, { entries: [] }));
    await assertFails(save(P.sup1, 't1', d, { note: 'x' }));
    // Saved under the saver's own number, at the server's time.
    await assertFails(save(P.sup1, 't1', d, { markedBy: P.sup3 }));
    await assertFails(save(P.sup1, 't1', d, { updatedAt: new Date() }));
    // The team must exist (the director too).
    await assertFails(save(P.ceo1, 'nope', d));
  });

  test('every member reads all sheets; nobody deletes them', async () => {
    const { collection, getDocs, query, where } = await import(
      'firebase/firestore'
    );
    for (const uid of [P.sup1, P.sup3, P.ceo1]) {
      await assertSucceeds(
        getDocs(
          query(
            collection(as(uid), 'companies', 'c1', 'attendance'),
            where('date', '>=', dayKey(-31)),
            where('date', '<=', dayKey()),
          ),
        ),
      );
    }
    await assertFails(deleteDoc(sheetRef(as(P.sup3), 't3', dayKey())));
    await assertFails(deleteDoc(sheetRef(as(P.ceo1), 't3', dayKey())));
  });

  test('deactivated supervisors and other firms are kept out', async () => {
    const d = dayKey();
    await assertFails(save(P.gone1, 't1', d));
    await assertFails(getDoc(sheetRef(as(P.gone1), 't3', d)));
    await assertFails(getDoc(sheetRef(as(P.ceo2), 't3', d)));
    await assertFails(getDoc(sheetRef(as(P.sup2), 't3', d)));
    await assertFails(save(P.ceo2, 't1', d));
  });
});

// A whole firm going through the app's real flow, with the same fields the
// app writes (lib/core/data/*_repository.dart, firebase_auth_service.dart).
describe('sample firm, end to end', () => {
  const dayKey = (offset = 0) =>
    new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);
  const monthKey = () => dayKey().slice(0, 7);

  const firm = 'firm1';
  const at = (db, ...path) => doc(db, 'companies', firm, ...path);

  /** The app's addEmployee: check the Emp ID is free, add, put on the list. */
  const addEmployee = (db, empId, name, teamId, list) =>
    runTransaction(db, async (tx) => {
      const ref = at(db, 'employees', empId);
      if ((await tx.get(ref)).exists()) throw new Error('taken');
      tx.set(ref, {
        empId,
        name,
        designation: 'Karigar',
        active: true,
        createdAt: serverTimestamp(),
      });
      tx.set(at(db, 'rosters', `${teamId}_${monthKey()}`), {
        teamId,
        month: monthKey(),
        empIds: [...list, empId],
        updatedAt: serverTimestamp(),
      });
    });

  /** The app's saveAttendance. */
  const saveDay = (db, uid, teamId, date, entries) =>
    setDoc(at(db, 'attendance', `${teamId}_${date}`), {
      teamId,
      date,
      entries,
      markedBy: uid,
      updatedAt: serverTimestamp(),
    });

  const present = (inTime, outTime, minutes, late = false) => ({
    status: 'present',
    inTime,
    outTime,
    minutes,
    late,
  });

  /** The Reports query: every sheet in a date range. */
  const report = (db, from, to) =>
    getDocs(
      query(
        collection(db, 'companies', firm, 'attendance'),
        where('date', '>=', from),
        where('date', '<=', to),
      ),
    );

  test('sign up, set up, mark a week, report, then a supervisor leaves', async () => {
    // 1. The director signs up and creates the firm.
    const owner = as(P.owner);
    await assertSucceeds(signUpBatch(owner, P.owner, firm).commit());

    // 2. Teams and two supervisors.
    for (const [id, name] of [['cut', 'Cutting'], ['sew', 'Stitching']]) {
      await assertSucceeds(
        setDoc(at(owner, 'teams', id), { name, createdAt: serverTimestamp() }),
      );
    }
    for (const [uid, username, teamIds] of [
      [P['m-ravi'], 'ravi', ['cut']],
      [P['m-sita'], 'sita', ['sew']],
    ]) {
      await assertSucceeds(
        setDoc(doc(owner, 'users', uid), {
          companyId: firm,
          role: 'supervisor',
          name: username,
          phone: uid,
          teamIds,
          active: true,
          createdAt: serverTimestamp(),
        }),
      );
    }

    // 3. The director adds the staff to each team; supervisors can't.
    const ravi = as(P['m-ravi']);
    const sita = as(P['m-sita']);
    await assertSucceeds(getDoc(doc(ravi, 'users', P['m-ravi'])));
    await assertSucceeds(getDoc(at(ravi)));
    await assert.rejects(addEmployee(ravi, 'E101', 'Asha', 'cut', []));
    await assertSucceeds(addEmployee(owner, 'E101', 'Asha', 'cut', []));
    await assertSucceeds(addEmployee(owner, 'E102', 'Bilal', 'cut', ['E101']));
    await assertSucceeds(addEmployee(owner, 'E201', 'Chitra', 'sew', []));
    // An Emp ID can't be taken twice, even in another team.
    await assert.rejects(addEmployee(owner, 'E101', 'Someone', 'sew', ['E201']));
    // Ravi can't edit Sita's list.
    await assertFails(
      setDoc(at(ravi, 'rosters', `sew_${monthKey()}`), {
        teamId: 'sew',
        month: monthKey(),
        empIds: ['E201', 'E102'],
        updatedAt: serverTimestamp(),
      }),
    );

    // 4. A week of attendance. Bilal is lent to Stitching on one day.
    for (let offset = -6; offset <= 0; offset++) {
      const date = dayKey(offset);
      const lent = offset === -2;
      await assertSucceeds(
        saveDay(ravi, P['m-ravi'], 'cut', date, {
          E101: present('09:30', '18:30', 540),
          E102: lent
            ? { status: 'absent', workingIn: 'sew' }
            : present('09:50', '14:00', 250, true),
        }),
      );
      await assertSucceeds(
        saveDay(sita, P['m-sita'], 'sew', date, {
          E201: offset === -3 ? { status: 'leave' } : present('09:30', '18:00', 510),
          ...(lent ? { E102: { ...present('09:30', '18:30', 540), guest: true } } : {}),
        }),
      );
    }
    // Nobody marks another team's day, or one outside the edit window.
    await assertFails(saveDay(ravi, P['m-ravi'], 'sew', dayKey(), {}));
    await assertFails(saveDay(ravi, P['m-ravi'], 'cut', dayKey(-20), {}));

    // 5. The director's report sees every sheet; the director corrects an old day.
    const week = await assertSucceeds(report(owner, dayKey(-6), dayKey()));
    assert.equal(week.size, 14);
    await assertSucceeds(
      saveDay(owner, P.owner, 'cut', dayKey(-20), { E101: { status: 'leave' } }),
    );
    // A supervisor sees the other team's sheets too (for lent staff).
    await assertSucceeds(report(sita, dayKey(-6), dayKey()));

    // 6. The director changes settings the way the Settings screen does.
    await assertSucceeds(
      updateDoc(at(owner), {
        name: 'Shree Garments',
        settings: { ...settings, lateAfter: '10:00', supervisorEditDays: 3 },
      }),
    );
    // Now day -5 is outside Ravi's window.
    await assertFails(saveDay(ravi, P['m-ravi'], 'cut', dayKey(-5), {}));
    await assertSucceeds(
      saveDay(ravi, P['m-ravi'], 'cut', dayKey(-1), { E101: present('09:30', '18:30', 540) }),
    );

    // 7. Ravi leaves: the director deactivates him and gives Cutting to Sita.
    await assertSucceeds(
      updateDoc(doc(owner, 'users', P['m-ravi']), { name: 'ravi', teamIds: [], active: false }),
    );
    await assertSucceeds(
      updateDoc(doc(owner, 'users', P['m-sita']), {
        name: 'sita',
        teamIds: ['sew', 'cut'],
        active: true,
      }),
    );
    await assertFails(saveDay(ravi, P['m-ravi'], 'cut', dayKey(), {}));
    await assertFails(report(ravi, dayKey(-6), dayKey()));
    await assertSucceeds(
      saveDay(sita, P['m-sita'], 'cut', dayKey(), { E101: present('09:30', '18:30', 540) }),
    );
    // His past sheets stay, for the monthly report.
    await assertFails(deleteDoc(at(owner, 'attendance', `cut_${dayKey(-6)}`)));

    // 8. Another firm sees none of it.
    const rival = as(P.rival);
    await assertSucceeds(
      signUpBatch(rival, P.rival, 'firm2').commit(),
    );
    await assertFails(report(rival, dayKey(-6), dayKey()));
    await assertFails(getDocs(collection(rival, 'companies', firm, 'employees')));
    await assertFails(getDoc(doc(rival, 'users', P['m-sita'])));
    await assertFails(
      setDoc(at(rival, 'teams', 'x'), { name: 'Mine', createdAt: serverTimestamp() }),
    );
  });
});
