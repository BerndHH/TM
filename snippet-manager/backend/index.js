const express = require('express');
const app = express();
const port = 3001;

app.get('/api', (req, res) => {
  res.json({ message: 'Hello from Snippet Manager Backend!' });
});

app.listen(port, () => {
  console.log(`Backend listening at http://localhost:${port}`);
});
