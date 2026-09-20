# Third-party components

LiveCaption's own code is MIT licensed. Third-party code keeps its original license.

| Component | Source / revision | License |
| --- | --- | --- |
| whisper.cpp | https://github.com/ggml-org/whisper.cpp, 9386f239401074690479731c1e41683fbbeac557 | Vendor/whisper.cpp/LICENSE (MIT) |
| FluidAudio | https://github.com/FluidInference/FluidAudio, vendored snapshot; README identifies 0.12.4, original commit unavailable | Vendor/FluidAudio/LICENSE (Apache-2.0) |

FluidAudio includes additional notices in `Vendor/FluidAudio/ThirdPartyLicenses/`
for fastcluster, VBx, and NeMo text processing. Keep these files with redistributed
sources and binaries. Vendor source is included directly, not as Git submodules.
The repository snapshot defines the exact FluidAudio source; do not assume it is
identical to an upstream release solely from the README version.

Whisper model binaries are downloaded separately from ggerganov/whisper.cpp on
Hugging Face, with optional mirrors. Expected SHA-256 values are pinned in
Sources/Models.swift. Speaker models are downloaded by FluidAudio. Model weights
are not covered by LiveCaption's MIT license; review each upstream model card and
terms before redistributing weights. Apple frameworks and language packs are
provided by macOS and are not redistributed by this project.
