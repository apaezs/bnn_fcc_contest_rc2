# Python Artifacts

This folder now carries two explicit dataset roots:

- `mnist/`: original trained MNIST model files and test vectors
- `fashion_mnist/`: Fashion-MNIST model files, test vectors, metadata, and generator outputs

Compatibility notes:

- `model_data/` and `test_vectors/` are preserved as top-level mirrors of the MNIST assets so the original contest flows still work.
- The SystemVerilog testbenches now auto-resolve both the legacy top-level MNIST layout and the explicit `mnist/` / `fashion_mnist/` subdirectories.

Fashion-MNIST generation:

```powershell
python python/generate_fashion_mnist_assets.py
```

By default, that script writes into:

- `python/fashion_mnist/model_data/`
- `python/fashion_mnist/test_vectors/`
- `python/fashion_mnist/fashion_mnist_metadata.json`
