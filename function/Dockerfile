# syntax=docker/dockerfile:1
# Base pinned by multi-arch index digest (linux/amd64 + linux/arm64).
ARG PYTHON_IMAGE=python:3.12.15-slim-trixie@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1

FROM ${PYTHON_IMAGE} AS builder
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_NO_CACHE_DIR=1
COPY requirements.txt /tmp/requirements.txt
# --no-deps: exactly the lock file; an incomplete lock fails the build here.
RUN pip install --no-deps --target /python -r /tmp/requirements.txt \
 && PYTHONPATH=/python python -m pip check

FROM ${PYTHON_IMAGE}
ARG GIT_SHA=unknown
LABEL org.opencontainers.image.title="antonime-function" \
      org.opencontainers.image.revision="${GIT_SHA}"
COPY --from=builder /python /python
COPY func.py /function/
# The function filesystem is read-only at runtime: compile .pyc now.
RUN python -m compileall -q /python /function \
 && groupadd --system --gid 1000 fn \
 && useradd --system --uid 1000 --gid fn --no-create-home --shell /usr/sbin/nologin fn
ENV PYTHONPATH=/function:/python \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    GIT_SHA=${GIT_SHA}
WORKDIR /function
USER 1000:1000
# fdk listens on the socket in $FN_LISTENER and calls func.handler per request.
ENTRYPOINT ["/python/bin/fdk", "/function/func.py", "handler"]
