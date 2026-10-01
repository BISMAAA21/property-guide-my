import { readFile } from 'node:fs/promises';
import { after, afterEach, before, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, setDoc } from 'firebase/firestore';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';

let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-property-guidance',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
    storage: {
      host: '127.0.0.1',
      port: 9199,
      rules: await readFile(new URL('../storage.rules', import.meta.url), 'utf8'),
    },
  });
});

afterEach(async () => {
  await environment.clearStorage();
  await environment.clearFirestore();
});
after(async () => environment.cleanup());

async function seedProfile(uid, role, status = 'active') {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', uid), {
      name: uid,
      email: `${uid}@example.test`,
      role,
      status,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
}

async function seedProperty(propertyId, agentId, approvalStatus = 'draft') {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'properties', propertyId), {
      agentId,
      propertyName: 'Storage Rules Residence',
      location: 'Subang Jaya, Selangor',
      normalizedLocation: 'subang jaya, selangor',
      monthlyRent: 1300,
      bedrooms: 1,
      bathrooms: 1,
      propertyType: 'studio',
      description: 'A controlled listing used only to test storage authorization.',
      facilities: ['Wi-Fi'],
      imageUrls: [],
      approvalStatus,
      ratingAverage: 0,
      ratingCount: 0,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
}

async function seedInspection(inspectionId, studentId, status = 'in_progress') {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'inspections', inspectionId), {
      studentId,
      propertyId: 'inspection-property',
      propertyName: 'Storage Inspection Residence',
      checklistVersion: '1.0.0',
      status,
      results: {},
      startedAt: new Date(),
      updatedAt: new Date(),
      ...(status === 'completed' ? { completedAt: new Date() } : {}),
    });
  });
}

function listingImage(context, agentId, propertyId, filename = 'room.jpg') {
  return ref(
    context.storage(),
    `properties/${agentId}/${propertyId}/listing/${filename}`,
  );
}

function inspectionImage(
  context,
  studentId,
  inspectionId,
  filename = 'concern.jpg',
) {
  return ref(
    context.storage(),
    `students/${studentId}/inspections/${inspectionId}/${filename}`,
  );
}

function verificationImage(
  context,
  studentId,
  reportId,
  filename = 'visit.jpg',
) {
  return ref(
    context.storage(),
    `students/${studentId}/verifications/${reportId}/${filename}`,
  );
}

function damageImage(context, studentId, reportId, filename = 'damage.jpg') {
  return ref(
    context.storage(),
    `students/${studentId}/damage/${reportId}/${filename}`,
  );
}

function agreementPdf(
  context,
  studentId,
  agreementId,
  filename = 'document.pdf',
) {
  return ref(
    context.storage(),
    `students/${studentId}/agreements/${agreementId}/${filename}`,
  );
}

const imageBytes = new Uint8Array([255, 216, 255, 217]);
const imageMetadata = { contentType: 'image/jpeg' };

test('agent can upload to an owned draft but other roles and agents cannot', async () => {
  await seedProfile('storage-owner', 'agent');
  await seedProfile('storage-other-agent', 'agent');
  await seedProfile('storage-student', 'student');
  await seedProperty('storage-draft', 'storage-owner');
  const owner = environment.authenticatedContext('storage-owner');
  const otherAgent = environment.authenticatedContext('storage-other-agent');
  const student = environment.authenticatedContext('storage-student');

  await assertSucceeds(
    uploadBytes(
      listingImage(owner, 'storage-owner', 'storage-draft'),
      imageBytes,
      imageMetadata,
    ),
  );
  await assertFails(
    uploadBytes(
      listingImage(otherAgent, 'storage-owner', 'storage-draft', 'other.jpg'),
      imageBytes,
      imageMetadata,
    ),
  );
  await assertFails(
    uploadBytes(
      listingImage(student, 'storage-student', 'storage-draft', 'student.jpg'),
      imageBytes,
      imageMetadata,
    ),
  );
  await assertSucceeds(
    deleteObject(listingImage(owner, 'storage-owner', 'storage-draft')),
  );
});

test('private draft image is readable by owner and admin but not student or other agent', async () => {
  await seedProfile('read-owner', 'agent');
  await seedProfile('read-other', 'agent');
  await seedProfile('read-student', 'student');
  await seedProfile('read-admin', 'admin');
  await seedProperty('read-draft', 'read-owner');
  const owner = environment.authenticatedContext('read-owner');
  const ownerImage = listingImage(owner, 'read-owner', 'read-draft');
  await assertSucceeds(uploadBytes(ownerImage, imageBytes, imageMetadata));

  await assertSucceeds(getBytes(ownerImage));
  await assertSucceeds(
    getBytes(
      listingImage(
        environment.authenticatedContext('read-admin'),
        'read-owner',
        'read-draft',
      ),
    ),
  );
  await assertFails(
    getBytes(
      listingImage(
        environment.authenticatedContext('read-other'),
        'read-owner',
        'read-draft',
      ),
    ),
  );
  await assertFails(
    getBytes(
      listingImage(
        environment.authenticatedContext('read-student'),
        'read-owner',
        'read-draft',
      ),
    ),
  );
});

test('approved image is readable by an active student and no longer editable by agent', async () => {
  await seedProfile('approved-owner', 'agent');
  await seedProfile('approved-student', 'student');
  await seedProfile('approved-admin', 'admin');
  await seedProperty('approved-property', 'approved-owner', 'draft');
  const owner = environment.authenticatedContext('approved-owner');
  const ownerImage = listingImage(owner, 'approved-owner', 'approved-property');
  await assertSucceeds(uploadBytes(ownerImage, imageBytes, imageMetadata));
  await seedProperty('approved-property', 'approved-owner', 'approved');

  await assertSucceeds(
    getBytes(
      listingImage(
        environment.authenticatedContext('approved-student'),
        'approved-owner',
        'approved-property',
      ),
    ),
  );
  await assertFails(deleteObject(ownerImage));
  await assertSucceeds(
    deleteObject(
      listingImage(
        environment.authenticatedContext('approved-admin'),
        'approved-owner',
        'approved-property',
      ),
    ),
  );
});

test('administrator can clean up an orphaned listing image', async () => {
  await seedProfile('orphan-owner', 'agent');
  await seedProfile('orphan-admin', 'admin');
  await seedProperty('orphan-property', 'orphan-owner');
  const owner = environment.authenticatedContext('orphan-owner');
  const image = listingImage(owner, 'orphan-owner', 'orphan-property');
  await assertSucceeds(uploadBytes(image, imageBytes, imageMetadata));
  await environment.withSecurityRulesDisabled(async (context) => {
    await deleteDoc(doc(context.firestore(), 'properties', 'orphan-property'));
  });

  await assertSucceeds(
    deleteObject(
      listingImage(
        environment.authenticatedContext('orphan-admin'),
        'orphan-owner',
        'orphan-property',
      ),
    ),
  );
});

test('invalid content type is rejected', async () => {
  await seedProfile('type-owner', 'agent');
  await seedProperty('type-property', 'type-owner');
  const owner = environment.authenticatedContext('type-owner');

  await assertFails(
    uploadBytes(
      listingImage(owner, 'type-owner', 'type-property', 'payload.txt'),
      new Uint8Array([1, 2, 3]),
      { contentType: 'text/plain' },
    ),
  );
});

test('cross-service uploads fail closed when referenced documents are missing', async () => {
  await seedProfile('missing-property-agent', 'agent');
  await seedProfile('missing-resource-student', 'student');
  const agent = environment.authenticatedContext('missing-property-agent');
  const student = environment.authenticatedContext('missing-resource-student');

  await assertFails(
    uploadBytes(
      listingImage(agent, 'missing-property-agent', 'missing-property'),
      imageBytes,
      imageMetadata,
    ),
  );
  await assertFails(
    uploadBytes(
      inspectionImage(
        student,
        'missing-resource-student',
        'missing-inspection',
      ),
      imageBytes,
      imageMetadata,
    ),
  );

  const reportMetadata = {
    contentType: 'image/jpeg',
    customMetadata: {
      ownerId: 'missing-resource-student',
      propertyId: 'missing-property',
      reportId: 'missing-report',
    },
  };
  await assertFails(
    uploadBytes(
      verificationImage(
        student,
        'missing-resource-student',
        'missing-report',
      ),
      imageBytes,
      reportMetadata,
    ),
  );
  await assertFails(
    uploadBytes(
      damageImage(
        student,
        'missing-resource-student',
        'missing-report',
      ),
      imageBytes,
      reportMetadata,
    ),
  );
});

test('inspection concern photo is private to its active student owner', async () => {
  await seedProfile('photo-student', 'student');
  await seedProfile('photo-other', 'student');
  await seedInspection('inspection-property_photo-student', 'photo-student');
  const owner = environment.authenticatedContext('photo-student');
  const other = environment.authenticatedContext('photo-other');
  const ownerImage = inspectionImage(
    owner,
    'photo-student',
    'inspection-property_photo-student',
  );

  await assertSucceeds(uploadBytes(ownerImage, imageBytes, imageMetadata));
  await assertSucceeds(getBytes(ownerImage));
  await assertFails(
    getBytes(
      inspectionImage(
        other,
        'photo-student',
        'inspection-property_photo-student',
      ),
    ),
  );
  await assertFails(
    uploadBytes(
      inspectionImage(
        other,
        'photo-other',
        'inspection-property_photo-student',
      ),
      imageBytes,
      imageMetadata,
    ),
  );
  await assertSucceeds(deleteObject(ownerImage));
});

test('inspection photo rejects invalid type and completed-inspection writes', async () => {
  await seedProfile('photo-validation-student', 'student');
  await seedInspection(
    'inspection-property_photo-validation-student',
    'photo-validation-student',
  );
  const owner = environment.authenticatedContext('photo-validation-student');
  const image = inspectionImage(
    owner,
    'photo-validation-student',
    'inspection-property_photo-validation-student',
  );

  await assertFails(
    uploadBytes(image, new Uint8Array([1, 2, 3]), {
      contentType: 'application/pdf',
    }),
  );
  await seedInspection(
    'completed-property_photo-validation-student',
    'photo-validation-student',
    'completed',
  );
  await assertFails(
    uploadBytes(
      inspectionImage(
        owner,
        'photo-validation-student',
        'completed-property_photo-validation-student',
      ),
      imageBytes,
      imageMetadata,
    ),
  );
});

test('verification visit photo is private to its active student owner', async () => {
  await seedProfile('verification-photo-agent', 'agent');
  await seedProfile('verification-photo-owner', 'student');
  await seedProfile('verification-photo-other', 'student');
  await seedProperty(
    'verification-photo-property',
    'verification-photo-agent',
    'approved',
  );
  const owner = environment.authenticatedContext('verification-photo-owner');
  const other = environment.authenticatedContext('verification-photo-other');
  const image = verificationImage(
    owner,
    'verification-photo-owner',
    'verification-report',
  );
  const metadata = {
    contentType: 'image/jpeg',
    customMetadata: {
      ownerId: 'verification-photo-owner',
      propertyId: 'verification-photo-property',
      reportId: 'verification-report',
    },
  };

  await assertSucceeds(uploadBytes(image, imageBytes, metadata));
  await assertSucceeds(getBytes(image));
  await assertFails(
    getBytes(
      verificationImage(
        other,
        'verification-photo-owner',
        'verification-report',
      ),
    ),
  );
  await assertFails(
    uploadBytes(
      verificationImage(
        other,
        'verification-photo-other',
        'verification-report',
      ),
      imageBytes,
      metadata,
    ),
  );
  await assertSucceeds(deleteObject(image));
});

test('verification upload rejects invalid metadata, property, and type', async () => {
  await seedProfile('verification-validation-agent', 'agent');
  await seedProfile('verification-validation-student', 'student');
  await seedProperty(
    'verification-pending-property',
    'verification-validation-agent',
    'pending',
  );
  await seedProperty(
    'verification-approved-property',
    'verification-validation-agent',
    'approved',
  );
  const owner = environment.authenticatedContext(
    'verification-validation-student',
  );
  const image = verificationImage(
    owner,
    'verification-validation-student',
    'validation-report',
  );

  await assertFails(
    uploadBytes(image, imageBytes, {
      contentType: 'image/jpeg',
      customMetadata: {
        ownerId: 'another-student',
        propertyId: 'verification-approved-property',
        reportId: 'validation-report',
      },
    }),
  );
  await assertFails(
    uploadBytes(image, imageBytes, {
      contentType: 'image/jpeg',
      customMetadata: {
        ownerId: 'verification-validation-student',
        propertyId: 'verification-pending-property',
        reportId: 'validation-report',
      },
    }),
  );
  await assertFails(
    uploadBytes(image, new Uint8Array([1, 2, 3]), {
      contentType: 'application/pdf',
      customMetadata: {
        ownerId: 'verification-validation-student',
        propertyId: 'verification-approved-property',
        reportId: 'validation-report',
      },
    }),
  );
});

test('uploaded damage photo is private to its active student owner', async () => {
  await seedProfile('damage-photo-agent', 'agent');
  await seedProfile('damage-photo-owner', 'student');
  await seedProfile('damage-photo-other', 'student');
  await seedProperty('damage-photo-property', 'damage-photo-agent', 'approved');
  const owner = environment.authenticatedContext('damage-photo-owner');
  const other = environment.authenticatedContext('damage-photo-other');
  const image = damageImage(owner, 'damage-photo-owner', 'damage-photo-report');
  const metadata = {
    contentType: 'image/jpeg',
    customMetadata: {
      ownerId: 'damage-photo-owner',
      propertyId: 'damage-photo-property',
      reportId: 'damage-photo-report',
    },
  };

  await assertSucceeds(uploadBytes(image, imageBytes, metadata));
  await assertSucceeds(getBytes(image));
  await assertFails(
    getBytes(
      damageImage(other, 'damage-photo-owner', 'damage-photo-report'),
    ),
  );
  await assertFails(
    uploadBytes(
      damageImage(other, 'damage-photo-other', 'damage-photo-report'),
      imageBytes,
      metadata,
    ),
  );
  await assertSucceeds(deleteObject(image));
});

test('damage upload rejects mismatched metadata, pending property, and invalid type', async () => {
  await seedProfile('damage-validation-agent', 'agent');
  await seedProfile('damage-validation-student', 'student');
  await seedProperty(
    'damage-validation-pending',
    'damage-validation-agent',
    'pending',
  );
  await seedProperty(
    'damage-validation-approved',
    'damage-validation-agent',
    'approved',
  );
  const owner = environment.authenticatedContext('damage-validation-student');
  const image = damageImage(
    owner,
    'damage-validation-student',
    'damage-validation-report',
  );
  const baseMetadata = {
    ownerId: 'damage-validation-student',
    propertyId: 'damage-validation-approved',
    reportId: 'damage-validation-report',
  };

  await assertFails(
    uploadBytes(image, imageBytes, {
      contentType: 'image/jpeg',
      customMetadata: { ...baseMetadata, ownerId: 'another-student' },
    }),
  );
  await assertFails(
    uploadBytes(image, imageBytes, {
      contentType: 'image/jpeg',
      customMetadata: {
        ...baseMetadata,
        propertyId: 'damage-validation-pending',
      },
    }),
  );
  await assertFails(
    uploadBytes(image, new Uint8Array([1, 2, 3]), {
      contentType: 'application/pdf',
      customMetadata: baseMetadata,
    }),
  );
});

test('agreement PDF is private to its active student owner', async () => {
  await seedProfile('agreement-pdf-owner', 'student');
  await seedProfile('agreement-pdf-other', 'student');
  await seedProfile('agreement-pdf-admin', 'admin');
  const owner = environment.authenticatedContext('agreement-pdf-owner');
  const pdf = agreementPdf(owner, 'agreement-pdf-owner', 'agreement-pdf-one');
  const metadata = {
    contentType: 'application/pdf',
    customMetadata: {
      ownerId: 'agreement-pdf-owner',
      agreementId: 'agreement-pdf-one',
    },
  };

  await assertSucceeds(
    uploadBytes(pdf, new Uint8Array([37, 80, 68, 70, 45]), metadata),
  );
  await assertSucceeds(getBytes(pdf));
  await assertFails(
    getBytes(
      agreementPdf(
        environment.authenticatedContext('agreement-pdf-other'),
        'agreement-pdf-owner',
        'agreement-pdf-one',
      ),
    ),
  );
  await assertFails(
    getBytes(
      agreementPdf(
        environment.authenticatedContext('agreement-pdf-admin'),
        'agreement-pdf-owner',
        'agreement-pdf-one',
      ),
    ),
  );
  await assertSucceeds(deleteObject(pdf));
});

test('agreement upload rejects wrong path, metadata, role, and content type', async () => {
  await seedProfile('agreement-validation-student', 'student');
  await seedProfile('agreement-validation-agent', 'agent');
  const student = environment.authenticatedContext('agreement-validation-student');
  const agent = environment.authenticatedContext('agreement-validation-agent');
  const pdfBytes = new Uint8Array([37, 80, 68, 70, 45]);
  const metadata = {
    contentType: 'application/pdf',
    customMetadata: {
      ownerId: 'agreement-validation-student',
      agreementId: 'agreement-validation-one',
    },
  };

  await assertFails(
    uploadBytes(
      agreementPdf(
        student,
        'agreement-validation-student',
        'agreement-validation-one',
        'renamed.pdf',
      ),
      pdfBytes,
      metadata,
    ),
  );
  await assertFails(
    uploadBytes(
      agreementPdf(
        student,
        'agreement-validation-student',
        'agreement-validation-one',
      ),
      pdfBytes,
      {
        ...metadata,
        customMetadata: { ...metadata.customMetadata, ownerId: 'other' },
      },
    ),
  );
  await assertFails(
    uploadBytes(
      agreementPdf(
        agent,
        'agreement-validation-agent',
        'agreement-validation-one',
      ),
      pdfBytes,
      metadata,
    ),
  );
  await assertFails(
    uploadBytes(
      agreementPdf(
        student,
        'agreement-validation-student',
        'agreement-validation-one',
      ),
      new Uint8Array([1, 2, 3]),
      { ...metadata, contentType: 'text/plain' },
    ),
  );
});
