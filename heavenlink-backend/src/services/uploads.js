const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const multer = require('multer');

const MAX_FILE_BYTES = 5 * 1024 * 1024;
const MAX_FILES = 5;

const uploadRoot = process.env.UPLOAD_DIR
  ? path.resolve(process.env.UPLOAD_DIR)
  : process.env.NODE_ENV === 'test'
    ? path.join(require('os').tmpdir(), `haven-link-uploads-${process.pid}`)
    : path.resolve(__dirname, '../../data/uploads');

const signatures = [
  { ext: 'jpg', mime: 'image/jpeg', match: (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff },
  { ext: 'png', mime: 'image/png', match: (b) => b.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) },
  { ext: 'webp', mime: 'image/webp', match: (b) => b.slice(0, 4).toString('latin1') === 'RIFF' && b.slice(8, 12).toString('latin1') === 'WEBP' },
  { ext: 'pdf', mime: 'application/pdf', match: (b) => b.slice(0, 5).toString('latin1') === '%PDF-' }
];

const detectType = (buffer) => signatures.find((type) => buffer.length > 12 && type.match(buffer));

const parser = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_BYTES, files: MAX_FILES, fields: 30 }
});

// Parses optional multipart files; JSON requests pass through untouched.
const acceptFiles = (fieldName) => (req, res, next) => {
  if (!req.is('multipart/form-data')) return next();
  parser.array(fieldName, MAX_FILES)(req, res, (error) => {
    if (!error) return next();
    const message = error.code === 'LIMIT_FILE_SIZE'
      ? 'Each file must be 5 MB or smaller'
      : error.code === 'LIMIT_UNEXPECTED_FILE' || error.code === 'LIMIT_FILE_COUNT'
        ? `At most ${MAX_FILES} files are allowed`
        : 'Upload failed';
    res.status(400).json({ error: message });
  });
};

// Validates content by signature (not client-declared MIME) and stores with random names.
const storeFiles = async (files, folder, { allowPdf }) => {
  const stored = [];
  for (const file of files || []) {
    const type = detectType(file.buffer);
    if (!type || (type.ext === 'pdf' && !allowPdf)) {
      const error = new Error('Only JPG, PNG or WebP images' + (allowPdf ? ' and PDF documents' : '') + ' are allowed');
      error.status = 400;
      throw error;
    }
    stored.push({ type, buffer: file.buffer });
  }
  const dir = path.join(uploadRoot, folder);
  await fs.promises.mkdir(dir, { recursive: true });
  const names = [];
  for (const item of stored) {
    const name = `${crypto.randomUUID()}.${item.type.ext}`;
    await fs.promises.writeFile(path.join(dir, name), item.buffer, { flag: 'wx' });
    names.push(name);
  }
  return names;
};

const removeFiles = (folder, names) => Promise.all(
  (names || []).map((name) => fs.promises.unlink(path.join(uploadRoot, folder, path.basename(name))).catch(() => {}))
);

const filePath = (folder, name) => {
  const safe = path.basename(String(name));
  if (!/^[0-9a-f-]{36}\.(jpg|png|webp|pdf)$/.test(safe)) return null;
  return path.join(uploadRoot, folder, safe);
};

module.exports = { acceptFiles, storeFiles, removeFiles, filePath, uploadRoot };
