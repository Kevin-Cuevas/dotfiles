// Proyecto: {{PROJECT_NAME}}
const express = require("express");
const app = express();
const port = 3000;

// Middleware para JSON
app.use(express.json());

// Ruta principal
app.get("/", (req, res) => {
  res.send("Hello World desde {{PROJECT_NAME}}!");
});

app.listen(port, () =>
  console.log(`Servidor ejecutándose en http://localhost:${port}`),
);
