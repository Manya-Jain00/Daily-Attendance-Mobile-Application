// Tests for ../firestore.rules, run against the local Firestore emulator.
// Run with:  npm test   (from this folder; needs Java on PATH)
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
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
  managerEditDays: 7,
};

/** Firestore as a logged-in user with the given uid and email. */
const as = (uid, email = `${uid}@test.com`) =>
  env.authenticatedContext(uid, { email }).firestore();

/** The batch the app writes when a CEO signs up. */
function signUpBatch(db, uid, companyId, overrides = {}) {
  const code = overrides.code ?? 'NEWC23';
  const batch = writeBatch(db);
  batch.set(doc(db, 'companies', companyId), {
    name: 'Acme',
    code,
    createdBy: uid,
    createdAt: serverTimestamp(),
    settings,
    ...overrides.company,
  });
  if (!overrides.skipCodeDoc) {
    batch.set(doc(db, 'companyCodes', overrides.claimCode ?? code), {
      companyId,
    });
  }
  batch.set(doc(db, 'users', uid), {
    companyId,
    companyCode: code,
    role: 'ceo',
    name: 'Boss',
    email: `${uid}@test.com`,
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
      code: 'ACME22',
      createdBy: 'ceo1',
      settings,
    });
    await setDoc(doc(db, 'companyCodes', 'ACME22'), { companyId: 'c1' });
    await setDoc(doc(db, 'companies', 'c2'), {
      name: 'Other firm',
      code: 'XYZW23',
      createdBy: 'ceo2',
      settings,
    });
    await setDoc(doc(db, 'companyCodes', 'XYZW23'), { companyId: 'c2' });
    const codes = { c1: 'ACME22', c2: 'XYZW23' };
    const user = (companyId, role, extra = {}) => ({
      companyId,
      companyCode: codes[companyId],
      role,
      name: 'Someone',
      email: 'x@test.com',
      teamIds: [],
      active: true,
      ...extra,
    });
    await setDoc(doc(db, 'users', 'ceo1'), user('c1', 'ceo'));
    await setDoc(doc(db, 'users', 'mgr1'), user('c1', 'manager'));
    await setDoc(
      doc(db, 'users', 'gone1'),
      user('c1', 'manager', { active: false }),
    );
    await setDoc(doc(db, 'users', 'ceo2'), user('c2', 'ceo'));
    await setDoc(doc(db, 'users', 'mgr2'), user('c2', 'manager'));
    await setDoc(doc(db, 'companies', 'c1', 'teams', 't1'), { name: 'Sales' });
  });
}

describe('CEO sign-up', () => {
  test('a new login can create a company with itself as CEO', async () => {
    await assertSucceeds(signUpBatch(as('new'), 'new', 'newco').commit());
  });

  test('the company alone, without the CEO profile, is refused', async () => {
    const db = as('new');
    await assertFails(
      setDoc(doc(db, 'companies', 'newco'), {
        name: 'Acme',
        code: 'NEWC23',
        createdBy: 'new',
        createdAt: serverTimestamp(),
        settings,
      }),
    );
  });

  test('a CEO profile alone, without a company, is refused', async () => {
    const db = as('new');
    await assertFails(
      setDoc(doc(db, 'users', 'new'), {
        companyId: 'newco',
        companyCode: 'NEWC23',
        role: 'ceo',
        name: 'Boss',
        email: 'new@test.com',
        teamIds: [],
        active: true,
        createdAt: serverTimestamp(),
      }),
    );
  });

  test("can't join an existing company as its CEO", async () => {
    await seedCompany();
    const db = as('intruder');
    await assertFails(
      setDoc(doc(db, 'users', 'intruder'), {
        companyId: 'c1',
        role: 'ceo',
        name: 'Intruder',
        email: 'intruder@test.com',
        teamIds: [],
        active: true,
        createdAt: serverTimestamp(),
      }),
    );
    // Not even by rewriting the company in the same batch.
    await assertFails(signUpBatch(db, 'intruder', 'c1').commit());
  });

  test('someone already in a company cannot create a second one', async () => {
    await seedCompany();
    await assertFails(signUpBatch(as('mgr1'), 'mgr1', 'newco').commit());
  });

  test('must use the login’s own email', async () => {
    await assertFails(
      signUpBatch(as('new'), 'new', 'newco', {
        user: { email: 'someone-else@test.com' },
      }).commit(),
    );
  });

  test('cannot sign up as a manager or with teams', async () => {
    await assertFails(
      signUpBatch(as('new'), 'new', 'newco', {
        user: { role: 'manager' },
      }).commit(),
    );
    await assertFails(
      signUpBatch(as('new'), 'new', 'newco', {
        user: { teamIds: ['t1'] },
      }).commit(),
    );
  });

  test('cannot create a profile for another uid', async () => {
    const db = as('new');
    const batch = signUpBatch(db, 'new', 'newco');
    batch.set(doc(db, 'users', 'victim'), {
      companyId: 'newco',
      role: 'ceo',
      name: 'X',
      email: 'new@test.com',
      teamIds: [],
      active: true,
      createdAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('the company code must be claimed in the same batch', async () => {
    await assertFails(
      signUpBatch(as('new'), 'new', 'newco', { skipCodeDoc: true }).commit(),
    );
    // ...and it must be the company's own code.
    await assertFails(
      signUpBatch(as('new'), 'new', 'newco', { claimCode: 'OTHR23' }).commit(),
    );
  });

  test('a code already taken by another firm is refused', async () => {
    await seedCompany();
    await assertFails(
      signUpBatch(as('new'), 'new', 'newco', { code: 'ACME22' }).commit(),
    );
  });

  test('codes must be 6 characters with no look-alikes', async () => {
    for (const code of ['ABC12', 'ABCDEFG', 'ABCDE0', 'abcdef', 'ABCDEI']) {
      await assertFails(
        signUpBatch(as('new'), 'new', 'newco', { code }).commit(),
      );
    }
  });

  test("the CEO profile must carry the company's code", async () => {
    await assertFails(
      signUpBatch(as('new'), 'new', 'newco', {
        user: { companyCode: 'ZZZZ22' },
      }).commit(),
    );
  });

  test('logged-out visitors can do nothing', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(signUpBatch(db, 'new', 'newco').commit());
  });
});

describe('reading profiles', () => {
  beforeEach(seedCompany);

  test('everyone can read their own profile', async () => {
    await assertSucceeds(getDoc(doc(as('mgr1'), 'users', 'mgr1')));
    await assertSucceeds(getDoc(doc(as('gone1'), 'users', 'gone1')));
  });

  test('a login with no profile can check its own (missing) profile', async () => {
    await assertSucceeds(getDoc(doc(as('nobody'), 'users', 'nobody')));
  });

  test('a CEO can read profiles in their company only', async () => {
    await assertSucceeds(getDoc(doc(as('ceo1'), 'users', 'mgr1')));
    await assertFails(getDoc(doc(as('ceo1'), 'users', 'mgr2')));
  });

  test("a manager can't read other people's profiles", async () => {
    await assertFails(getDoc(doc(as('mgr1'), 'users', 'ceo1')));
  });
});

describe('managing managers (Phase 3)', () => {
  beforeEach(seedCompany);

  const newManager = (companyId) => ({
    companyId,
    companyCode: companyId === 'c1' ? 'ACME22' : 'XYZW23',
    role: 'manager',
    name: 'New manager',
    username: 'ravi',
    email:
      companyId === 'c1'
        ? 'ravi@acme22.login.daily-attendance-b1b1e.firebaseapp.com'
        : 'ravi@xyzw23.login.daily-attendance-b1b1e.firebaseapp.com',
    teamIds: ['t1'],
    active: true,
    createdAt: serverTimestamp(),
  });

  test('a CEO can add a manager to their company', async () => {
    await assertSucceeds(
      setDoc(doc(as('ceo1'), 'users', 'newmgr'), newManager('c1')),
    );
  });

  test("a CEO can't add a manager to another company", async () => {
    await assertFails(
      setDoc(doc(as('ceo1'), 'users', 'newmgr'), newManager('c2')),
    );
  });

  test('a manager needs a valid username and their company’s code', async () => {
    const db = as('ceo1');
    const { username, ...noUsername } = newManager('c1');
    await assertFails(setDoc(doc(db, 'users', 'newmgr'), noUsername));
    await assertFails(
      setDoc(doc(db, 'users', 'newmgr'), {
        ...newManager('c1'),
        username: 'Has Spaces',
      }),
    );
    await assertFails(
      setDoc(doc(db, 'users', 'newmgr'), {
        ...newManager('c1'),
        companyCode: 'XYZW23',
      }),
    );
  });

  test('the email must be the login address made from code + username', async () => {
    await assertFails(
      setDoc(doc(as('ceo1'), 'users', 'newmgr'), {
        ...newManager('c1'),
        email: 'ravi@gmail.com',
      }),
    );
    await assertFails(
      setDoc(doc(as('ceo1'), 'users', 'newmgr'), {
        ...newManager('c1'),
        username: 'priya',
      }),
    );
  });

  test("a CEO can't change a manager's username or code", async () => {
    await assertFails(
      updateDoc(doc(as('ceo1'), 'users', 'mgr1'), { username: 'other' }),
    );
    await assertFails(
      updateDoc(doc(as('ceo1'), 'users', 'mgr1'), { companyCode: 'XYZW23' }),
    );
  });

  test("a CEO can't create another CEO, and managers can't add anyone", async () => {
    await assertFails(
      setDoc(doc(as('ceo1'), 'users', 'newmgr'), {
        ...newManager('c1'),
        role: 'ceo',
      }),
    );
    await assertFails(
      setDoc(doc(as('mgr1'), 'users', 'newmgr'), newManager('c1')),
    );
  });

  test('a CEO can change a manager’s teams and deactivate them', async () => {
    await assertSucceeds(
      updateDoc(doc(as('ceo1'), 'users', 'mgr1'), {
        teamIds: ['t1', 't2'],
        active: false,
      }),
    );
  });

  test("a CEO can't promote a manager or move them to another company", async () => {
    await assertFails(
      updateDoc(doc(as('ceo1'), 'users', 'mgr1'), { role: 'ceo' }),
    );
    await assertFails(
      updateDoc(doc(as('ceo1'), 'users', 'mgr1'), { companyId: 'c2' }),
    );
    await assertFails(
      updateDoc(doc(as('ceo1'), 'users', 'mgr2'), { active: false }),
    );
  });

  test("users can't change their own profile or delete any", async () => {
    await assertFails(
      updateDoc(doc(as('mgr1'), 'users', 'mgr1'), { role: 'ceo' }),
    );
    await assertFails(
      updateDoc(doc(as('mgr1'), 'users', 'mgr1'), { teamIds: ['t9'] }),
    );
    await assertFails(deleteDoc(doc(as('ceo1'), 'users', 'mgr1')));
  });

  test('a deactivated CEO loses their powers', async () => {
    await seed((db) => updateDoc(doc(db, 'users', 'ceo1'), { active: false }));
    await assertFails(
      setDoc(doc(as('ceo1'), 'users', 'newmgr'), newManager('c1')),
    );
    await assertFails(getDoc(doc(as('ceo1'), 'companies', 'c1')));
  });
});

describe('companies and their data', () => {
  beforeEach(seedCompany);

  test('active members can read their own company only', async () => {
    await assertSucceeds(getDoc(doc(as('ceo1'), 'companies', 'c1')));
    await assertSucceeds(getDoc(doc(as('mgr1'), 'companies', 'c1')));
    await assertFails(getDoc(doc(as('gone1'), 'companies', 'c1')));
    await assertFails(getDoc(doc(as('ceo1'), 'companies', 'c2')));
    await assertFails(getDoc(doc(as('nobody'), 'companies', 'c1')));
  });

  test('the CEO can rename the company and change settings', async () => {
    await assertSucceeds(
      updateDoc(doc(as('ceo1'), 'companies', 'c1'), {
        name: 'Acme Pvt Ltd',
        'settings.lateAfter': '10:00',
      }),
    );
  });

  test('the company code never changes and code records are closed', async () => {
    await assertFails(
      updateDoc(doc(as('ceo1'), 'companies', 'c1'), { code: 'NEWC23' }),
    );
    await assertFails(getDoc(doc(as('ceo1'), 'companyCodes', 'ACME22')));
    await assertFails(
      setDoc(doc(as('ceo2'), 'companyCodes', 'ACME22'), { companyId: 'c2' }),
    );
    await assertFails(deleteDoc(doc(as('ceo1'), 'companyCodes', 'ACME22')));
  });

  test("managers can't change the company; nobody can change its creator", async () => {
    await assertFails(
      updateDoc(doc(as('mgr1'), 'companies', 'c1'), { name: 'Mine now' }),
    );
    await assertFails(
      updateDoc(doc(as('ceo1'), 'companies', 'c1'), { createdBy: 'mgr1' }),
    );
    await assertFails(deleteDoc(doc(as('ceo1'), 'companies', 'c1')));
  });
});

describe('teams', () => {
  beforeEach(seedCompany);

  const team = (name) => ({ name, createdAt: serverTimestamp() });

  test('the CEO adds, renames and deletes teams', async () => {
    const db = as('ceo1');
    const ref = doc(db, 'companies', 'c1', 'teams', 't2');
    await assertSucceeds(getDoc(doc(db, 'companies', 'c1', 'teams', 't1')));
    await assertSucceeds(setDoc(ref, team('Legal')));
    await assertSucceeds(updateDoc(ref, { name: 'Legal & Compliance' }));
    await assertSucceeds(deleteDoc(ref));
  });

  test('a team is just a valid name', async () => {
    const ref = doc(as('ceo1'), 'companies', 'c1', 'teams', 't2');
    await assertFails(setDoc(ref, team('')));
    await assertFails(setDoc(ref, team('x'.repeat(101))));
    await assertFails(setDoc(ref, { ...team('Legal'), managerIds: ['mgr1'] }));
    await assertFails(setDoc(ref, { name: 'Legal' })); // no createdAt
    await assertFails(
      updateDoc(doc(as('ceo1'), 'companies', 'c1', 'teams', 't1'), {
        extra: 1,
      }),
    );
  });

  test('deleting a team and taking it off its managers in one batch', async () => {
    await seed((db) =>
      updateDoc(doc(db, 'users', 'mgr1'), { teamIds: ['t1', 't9'] }),
    );
    const db = as('ceo1');
    const batch = writeBatch(db);
    batch.delete(doc(db, 'companies', 'c1', 'teams', 't1'));
    batch.update(doc(db, 'users', 'mgr1'), { teamIds: ['t9'] });
    await assertSucceeds(batch.commit());
  });

  test("managers can't change teams (yet)", async () => {
    const db = as('mgr1');
    await assertFails(
      setDoc(doc(db, 'companies', 'c1', 'teams', 't2'), team('Mine')),
    );
    await assertFails(deleteDoc(doc(db, 'companies', 'c1', 'teams', 't1')));
  });

  test('the CEO can list the company’s managers', async () => {
    const { collection, getDocs, query, where } = await import(
      'firebase/firestore'
    );
    const db = as('ceo1');
    await assertSucceeds(
      getDocs(
        query(
          collection(db, 'users'),
          where('companyId', '==', 'c1'),
          where('role', '==', 'manager'),
        ),
      ),
    );
    // ...but not everyone's.
    await assertFails(getDocs(collection(db, 'users')));
    await assertFails(
      getDocs(query(collection(db, 'users'), where('companyId', '==', 'c2'))),
    );
  });

  test("another firm's CEO can't touch them", async () => {
    const db = as('ceo2');
    await assertFails(getDoc(doc(db, 'companies', 'c1', 'teams', 't1')));
    await assertFails(
      setDoc(doc(db, 'companies', 'c1', 'teams', 't2'), team('Hack')),
    );
    await assertFails(deleteDoc(doc(db, 'companies', 'c1', 'teams', 't1')));
  });

  test('top-level collections other than users are closed', async () => {
    await assertFails(setDoc(doc(as('ceo1'), 'attendance', 'a1'), { x: 1 }));
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
      // mgr1 looks after Sales (t1) and Accounts (t2); mgr3 only Legal (t3).
      await setDoc(doc(db, 'companies', 'c1', 'teams', 't2'), {
        name: 'Accounts',
      });
      await setDoc(doc(db, 'companies', 'c1', 'teams', 't3'), {
        name: 'Legal',
      });
      await updateDoc(doc(db, 'users', 'mgr1'), { teamIds: ['t1', 't2'] });
      await setDoc(doc(db, 'users', 'mgr3'), {
        companyId: 'c1',
        companyCode: 'ACME22',
        role: 'manager',
        name: 'Other manager',
        email: 'x@test.com',
        teamIds: ['t3'],
        active: true,
      });
      await updateDoc(doc(db, 'users', 'gone1'), { teamIds: ['t1'] });
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
    for (const uid of ['mgr1', 'mgr3', 'ceo1']) {
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

  test('any active manager adds and edits employees', async () => {
    const db = as('mgr3');
    await assertSucceeds(setDoc(empRef(db, 'E2'), employee('E2')));
    await assertSucceeds(
      updateDoc(empRef(as('mgr1'), 'E1'), {
        name: 'Asha Rao',
        designation: 'Senior clerk',
        active: false,
      }),
    );
  });

  test('an employee record must be valid', async () => {
    const db = as('mgr1');
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
    await assertFails(deleteDoc(empRef(as('mgr1'), 'E1')));
    await assertFails(deleteDoc(empRef(as('ceo1'), 'E1')));
    await assertFails(deleteDoc(rosterRef(as('mgr3'), 't3', monthKey())));
    await assertFails(deleteDoc(rosterRef(as('ceo1'), 't3', monthKey())));
  });

  test("a manager saves their own teams' lists for this month or next", async () => {
    const db = as('mgr1');
    await assertSucceeds(setDoc(rosterRef(db, 't1', monthKey()), roster('t1', monthKey())));
    await assertSucceeds(
      setDoc(rosterRef(db, 't2', monthKey(1)), roster('t2', monthKey(1), [])),
    );
    // Changing a saved list.
    await assertSucceeds(
      setDoc(rosterRef(db, 't1', monthKey()), roster('t1', monthKey(), ['E1', 'E2'])),
    );
    // Not another manager's team.
    await assertFails(setDoc(rosterRef(db, 't3', monthKey()), roster('t3', monthKey())));
    // Not long past or far ahead.
    await assertFails(setDoc(rosterRef(db, 't1', monthKey(-3)), roster('t1', monthKey(-3))));
    await assertFails(setDoc(rosterRef(db, 't1', monthKey(3)), roster('t1', monthKey(3))));
  });

  test('a list must be valid', async () => {
    const db = as('mgr1');
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

  test('adding a new employee and putting them on a list in one batch', async () => {
    const db = as('mgr1');
    const batch = writeBatch(db);
    batch.set(empRef(db, 'E5'), employee('E5'));
    batch.set(rosterRef(db, 't1', monthKey()), roster('t1', monthKey(), ['E5']));
    await assertSucceeds(batch.commit());
  });

  test('the CEO can correct any list, any month', async () => {
    const db = as('ceo1');
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

  test('deactivated managers and other firms are kept out', async () => {
    const m = monthKey();
    await assertFails(getDoc(empRef(as('gone1'), 'E1')));
    await assertFails(setDoc(empRef(as('gone1'), 'E2'), employee('E2')));
    await assertFails(updateDoc(empRef(as('gone1'), 'E1'), { name: 'X' }));
    await assertFails(setDoc(rosterRef(as('gone1'), 't1', m), roster('t1', m)));
    await assertFails(getDoc(empRef(as('ceo2'), 'E1')));
    await assertFails(setDoc(empRef(as('ceo2'), 'E2'), employee('E2')));
    await assertFails(getDoc(rosterRef(as('ceo2'), 't3', m)));
    await assertFails(setDoc(rosterRef(as('ceo2'), 't1', m), roster('t1', m)));
    await assertFails(getDoc(empRef(as('mgr2'), 'E1')));
    await assertFails(
      getDoc(doc(as('mgr2'), 'companies', 'c1', 'teams', 't1')),
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
      // mgr1 looks after Sales (t1); mgr3 only Legal (t3).
      await setDoc(doc(db, 'companies', 'c1', 'teams', 't3'), {
        name: 'Legal',
      });
      await updateDoc(doc(db, 'users', 'mgr1'), { teamIds: ['t1'] });
      await updateDoc(doc(db, 'users', 'gone1'), { teamIds: ['t1'] });
      await setDoc(doc(db, 'users', 'mgr3'), {
        companyId: 'c1',
        companyCode: 'ACME22',
        role: 'manager',
        name: 'Other manager',
        email: 'x@test.com',
        teamIds: ['t3'],
        active: true,
      });
      await setDoc(
        doc(db, 'companies', 'c1', 'attendance', `t3_${dayKey()}`),
        { teamId: 't3', date: dayKey(), entries: {}, markedBy: 'mgr3' },
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

  test("a manager saves their own team's sheet for today", async () => {
    await assertSucceeds(save('mgr1', 't1', dayKey()));
    // Saving again replaces it.
    await assertSucceeds(save('mgr1', 't1', dayKey(), { entries: {} }));
    // Not another manager's team.
    await assertFails(save('mgr1', 't3', dayKey()));
    await assertFails(save('mgr3', 't1', dayKey()));
  });

  test('a manager corrects the last 7 days, but not older or future days', async () => {
    await assertSucceeds(save('mgr1', 't1', dayKey(-1)));
    await assertSucceeds(save('mgr1', 't1', dayKey(-7)));
    await assertFails(save('mgr1', 't1', dayKey(-10)));
    await assertFails(save('mgr1', 't1', dayKey(3)));
  });

  test("the edit window follows the company's settings", async () => {
    await seed((db) =>
      updateDoc(doc(db, 'companies', 'c1'), {
        'settings.managerEditDays': 1,
      }),
    );
    await assertSucceeds(save('mgr1', 't1', dayKey(-1)));
    await assertFails(save('mgr1', 't1', dayKey(-4)));
  });

  test('the CEO corrects any team, any day', async () => {
    await assertSucceeds(save('ceo1', 't1', dayKey(-40)));
    await assertSucceeds(save('ceo1', 't3', dayKey()));
  });

  test('a sheet must be valid', async () => {
    const d = dayKey();
    // The id must be {teamId}_{date}.
    await assertFails(setDoc(sheetRef(as('mgr1'), 't1', d), sheet('mgr1', 't3', d)));
    await assertFails(
      setDoc(doc(as('mgr1'), 'companies', 'c1', 'attendance', 'x'), sheet('mgr1', 't1', d)),
    );
    await assertFails(save('mgr1', 't1', '2026-1-5'));
    await assertFails(save('mgr1', 't1', d, { entries: [] }));
    await assertFails(save('mgr1', 't1', d, { note: 'x' }));
    // Saved under the saver's own uid, at the server's time.
    await assertFails(save('mgr1', 't1', d, { markedBy: 'mgr3' }));
    await assertFails(save('mgr1', 't1', d, { updatedAt: new Date() }));
    // The team must exist (the CEO too).
    await assertFails(save('ceo1', 'nope', d));
  });

  test('every member reads all sheets; nobody deletes them', async () => {
    const { collection, getDocs, query, where } = await import(
      'firebase/firestore'
    );
    for (const uid of ['mgr1', 'mgr3', 'ceo1']) {
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
    await assertFails(deleteDoc(sheetRef(as('mgr3'), 't3', dayKey())));
    await assertFails(deleteDoc(sheetRef(as('ceo1'), 't3', dayKey())));
  });

  test('deactivated managers and other firms are kept out', async () => {
    const d = dayKey();
    await assertFails(save('gone1', 't1', d));
    await assertFails(getDoc(sheetRef(as('gone1'), 't3', d)));
    await assertFails(getDoc(sheetRef(as('ceo2'), 't3', d)));
    await assertFails(getDoc(sheetRef(as('mgr2'), 't3', d)));
    await assertFails(save('ceo2', 't1', d));
  });
});
