#!/usr/bin/env python3
"""
Convert bge-small-en-v1.5 to a Core ML mlpackage for use in Glimpse.

Usage:
    python3 -m venv ~/ml-venv && source ~/ml-venv/bin/activate
    pip install coremltools==8.0 transformers==4.44 torch==2.4 sentencepiece numpy
    python3 scripts/convert_model.py

Output:
    Glimpse/Resources/bge-small-en-v1.5.mlpackage   ← add to Xcode target
    Glimpse/Resources/vocab.txt                       ← add to Xcode target
"""

import sys
import shutil
import numpy as np
from pathlib import Path

MODEL_ID   = "BAAI/bge-small-en-v1.5"
SEQ_LEN    = 128
OUT_DIR    = Path(__file__).parent.parent / "Glimpse" / "Resources"
MODEL_OUT  = OUT_DIR / "bge-small-en-v1.5.mlpackage"
VOCAB_OUT  = OUT_DIR / "vocab.txt"

def main():
    print(f"Loading {MODEL_ID} …")
    try:
        import torch
        from transformers import AutoTokenizer, AutoModel
        import coremltools as ct
    except ImportError as e:
        sys.exit(f"Missing dependency: {e}\n"
                 f"Run: pip install coremltools==8.0 transformers==4.44 torch==2.4 sentencepiece numpy")

    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    model     = AutoModel.from_pretrained(MODEL_ID)
    model.eval()

    # Save vocab.txt for the Swift tokenizer
    vocab_path = tokenizer.save_vocabulary(str(OUT_DIR))[0]
    if Path(vocab_path).resolve() != VOCAB_OUT.resolve():
        shutil.copy(vocab_path, VOCAB_OUT)
    print(f"vocab.txt → {VOCAB_OUT}")

    # Reference embedding for validation
    sample = "Invoice total amount due pricing"
    enc    = tokenizer(sample, return_tensors="pt", max_length=SEQ_LEN,
                       padding="max_length", truncation=True)
    with torch.no_grad():
        out  = model(**enc)
    mask      = enc["attention_mask"].unsqueeze(-1).float()
    pooled    = (out.last_hidden_state * mask).sum(1) / mask.sum(1).clamp(min=1e-9)
    ref_emb   = torch.nn.functional.normalize(pooled, p=2, dim=1)[0].numpy()
    print(f"Reference embedding: shape={ref_emb.shape}, norm={np.linalg.norm(ref_emb):.4f}")

    # Wrapper: pre-bake position_ids as a buffer to avoid the dynamic int cast
    # that trips up coremltools when tracing vanilla BERT.
    class BGEWrapper(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m
            # Fixed position IDs as a constant buffer — avoids torch.arange inside model
            self.register_buffer("position_ids",
                                 torch.arange(SEQ_LEN, dtype=torch.long).unsqueeze(0))

        def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor):
            out    = self.m(input_ids=input_ids,
                            attention_mask=attention_mask,
                            position_ids=self.position_ids)
            mask   = attention_mask.unsqueeze(-1).float()
            pooled = (out.last_hidden_state * mask).sum(1) / mask.sum(1).clamp(min=1e-9)
            return torch.nn.functional.normalize(pooled, p=2, dim=1)   # (1, 384)

    wrapper = BGEWrapper(model)
    wrapper.eval()

    dummy_ids  = torch.zeros((1, SEQ_LEN), dtype=torch.int32)
    dummy_mask = torch.ones((1, SEQ_LEN), dtype=torch.int32)

    # jit.trace with the position_ids buffer pre-baked — avoids the dynamic int
    # cast inside BERT's embedding layer that trips up the converter.
    print("Tracing model …")
    test_ids  = enc["input_ids"].to(torch.int32)
    test_mask = enc["attention_mask"].to(torch.int32)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, (dummy_ids, dummy_mask))

    # Validate trace output matches original PyTorch model
    with torch.no_grad():
        traced_out = traced(test_ids, test_mask)[0].detach().numpy()
    diff = np.max(np.abs(ref_emb - traced_out))
    print(f"Trace validation — max diff from reference: {diff:.2e}")
    if diff > 1e-4:
        sys.exit(f"ERROR: trace diff {diff:.2e} exceeds threshold. Do not use this model.")

    print("Converting to Core ML …")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids",      shape=(1, SEQ_LEN), dtype=np.int32),
            ct.TensorType(name="attention_mask",  shape=(1, SEQ_LEN), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="embedding")],
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.macOS13,
        convert_to="mlprogram",
    )

    # Float16 quantise: halves file size (~75 MB → ~38 MB), negligible accuracy loss
    print("Quantising weights to Float16 …")
    try:
        from coremltools.optimize.coreml import OpLinearQuantizerConfig, OptimizationConfig, linear_quantize_weights
        config = OptimizationConfig(
            global_config=OpLinearQuantizerConfig(mode="linear_symmetric", dtype="int8")
        )
        mlmodel = linear_quantize_weights(mlmodel, config=config)
        print("Float16 weight quantisation applied.")
    except Exception as e:
        print(f"Float16 quantisation unavailable ({e}) — model saved at full precision.")

    mlmodel.short_description = "bge-small-en-v1.5 sentence embeddings, seq_len=128, mean-pooled, L2-normalised"

    if MODEL_OUT.exists():
        shutil.rmtree(MODEL_OUT)
    mlmodel.save(str(MODEL_OUT))
    print(f"Saved → {MODEL_OUT}")

    # Final Core ML validation
    print("Validating Core ML output …")
    loaded = ct.models.MLModel(str(MODEL_OUT), compute_units=ct.ComputeUnit.CPU_ONLY)
    cml_out = loaded.predict({
        "input_ids":      test_ids.numpy().astype(np.int32),
        "attention_mask": test_mask.numpy().astype(np.int32),
    })["embedding"][0]

    final_diff = np.max(np.abs(ref_emb - cml_out))
    print(f"Core ML validation — max diff from PyTorch: {final_diff:.2e}")
    if final_diff > 1e-3:
        print(f"WARNING: diff {final_diff:.2e} is higher than expected (quantisation). "
              f"Verify search quality before shipping.")
    else:
        print("✓ Validation passed.")

    print("\nNext steps:")
    print("1. In Xcode: Add Glimpse/Resources/bge-small-en-v1.5.mlpackage to the Glimpse target")
    print("2. In Xcode: Add Glimpse/Resources/vocab.txt to the Glimpse target")
    print("3. Build and run — semantic search will activate automatically.")

if __name__ == "__main__":
    main()
