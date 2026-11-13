const path = require('path');
const fs = require('fs');
const bundledExpress = path.resolve(__dirname, '../heavenlink-backend/node_modules/express');
const express = require(fs.existsSync(bundledExpress) ? bundledExpress
  : path.resolve(__dirname, '../../heavenlink-backend/node_modules/express'));

const buildRoot = path.resolve(__dirname, '../build/web');
const app = express();
const port = Number(process.env.PORT) || 8080;

app.use(express.static(buildRoot));
app.get('*', (_req, res) => {
  res.sendFile(path.join(buildRoot, 'index.html'));
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Haven Link web build is available on port ${port}`);
});