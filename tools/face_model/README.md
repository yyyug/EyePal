# Face Model Prep

This folder prepares the face embedding model for EyePal.

## Tooling split

This repo now uses one shipping model path and two environments:

- Windows path: download and validate `w600k_mbf.onnx`
- Ubuntu path: validate and package `w600k_mbf.onnx` for app handoff

The shipping iOS path is ONNX Runtime with `w600k_mbf.onnx` (InsightFace buffalo_sc MobileFaceNet, same weights as Android).

## Verified model contract

The Swift app expects the final ONNX model to match this contract:

- input name: `input_1`
- input shape: `N x 112 x 112 x 3`
- input type: `float32`
- output name: `embedding`
- output shape: `N x 512`
- output type: `float32`

## Important platform note

The repo does not depend on Core ML conversion for the face model. The app uses ONNX Runtime directly and bundles the verified ONNX model.

## Windows setup

1. Install Python 3.12 or newer.
2. Run the downloader (pulls InsightFace buffalo_sc, copies `w600k_mbf.onnx`):
   `powershell -ExecutionPolicy Bypass -File tools\face_model\download_arcface_onnx.ps1`
3. Create a virtual environment and install requirements:
   `py -3.12 -m venv .venv`
   `.\.venv\Scripts\Activate.ps1`
   `pip install -r tools\face_model\requirements.txt`
4. Validate the model with two cropped face photos:
   `python tools\face_model\validate_arcface_onnx.py --model tools\face_model\models\w600k_mbf.onnx --image-a path\to\face1.jpg --image-b path\to\face2.jpg`

## Expected preprocessing

The selected model (w600k_mbf) expects:
- RGB
- resized to `112x112`
- normalized as `(pixel - 127.5) / 128.0`
- NCHW tensor shape `1 x 3 x 112 x 112`

## Ubuntu packaging setup

On Ubuntu, run:

```bash
bash tools/face_model/run_ubuntu_onnx_pipeline.sh
```

This will:

1. create `.venv-ubuntu`
2. install the ONNX validation requirements
3. verify `tools/face_model/models/w600k_mbf.onnx`
4. copy the validated model into `tools/face_model/dist`
5. write `tools/face_model/dist/arcface_contract.json`

The packager can also be run directly:

```bash
python tools/face_model/package_onnx_model.py \
  --model tools/face_model/models/w600k_mbf.onnx \
  --output-dir tools/face_model/dist
```

## Final app bundling step

The current app loads `w600k_mbf.onnx` at runtime (iOS and Android share the same weights). The Ubuntu toolchain therefore hands off:

- `w600k_mbf.onnx`
- `arcface_contract.json` (updated for the w600k_mbf input/output contract)

The verified w600k_mbf contract is: input `input.1`, shape `1 x 3 x 112 x 112` (NCHW), RGB, output `516` with shape `1 x 512`.

## Experimental Non-Shipping Files

These files may exist locally from earlier experiments, but they are not used by the shipping build or packaging flow:

- `tools/face_model/models/mobilefacenet_scripted.pt`
- `tools/face_model/models/model_mobilefacenet.pth`

## Sources used for this setup

- Hugging Face ArcFace ONNX model card: https://huggingface.co/onnx-community/arcface-onnx
