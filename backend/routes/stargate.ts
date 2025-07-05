import { Router } from "express";
import generateCallData from "../funcs/buildSwapData";

const router = Router();

router.post("/", (req, res) => {
    const { srcChain, dstChain, amount, amountOutMin } = req.body;
    const callData = generateCallData(srcChain, dstChain, amount, amountOutMin);
    res.send(callData);
});

export default router;