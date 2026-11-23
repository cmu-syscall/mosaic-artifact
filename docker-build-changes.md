# Docker build change log

## Ubuntu 26.04 image

- Restored Ubuntu 26.04 as the final Docker image base. The Dockerfile copies
  CUDA 12.6.3 from the NVIDIA image to preserve the existing cuBLAS version
  and host driver requirements.
- Registered the CUDA library path, set NVIDIA Container Toolkit environment
  defaults, and added a build-time cuBLAS header and linker check.
- Updated `docker.md` to identify the Ubuntu 26.04 base. Build output is in
  `/tmp/mosaic-docker-ubuntu2604.log`.
- `docker build -t mosaic-artifact .` passed, including the cuBLAS link check
  and both Mosaic targets. Docker tagged image `908c3f6e8e6c` as
  `mosaic-artifact:latest`. GPU runtime testing was unavailable because
  `nvidia-smi` could not communicate with the host driver.

## 2026-11-18

- Added this file at the user's request to record all changes and validation.
- Started `docker build -t mosaic-artifact .` to reproduce the failure with the
  current CUDA base image. Build output is in `/tmp/mosaic-docker-build.log`.
- The existing `build.log` records a successful build using the previous
  `ubuntu:26.04` base; it does not validate the current CUDA Dockerfile.
- Existing source and benchmark modifications have been left intact.
- The server restart interrupted the first build. Resumed using cached layers;
  output is in `/tmp/mosaic-docker-build-resumed.log`.
- Reproduced failure in TBLIS `make install`: its pinned revision lists
  `src/external/marray/marray/expression.hpp` twice, and Ubuntu 24.04's
  `/usr/bin/install` rejects overwriting a just-created file.
- Changed `scripts/tblis_download.sh` to remove the duplicate header entry from
  downloaded `Makefile.am` and `Makefile.in` before configuring TBLIS. The pinned
  version and Docker base image are unchanged.
- Validation: `bash -n scripts/tblis_download.sh` and `git diff --check` passed.
- Full validation: `docker build -t mosaic-artifact .` exited successfully and
  produced image `34fd97e2d4d1`, tagged `mosaic-artifact:latest`. TBLIS and the
  tensor extension installed, Python imports passed, and both `taco-bench` and
  `taco-test` compiled and linked. Full output:
  `/tmp/mosaic-docker-build-fixed.log`.
- Runtime tests and GPU benchmarks were not run; this validation covers the
  requested image build.
