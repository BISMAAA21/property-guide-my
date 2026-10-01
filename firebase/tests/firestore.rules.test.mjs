import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { after, afterEach, before, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  deleteField,
  doc,
  collection,
  getDoc,
  getDocs,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-property-guidance',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

afterEach(async () => environment.clearFirestore());
after(async () => environment.cleanup());

function userDocument(database, uid) {
  return doc(database, 'users', uid);
}

async function seedProfile(uid, role, status = 'active') {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(userDocument(context.firestore(), uid), {
      name: uid,
      email: `${uid}@example.test`,
      role,
      status,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
}

function propertyDocument(database, propertyId) {
  return doc(database, 'properties', propertyId);
}

function propertyData(agentId, overrides = {}) {
  return {
    agentId,
    propertyName: 'Demo Student Residence',
    location: 'Cyberjaya, Selangor',
    normalizedLocation: 'cyberjaya, selangor',
    monthlyRent: 1450,
    bedrooms: 2,
    bathrooms: 1,
    propertyType: 'apartment',
    description: 'A controlled demonstration property close to student facilities.',
    facilities: ['Wi-Fi', 'Study area'],
    imageUrls: [],
    approvalStatus: 'draft',
    ratingAverage: 0,
    ratingCount: 0,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

async function seedProperty(propertyId, agentId, overrides = {}) {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      propertyDocument(context.firestore(), propertyId),
      propertyData(agentId, overrides),
    );
  });
}

function reviewDocument(database, propertyId, studentId) {
  return doc(database, 'reviews', `${propertyId}_${studentId}`);
}

const inspectionChecks = [
  ['living_walls_ceiling', 'living_room'],
  ['living_windows_doors', 'living_room'],
  ['living_floor_furniture', 'living_room'],
  ['bedroom_walls_ceiling', 'bedroom'],
  ['bedroom_windows_locks', 'bedroom'],
  ['bedroom_storage_furniture', 'bedroom'],
  ['bathroom_water_drainage', 'bathroom'],
  ['bathroom_toilet_leaks', 'bathroom'],
  ['bathroom_ventilation_mold', 'bathroom'],
  ['kitchen_sink_plumbing', 'kitchen'],
  ['kitchen_appliances', 'kitchen'],
  ['kitchen_storage_pests', 'kitchen'],
  ['utilities_water_electricity', 'utilities'],
  ['utilities_sockets_lights', 'utilities'],
  ['utilities_internet_cooling', 'utilities'],
  ['safety_access_locks', 'safety'],
  ['safety_fire_equipment', 'safety'],
  ['safety_hazards_exits', 'safety'],
];

function inspectionResults(state = 'not_checked') {
  return Object.fromEntries(
    inspectionChecks.map(([checkId, sectionId]) => [
      checkId,
      { checkId, sectionId, state, note: '' },
    ]),
  );
}

function inspectionDocument(database, propertyId, studentId) {
  return doc(database, 'inspections', `${propertyId}_${studentId}`);
}

function inspectionData(studentId, propertyId, results = inspectionResults()) {
  return {
    studentId,
    propertyId,
    propertyName: 'Demo Student Residence',
    checklistVersion: '1.0.0',
    status: 'in_progress',
    results,
    startedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function verificationReportDocument(database, reportId) {
  return doc(database, 'verificationReports', reportId);
}

function verificationReportData(studentId, propertyId, overrides = {}) {
  return {
    studentId,
    propertyId,
    propertyName: 'Demo Student Residence',
    visitImagePath:
      `students/${studentId}/verifications/report-one/visit.jpg`,
    bestListingImageUrl: 'https://example.test/listing-one.jpg',
    bestListingImageIndex: 0,
    similarityScore: 91.2,
    similarityLevel: 'high',
    possibleMismatch: false,
    mismatchWarning: null,
    guidance:
      'The visit image appears reasonably similar to one approved listing image. Continue checking the address, surroundings, and property details in person.',
    disclaimer:
      'AI-assisted guidance only; this does not guarantee that the property or listing is genuine.',
    modelId: 'controlled-model',
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function damageReportDocument(database, reportId) {
  return doc(database, 'damageReports', reportId);
}

function damageReportData(studentId, propertyId, overrides = {}) {
  return {
    studentId,
    propertyId,
    imagePath: `students/${studentId}/damage/damage-report-one/damage.jpg`,
    sourceType: 'upload',
    inspectionId: null,
    checkId: null,
    damageClass: 'wall_crack',
    modelScore: 0.81,
    boundingBox: null,
    recommendation:
      'The model noticed visual features consistent with a possible wall crack. Inspect the area closely, ask about previous repairs, and seek a qualified professional if concerned.',
    disclaimer:
      'AI-assisted observation only; this does not confirm damage or replace a qualified property inspection.',
    modelId: 'controlled-damage-model',
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

function agreementDocument(database, agreementId) {
  return doc(database, 'agreements', agreementId);
}

function agreementData(studentId, agreementId, overrides = {}) {
  return {
    studentId,
    documentPath:
      `students/${studentId}/agreements/${agreementId}/document.pdf`,
    filename: 'sample-tenancy.pdf',
    extractionMethod: 'mixed',
    clauses: [
      {
        id: 'clause-1',
        title: 'Rent',
        original: '1. RENT\nThe tenant pays RM 1,500 monthly.',
        simplified: 'You pay RM 1,500 every month.',
        importantPoints: ['Monthly payment', 'RM 1,500'],
      },
      {
        id: 'clause-2',
        title: 'Deposit',
        original: '2. DEPOSIT\nThe tenant pays a deposit before moving in.',
        simplified: 'You pay a deposit before moving in.',
        importantPoints: ['Payment is due before moving in'],
      },
    ],
    disclaimer:
      'This is simplified legal information, not legal advice. Verify important terms with a qualified professional.',
    modelId: 'controlled-agreement-model',
    processingStatus: 'completed',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

async function seedDamageInspection(
  inspectionId,
  studentId,
  propertyId,
  checkId,
  imagePath,
) {
  const results = inspectionResults('satisfactory');
  results[checkId] = {
    ...results[checkId],
    state: 'concern',
    note: 'Possible visible concern.',
    concernImagePath: imagePath,
    concernImageUrl: 'https://example.test/concern.jpg',
  };
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'inspections', inspectionId), {
      studentId,
      propertyId,
      propertyName: 'Demo Student Residence',
      checklistVersion: '1.0.0',
      status: 'completed',
      results,
      startedAt: new Date(),
      updatedAt: new Date(),
      completedAt: new Date(),
    });
  });
}

async function saveReview(database, propertyId, studentId, rating, comment) {
  const propertyReference = propertyDocument(database, propertyId);
  const reviewReference = reviewDocument(database, propertyId, studentId);
  await runTransaction(database, async (transaction) => {
    const propertySnapshot = await transaction.get(propertyReference);
    const reviewSnapshot = await transaction.get(reviewReference);
    const property = propertySnapshot.data();
    const oldRating = reviewSnapshot.exists() ? reviewSnapshot.data().rating : 0;
    const nextCount = reviewSnapshot.exists()
      ? property.ratingCount
      : property.ratingCount + 1;
    const nextAverage =
      (property.ratingAverage * property.ratingCount - oldRating + rating) /
      nextCount;
    transaction.set(reviewReference, {
      propertyId,
      studentId,
      studentName: studentId,
      rating,
      comment,
      createdAt: reviewSnapshot.exists()
        ? reviewSnapshot.data().createdAt
        : serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    transaction.update(propertyReference, {
      ratingAverage: nextAverage,
      ratingCount: nextCount,
      updatedAt: serverTimestamp(),
    });
  });
}

test('student self-registration can create only an active student profile', async () => {
  const uid = 'student-one';
  const email = 'student-one@example.test';
  const profile = {
    name: 'Student One',
    email,
    role: 'student',
    status: 'active',
    createdAt: new Date(),
    updatedAt: new Date(),
  };
  const database = environment.authenticatedContext(uid, { email }).firestore();

  await assertSucceeds(setDoc(userDocument(database, uid), profile));
  await assertFails(
    setDoc(userDocument(database, 'promoted-user'), {
      ...profile,
      role: 'agent',
    }),
  );
});

test('student cannot change their role or status', async () => {
  const uid = 'student-two';
  await seedProfile(uid, 'student');
  const database = environment
    .authenticatedContext(uid, { email: `${uid}@example.test` })
    .firestore();

  await assertFails(updateDoc(userDocument(database, uid), { role: 'admin' }));
  await assertFails(updateDoc(userDocument(database, uid), { status: 'disabled' }));
  await assertSucceeds(
    updateDoc(userDocument(database, uid), {
      name: 'Updated Student',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('active administrator can read profiles and change status without changing role', async () => {
  await seedProfile('admin-one', 'admin');
  await seedProfile('student-three', 'student');
  const database = environment
    .authenticatedContext('admin-one', { email: 'admin-one@example.test' })
    .firestore();

  await assertSucceeds(getDoc(userDocument(database, 'student-three')));
  await assertSucceeds(
    updateDoc(userDocument(database, 'student-three'), {
      status: 'disabled',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(userDocument(database, 'student-three'), { role: 'agent' }),
  );
});

test('agent can maintain professional profile fields without changing role', async () => {
  await seedProfile('profile-agent', 'agent');
  await seedProfile('profile-student', 'student');
  const agentDatabase = environment.authenticatedContext('profile-agent').firestore();
  const studentDatabase = environment.authenticatedContext('profile-student').firestore();

  await assertSucceeds(
    updateDoc(userDocument(agentDatabase, 'profile-agent'), {
      name: 'Demo Property Agent',
      agencyName: 'Student Homes Malaysia',
      phone: '+60 12 345 6789',
      registrationNumber: 'REN-DEMO-001',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(userDocument(studentDatabase, 'profile-student'), {
      agencyName: 'Unauthorized Agency',
      phone: '+60 12 000 0000',
      registrationNumber: 'REN-INVALID',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(userDocument(agentDatabase, 'profile-agent'), {
      role: 'admin',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('disabled user can read only their account state', async () => {
  await seedProfile('disabled-user', 'student', 'disabled');
  await seedProfile('other-user', 'student');
  const database = environment
    .authenticatedContext('disabled-user', {
      email: 'disabled-user@example.test',
    })
    .firestore();

  const ownProfile = await assertSucceeds(
    getDoc(userDocument(database, 'disabled-user')),
  );
  assert.equal(ownProfile.data().status, 'disabled');
  await assertFails(getDoc(userDocument(database, 'other-user')));
});

test('active student can read only an active public agent profile', async () => {
  await seedProfile('profile-student', 'student');
  await seedProfile('public-agent', 'agent');
  await seedProfile('disabled-agent', 'agent', 'disabled');
  const studentDatabase = environment.authenticatedContext('profile-student').firestore();

  await assertSucceeds(getDoc(userDocument(studentDatabase, 'public-agent')));
  await assertFails(getDoc(userDocument(studentDatabase, 'disabled-agent')));
});

test('agent can create only a valid draft owned by their account', async () => {
  await seedProfile('agent-one', 'agent');
  await seedProfile('student-four', 'student');
  const agentDatabase = environment
    .authenticatedContext('agent-one', { email: 'agent-one@example.test' })
    .firestore();
  const studentDatabase = environment
    .authenticatedContext('student-four', { email: 'student-four@example.test' })
    .firestore();

  await assertSucceeds(
    setDoc(propertyDocument(agentDatabase, 'agent-draft'), propertyData('agent-one')),
  );
  await assertFails(
    setDoc(
      propertyDocument(agentDatabase, 'spoofed-draft'),
      propertyData('another-agent'),
    ),
  );
  await assertFails(
    setDoc(
      propertyDocument(studentDatabase, 'student-draft'),
      propertyData('student-four'),
    ),
  );
});

test('private drafts are restricted to the owner and administrator', async () => {
  await seedProfile('owner-agent', 'agent');
  await seedProfile('other-agent', 'agent');
  await seedProfile('draft-admin', 'admin');
  await seedProfile('draft-student', 'student');
  await seedProperty('private-draft', 'owner-agent');

  const ownerDatabase = environment.authenticatedContext('owner-agent').firestore();
  const otherDatabase = environment.authenticatedContext('other-agent').firestore();
  const adminDatabase = environment.authenticatedContext('draft-admin').firestore();
  const studentDatabase = environment.authenticatedContext('draft-student').firestore();

  await assertSucceeds(getDoc(propertyDocument(ownerDatabase, 'private-draft')));
  await assertSucceeds(getDoc(propertyDocument(adminDatabase, 'private-draft')));
  await assertFails(getDoc(propertyDocument(otherDatabase, 'private-draft')));
  await assertFails(getDoc(propertyDocument(studentDatabase, 'private-draft')));
  await assertSucceeds(
    updateDoc(propertyDocument(ownerDatabase, 'private-draft'), {
      propertyName: 'Updated Demo Residence',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(propertyDocument(otherDatabase, 'private-draft'), {
      propertyName: 'Unauthorized edit',
      updatedAt: serverTimestamp(),
    }),
  );
});

test('agent submits, admin approves, student reads, and agent deactivates', async () => {
  await seedProfile('lifecycle-agent', 'agent');
  await seedProfile('lifecycle-admin', 'admin');
  await seedProfile('lifecycle-student', 'student');
  await seedProperty('lifecycle-property', 'lifecycle-agent', {
    imageUrls: ['https://example.test/listing.jpg'],
  });
  const agentDatabase = environment.authenticatedContext('lifecycle-agent').firestore();
  const adminDatabase = environment.authenticatedContext('lifecycle-admin').firestore();
  const studentDatabase = environment.authenticatedContext('lifecycle-student').firestore();
  const agentProperty = propertyDocument(agentDatabase, 'lifecycle-property');
  const adminProperty = propertyDocument(adminDatabase, 'lifecycle-property');
  const studentProperty = propertyDocument(studentDatabase, 'lifecycle-property');

  await assertSucceeds(
    updateDoc(agentProperty, {
      approvalStatus: 'pending',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(getDoc(studentProperty));
  await assertFails(
    updateDoc(agentProperty, {
      approvalStatus: 'approved',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(adminProperty, {
      approvalStatus: 'approved',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(getDoc(studentProperty));
  await assertSucceeds(
    updateDoc(agentProperty, {
      approvalStatus: 'inactive',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(getDoc(studentProperty));
});

test('administrator rejection requires feedback and allows corrected resubmission', async () => {
  await seedProfile('revision-agent', 'agent');
  await seedProfile('revision-admin', 'admin');
  await seedProperty('revision-property', 'revision-agent', {
    imageUrls: ['https://example.test/revision.jpg'],
    approvalStatus: 'pending',
  });
  const agentDatabase = environment.authenticatedContext('revision-agent').firestore();
  const adminDatabase = environment.authenticatedContext('revision-admin').firestore();
  const agentProperty = propertyDocument(agentDatabase, 'revision-property');
  const adminProperty = propertyDocument(adminDatabase, 'revision-property');

  await assertFails(
    updateDoc(adminProperty, {
      approvalStatus: 'rejected',
      rejectionReason: 'No',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(adminProperty, {
      approvalStatus: 'rejected',
      rejectionReason: 'Add a clearer bedroom photograph.',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(agentProperty, {
      description: 'A corrected controlled demonstration property with clearer details.',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(agentProperty, {
      approvalStatus: 'pending',
      rejectionReason: deleteField(),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('only an administrator can permanently remove a listing', async () => {
  await seedProfile('remove-agent', 'agent');
  await seedProfile('remove-admin', 'admin');
  await seedProperty('remove-property', 'remove-agent');
  const agentDatabase = environment.authenticatedContext('remove-agent').firestore();
  const adminDatabase = environment.authenticatedContext('remove-admin').firestore();

  await assertFails(deleteDoc(propertyDocument(agentDatabase, 'remove-property')));
  await assertSucceeds(deleteDoc(propertyDocument(adminDatabase, 'remove-property')));
});

test('student creates one deterministic review and edits its rating aggregate', async () => {
  await seedProfile('review-agent', 'agent');
  await seedProfile('review-student', 'student');
  await seedProperty('review-property', 'review-agent', {
    approvalStatus: 'approved',
  });
  const studentDatabase = environment.authenticatedContext('review-student').firestore();

  await assertSucceeds(
    saveReview(
      studentDatabase,
      'review-property',
      'review-student',
      4,
      'A useful student property review.',
    ),
  );
  let property = await getDoc(propertyDocument(studentDatabase, 'review-property'));
  assert.equal(property.data().ratingCount, 1);
  assert.equal(property.data().ratingAverage, 4);

  await assertFails(
    setDoc(doc(studentDatabase, 'reviews', 'non-deterministic-id'), {
      propertyId: 'review-property',
      studentId: 'review-student',
      studentName: 'review-student',
      rating: 5,
      comment: 'This identifier must not be accepted.',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    saveReview(
      studentDatabase,
      'review-property',
      'review-student',
      2,
      'Updated after another property visit.',
    ),
  );
  property = await getDoc(propertyDocument(studentDatabase, 'review-property'));
  assert.equal(property.data().ratingCount, 1);
  assert.equal(property.data().ratingAverage, 2);
});

test('non-student and pending-property review writes are denied', async () => {
  await seedProfile('write-agent', 'agent');
  await seedProfile('pending-student', 'student');
  await seedProperty('pending-review-property', 'write-agent', {
    approvalStatus: 'pending',
  });
  const agentDatabase = environment.authenticatedContext('write-agent').firestore();
  const studentDatabase = environment.authenticatedContext('pending-student').firestore();

  await assertFails(
    saveReview(
      agentDatabase,
      'pending-review-property',
      'write-agent',
      5,
      'Agents cannot review their own listing.',
    ),
  );
  await assertFails(
    saveReview(
      studentDatabase,
      'pending-review-property',
      'pending-student',
      4,
      'Pending properties cannot be reviewed.',
    ),
  );
});

test('administrator removes an inappropriate review and repairs the aggregate', async () => {
  await seedProfile('moderation-agent', 'agent');
  await seedProfile('moderation-student', 'student');
  await seedProfile('moderation-admin', 'admin');
  await seedProperty('moderation-property', 'moderation-agent', {
    approvalStatus: 'approved',
  });
  const studentDatabase = environment.authenticatedContext('moderation-student').firestore();
  await saveReview(
    studentDatabase,
    'moderation-property',
    'moderation-student',
    3,
    'This review will be removed by moderation.',
  );
  const adminDatabase = environment.authenticatedContext('moderation-admin').firestore();
  const propertyReference = propertyDocument(adminDatabase, 'moderation-property');
  const reviewReference = reviewDocument(
    adminDatabase,
    'moderation-property',
    'moderation-student',
  );

  await assertSucceeds(
    runTransaction(adminDatabase, async (transaction) => {
      await transaction.get(reviewReference);
      await transaction.get(propertyReference);
      transaction.delete(reviewReference);
      transaction.update(propertyReference, {
        ratingAverage: 0,
        ratingCount: 0,
        updatedAt: serverTimestamp(),
      });
    }),
  );
  const property = await getDoc(propertyReference);
  assert.equal(property.data().ratingCount, 0);
  assert.equal(property.data().ratingAverage, 0);
  assert.equal((await getDoc(reviewReference)).exists(), false);
});

test('administrator atomically removes a property and its reviews', async () => {
  await seedProfile('cleanup-agent', 'agent');
  await seedProfile('cleanup-student', 'student');
  await seedProfile('cleanup-admin', 'admin');
  await seedProperty('cleanup-property', 'cleanup-agent', {
    approvalStatus: 'approved',
  });
  const studentDatabase = environment.authenticatedContext('cleanup-student').firestore();
  await saveReview(
    studentDatabase,
    'cleanup-property',
    'cleanup-student',
    4,
    'A review removed together with its property.',
  );
  const adminDatabase = environment.authenticatedContext('cleanup-admin').firestore();
  const propertyReference = propertyDocument(adminDatabase, 'cleanup-property');
  const reviewReference = reviewDocument(
    adminDatabase,
    'cleanup-property',
    'cleanup-student',
  );
  const batch = writeBatch(adminDatabase);
  batch.delete(propertyReference);
  batch.delete(reviewReference);

  await assertSucceeds(batch.commit());
  await environment.withSecurityRulesDisabled(async (context) => {
    assert.equal(
      (await getDoc(propertyDocument(context.firestore(), 'cleanup-property'))).exists(),
      false,
    );
    assert.equal(
      (
        await getDoc(
          reviewDocument(
            context.firestore(),
            'cleanup-property',
            'cleanup-student',
          ),
        )
      ).exists(),
      false,
    );
  });
});

test('review ownership prevents another student or agent from changing it', async () => {
  await seedProfile('ownership-agent', 'agent');
  await seedProfile('review-owner', 'student');
  await seedProfile('other-student', 'student');
  await seedProperty('ownership-property', 'ownership-agent', {
    approvalStatus: 'approved',
  });
  const ownerDatabase = environment.authenticatedContext('review-owner').firestore();
  await saveReview(
    ownerDatabase,
    'ownership-property',
    'review-owner',
    5,
    'A review that remains under student ownership.',
  );
  const otherStudentDatabase = environment.authenticatedContext('other-student').firestore();
  const agentDatabase = environment.authenticatedContext('ownership-agent').firestore();
  const otherReference = reviewDocument(
    otherStudentDatabase,
    'ownership-property',
    'review-owner',
  );
  const agentReference = reviewDocument(
    agentDatabase,
    'ownership-property',
    'review-owner',
  );

  await assertFails(
    updateDoc(otherReference, {
      rating: 1,
      comment: 'An unauthorized replacement review.',
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(deleteDoc(agentReference));
  await assertSucceeds(getDoc(agentReference));
});

test('student creates, resumes, updates, and completes an owned inspection', async () => {
  await seedProfile('inspection-agent', 'agent');
  await seedProfile('inspection-student', 'student');
  await seedProfile('inspection-other', 'student');
  await seedProperty('inspection-property', 'inspection-agent', {
    approvalStatus: 'approved',
  });
  const studentDatabase = environment.authenticatedContext('inspection-student').firestore();
  const inspectionReference = inspectionDocument(
    studentDatabase,
    'inspection-property',
    'inspection-student',
  );

  await assertSucceeds(getDoc(inspectionReference));
  await assertSucceeds(
    setDoc(
      inspectionReference,
      inspectionData('inspection-student', 'inspection-property'),
    ),
  );
  await assertFails(
    getDoc(
      inspectionDocument(
        environment.authenticatedContext('inspection-other').firestore(),
        'inspection-property',
        'inspection-student',
      ),
    ),
  );

  const invalidStateResults = inspectionResults();
  invalidStateResults.living_walls_ceiling.state = 'unsafe_custom_state';
  await assertFails(
    updateDoc(inspectionReference, {
      results: invalidStateResults,
      updatedAt: serverTimestamp(),
    }),
  );

  const partialResults = inspectionResults();
  partialResults.living_walls_ceiling = {
    checkId: 'living_walls_ceiling',
    sectionId: 'living_room',
    state: 'concern',
    note: 'Possible damp mark beside the window.',
  };
  await assertSucceeds(
    updateDoc(inspectionReference, {
      results: partialResults,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(inspectionReference, {
      status: 'completed',
      completedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );

  const completedResults = inspectionResults('satisfactory');
  completedResults.living_walls_ceiling = partialResults.living_walls_ceiling;
  await assertSucceeds(
    updateDoc(inspectionReference, {
      results: completedResults,
      status: 'completed',
      completedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(inspectionReference, {
      results: inspectionResults('not_applicable'),
      updatedAt: serverTimestamp(),
    }),
  );
});

test('inspection creation rejects another owner, pending property, and malformed checklist', async () => {
  await seedProfile('invalid-inspection-agent', 'agent');
  await seedProfile('invalid-inspection-student', 'student');
  await seedProperty('pending-inspection-property', 'invalid-inspection-agent', {
    approvalStatus: 'pending',
  });
  const database = environment.authenticatedContext('invalid-inspection-student').firestore();

  await assertFails(
    setDoc(
      inspectionDocument(
        database,
        'pending-inspection-property',
        'invalid-inspection-student',
      ),
      inspectionData(
        'invalid-inspection-student',
        'pending-inspection-property',
      ),
    ),
  );
  await seedProperty('valid-inspection-property', 'invalid-inspection-agent', {
    approvalStatus: 'approved',
  });
  await assertFails(
    setDoc(
      doc(database, 'inspections', 'non-deterministic-inspection'),
      inspectionData(
        'another-student',
        'valid-inspection-property',
      ),
    ),
  );
  const malformed = inspectionResults();
  delete malformed.safety_hazards_exits;
  await assertFails(
    setDoc(
      inspectionDocument(
        database,
        'valid-inspection-property',
        'invalid-inspection-student',
      ),
      inspectionData(
        'invalid-inspection-student',
        'valid-inspection-property',
        malformed,
      ),
    ),
  );
});

test('student creates and queries only owned image-verification reports', async () => {
  await seedProfile('verification-agent', 'agent');
  await seedProfile('verification-student', 'student');
  await seedProperty('verification-property', 'verification-agent', {
    approvalStatus: 'approved',
    imageUrls: [
      'https://example.test/listing-one.jpg',
      'https://example.test/listing-two.jpg',
    ],
  });
  const database = environment
    .authenticatedContext('verification-student')
    .firestore();
  const report = verificationReportDocument(database, 'report-one');

  await assertSucceeds(
    setDoc(
      report,
      verificationReportData('verification-student', 'verification-property'),
    ),
  );
  await assertSucceeds(getDoc(report));
  const ownedQuery = query(
    collection(database, 'verificationReports'),
    where('studentId', '==', 'verification-student'),
  );
  const snapshot = await assertSucceeds(getDocs(ownedQuery));
  assert.equal(snapshot.size, 1);
});

test('verification report is private and immutable', async () => {
  await seedProfile('private-report-agent', 'agent');
  await seedProfile('private-report-owner', 'student');
  await seedProfile('private-report-other', 'student');
  await seedProfile('private-report-admin', 'admin');
  await seedProperty('private-report-property', 'private-report-agent', {
    approvalStatus: 'approved',
    imageUrls: ['https://example.test/listing-one.jpg'],
  });
  const ownerDatabase = environment
    .authenticatedContext('private-report-owner')
    .firestore();
  const ownerReport = verificationReportDocument(ownerDatabase, 'report-one');
  await assertSucceeds(
    setDoc(
      ownerReport,
      verificationReportData('private-report-owner', 'private-report-property'),
    ),
  );

  for (const uid of [
    'private-report-other',
    'private-report-agent',
    'private-report-admin',
  ]) {
    await assertFails(
      getDoc(
        verificationReportDocument(
          environment.authenticatedContext(uid).firestore(),
          'report-one',
        ),
      ),
    );
  }
  await assertFails(
    updateDoc(ownerReport, {
      similarityScore: 100,
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(deleteDoc(ownerReport));
});

test('verification report rejects unsafe claims and invalid references', async () => {
  await seedProfile('invalid-report-agent', 'agent');
  await seedProfile('invalid-report-student', 'student');
  await seedProperty('invalid-report-property', 'invalid-report-agent', {
    approvalStatus: 'approved',
    imageUrls: ['https://example.test/listing-one.jpg'],
  });
  await seedProperty('pending-report-property', 'invalid-report-agent', {
    approvalStatus: 'pending',
    imageUrls: ['https://example.test/listing-one.jpg'],
  });
  const database = environment
    .authenticatedContext('invalid-report-student')
    .firestore();

  await assertFails(
    setDoc(
      verificationReportDocument(database, 'unsafe-report'),
      verificationReportData('invalid-report-student', 'invalid-report-property', {
        visitImagePath:
          'students/invalid-report-student/verifications/unsafe-report/visit.jpg',
        guidance: 'This property is definitely fake.',
      }),
    ),
  );
  await assertFails(
    setDoc(
      verificationReportDocument(database, 'wrong-image-report'),
      verificationReportData('invalid-report-student', 'invalid-report-property', {
        visitImagePath:
          'students/invalid-report-student/verifications/wrong-image-report/visit.jpg',
        bestListingImageUrl: 'https://example.test/not-in-listing.jpg',
      }),
    ),
  );
  await assertFails(
    setDoc(
      verificationReportDocument(database, 'pending-report'),
      verificationReportData('invalid-report-student', 'pending-report-property', {
        visitImagePath:
          'students/invalid-report-student/verifications/pending-report/visit.jpg',
      }),
    ),
  );
  await assertFails(
    setDoc(
      verificationReportDocument(database, 'mismatch-report'),
      verificationReportData('invalid-report-student', 'invalid-report-property', {
        visitImagePath:
          'students/invalid-report-student/verifications/mismatch-report/visit.jpg',
        similarityScore: 35,
        similarityLevel: 'low',
        possibleMismatch: false,
      }),
    ),
  );
});

test('student creates and queries an immutable private uploaded-photo damage report', async () => {
  await seedProfile('damage-agent', 'agent');
  await seedProfile('damage-owner', 'student');
  await seedProfile('damage-other', 'student');
  await seedProperty('damage-property', 'damage-agent', {
    approvalStatus: 'approved',
  });
  const ownerDatabase = environment.authenticatedContext('damage-owner').firestore();
  const report = damageReportDocument(ownerDatabase, 'damage-report-one');

  await assertSucceeds(
    setDoc(report, damageReportData('damage-owner', 'damage-property')),
  );
  await assertSucceeds(getDoc(report));
  const ownedQuery = query(
    collection(ownerDatabase, 'damageReports'),
    where('studentId', '==', 'damage-owner'),
  );
  assert.equal((await assertSucceeds(getDocs(ownedQuery))).size, 1);
  await assertFails(
    getDoc(
      damageReportDocument(
        environment.authenticatedContext('damage-other').firestore(),
        'damage-report-one',
      ),
    ),
  );
  await assertFails(updateDoc(report, { modelScore: 1 }));
  await assertFails(deleteDoc(report));
});

test('damage report accepts only the exact owned inspection concern photo context', async () => {
  await seedProfile('damage-inspection-agent', 'agent');
  await seedProfile('damage-inspection-student', 'student');
  await seedProperty('damage-inspection-property', 'damage-inspection-agent', {
    approvalStatus: 'inactive',
  });
  const inspectionId = 'damage-property_damage-inspection-student';
  const imagePath =
    'students/damage-inspection-student/inspections/damage-property_damage-inspection-student/concern.jpg';
  await seedDamageInspection(
    inspectionId,
    'damage-inspection-student',
    'damage-inspection-property',
    'living_walls_ceiling',
    imagePath,
  );
  const database = environment
    .authenticatedContext('damage-inspection-student')
    .firestore();

  await assertSucceeds(
    setDoc(
      damageReportDocument(database, 'inspection-damage-report'),
      damageReportData(
        'damage-inspection-student',
        'damage-inspection-property',
        {
          imagePath,
          sourceType: 'inspection',
          inspectionId,
          checkId: 'living_walls_ceiling',
        },
      ),
    ),
  );
  await assertFails(
    setDoc(
      damageReportDocument(database, 'wrong-inspection-report'),
      damageReportData(
        'damage-inspection-student',
        'damage-inspection-property',
        {
          imagePath,
          sourceType: 'inspection',
          inspectionId,
          checkId: 'kitchen_appliances',
        },
      ),
    ),
  );
});

test('damage report rejects unsupported labels, unsafe claims, and pending upload property', async () => {
  await seedProfile('invalid-damage-agent', 'agent');
  await seedProfile('invalid-damage-student', 'student');
  await seedProperty('pending-damage-property', 'invalid-damage-agent', {
    approvalStatus: 'pending',
  });
  await seedProperty('valid-damage-property', 'invalid-damage-agent', {
    approvalStatus: 'approved',
  });
  const database = environment
    .authenticatedContext('invalid-damage-student')
    .firestore();

  await assertFails(
    setDoc(
      damageReportDocument(database, 'unsupported-damage-report'),
      damageReportData('invalid-damage-student', 'valid-damage-property', {
        imagePath:
          'students/invalid-damage-student/damage/unsupported-damage-report/damage.jpg',
        damageClass: 'electrical_fault',
      }),
    ),
  );
  await assertFails(
    setDoc(
      damageReportDocument(database, 'unsafe-damage-report'),
      damageReportData('invalid-damage-student', 'valid-damage-property', {
        imagePath:
          'students/invalid-damage-student/damage/unsafe-damage-report/damage.jpg',
        recommendation: 'This is definitely dangerous structural damage.',
      }),
    ),
  );
  await assertFails(
    setDoc(
      damageReportDocument(database, 'pending-damage-report'),
      damageReportData('invalid-damage-student', 'pending-damage-property', {
        imagePath:
          'students/invalid-damage-student/damage/pending-damage-report/damage.jpg',
      }),
    ),
  );
});

test('student creates and queries an immutable owned agreement report', async () => {
  await seedProfile('agreement-owner', 'student');
  const database = environment.authenticatedContext('agreement-owner').firestore();
  const report = agreementDocument(database, 'agreement-one');

  await assertSucceeds(
    setDoc(report, agreementData('agreement-owner', 'agreement-one')),
  );
  await assertSucceeds(getDoc(report));
  const ownedQuery = query(
    collection(database, 'agreements'),
    where('studentId', '==', 'agreement-owner'),
  );
  assert.equal((await assertSucceeds(getDocs(ownedQuery))).size, 1);
  await assertFails(updateDoc(report, { filename: 'changed.pdf' }));
  await assertFails(deleteDoc(report));
});

test('agreement report is private from other students, agents, and admins', async () => {
  await seedProfile('private-agreement-owner', 'student');
  await seedProfile('private-agreement-other', 'student');
  await seedProfile('private-agreement-agent', 'agent');
  await seedProfile('private-agreement-admin', 'admin');
  const ownerDatabase = environment
    .authenticatedContext('private-agreement-owner')
    .firestore();
  await assertSucceeds(
    setDoc(
      agreementDocument(ownerDatabase, 'private-agreement'),
      agreementData('private-agreement-owner', 'private-agreement'),
    ),
  );

  for (const uid of [
    'private-agreement-other',
    'private-agreement-agent',
    'private-agreement-admin',
  ]) {
    await assertFails(
      getDoc(
        agreementDocument(
          environment.authenticatedContext(uid).firestore(),
          'private-agreement',
        ),
      ),
    );
  }
});

test('agreement report rejects unsafe disclaimer, owner, path, and shape', async () => {
  await seedProfile('invalid-agreement-student', 'student');
  const database = environment
    .authenticatedContext('invalid-agreement-student')
    .firestore();

  await assertFails(
    setDoc(
      agreementDocument(database, 'unsafe-agreement'),
      agreementData('invalid-agreement-student', 'unsafe-agreement', {
        disclaimer: 'This is guaranteed legal advice.',
      }),
    ),
  );
  await assertFails(
    setDoc(
      agreementDocument(database, 'wrong-owner-agreement'),
      agreementData('another-student', 'wrong-owner-agreement'),
    ),
  );
  await assertFails(
    setDoc(
      agreementDocument(database, 'wrong-path-agreement'),
      agreementData('invalid-agreement-student', 'wrong-path-agreement', {
        documentPath:
          'students/invalid-agreement-student/agreements/another/document.pdf',
      }),
    ),
  );
  await assertFails(
    setDoc(
      agreementDocument(database, 'malformed-agreement'),
      agreementData('invalid-agreement-student', 'malformed-agreement', {
        clauses: [{ id: 'clause-1', title: 'Incomplete' }],
      }),
    ),
  );
});
