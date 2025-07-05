import express from "express";
import unicorn from "./routes/unicorn.ts";
import stargate from "./routes/stargate.ts";
const app = express();

const port = 3000

app.get("/", (req, res) => {
    res.send("Neigh");
});

app.use("/unicorn", unicorn);

app.use("/stargate", stargate);



app.listen(port, () => {
    console.log(`Server is running on port ${port}`);
});