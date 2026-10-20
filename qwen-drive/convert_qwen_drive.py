"""Convert Qwen/Qwen-Drive-1.0-4B (QwenDriveForPlanning) into a plain
Qwen3_5ForConditionalGeneration checkpoint that vLLM can serve.

Only the shared VLM at the repository root is used; the planning expert and
perception head are not loaded. Weight names lose the leading "vlm." prefix;
tensor bytes are copied verbatim by rewriting the safetensors header.
"""
import hashlib
import json
import os
import shutil
import struct
import sys

from huggingface_hub import hf_hub_download

REPO = "Qwen/Qwen-Drive-1.0-4B"
BASE = "Qwen/Qwen3.5-4B"
REVISION = os.environ.get("QWEN_DRIVE_REVISION", "main")
OUT = sys.argv[1]
DONE = os.path.join(OUT, ".converted")

os.makedirs(OUT, exist_ok=True)

def get(name, repo=REPO, rev=REVISION):
    return hf_hub_download(repo, name, revision=rev)

for name in ["tokenizer.json", "tokenizer_config.json", "vocab.json", "merges.txt",
             "chat_template.jinja", "preprocessor_config.json", "generation_config.json"]:
    shutil.copy(get(name), os.path.join(OUT, name))
# Qwen-Drive does not ship a video preprocessor config; its VLM is unchanged
# Qwen3.5, so the base model's video preprocessor applies. vLLM 0.32 resamples
# fully decoded videos to 2 fps regardless of an "fps" entry here or per-request
# mm_processor_kwargs (verified 2026-10-20), so the benchmark encodes its 24
# frames at 2 fps instead.
shutil.copy(get("video_preprocessor_config.json", BASE, "main"),
            os.path.join(OUT, "video_preprocessor_config.json"))

drive_config = json.load(open(get("config.json")))
config = drive_config["vlm_config"]
config["architectures"] = ["Qwen3_5ForConditionalGeneration"]
config["torch_dtype"] = "bfloat16"
json.dump(config, open(os.path.join(OUT, "config.json"), "w"), indent=2)

if os.path.exists(DONE):
    print("weights already converted:", open(DONE).read().strip())
    sys.exit(0)

src = get("model.safetensors")
dst = os.path.join(OUT, "model.safetensors")
with open(src, "rb") as f:
    n = struct.unpack("<Q", f.read(8))[0]
    header = json.loads(f.read(n))
    renamed = {}
    for key, value in header.items():
        if key == "__metadata__":
            renamed[key] = value
            continue
        if not key.startswith("vlm."):
            raise SystemExit(f"unexpected tensor outside VLM: {key}")
        renamed[key[len("vlm."):]] = value
    blob = json.dumps(renamed, separators=(",", ":")).encode()
    blob += b" " * ((8 - len(blob) % 8) % 8)
    with open(dst + ".tmp", "wb") as g:
        g.write(struct.pack("<Q", len(blob)))
        g.write(blob)
        shutil.copyfileobj(f, g, 64 << 20)
os.replace(dst + ".tmp", dst)

sha = hashlib.sha256(open(src, "rb").read(1 << 20)).hexdigest()
with open(DONE, "w") as f:
    f.write(f"{REPO}@{REVISION} tensors={len(renamed) - 1} src_head_sha256={sha}\n")
print(open(DONE).read().strip())
