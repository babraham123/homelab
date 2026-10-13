# Builds localhost/bookmark_handoff: bookmark_handoff.py and its pinned libraries.
# Built by build.sh, which pins the base image by digest; requirements.txt pins the
# libraries by hash:
#   uv pip compile --generate-hashes --universal requirements.in -o requirements.txt

ARG PY_IMAGE=docker.io/library/python:3-alpine

FROM ${PY_IMAGE}
ENV PYTHONDONTWRITEBYTECODE=1
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --require-hashes -r /tmp/requirements.txt && rm /tmp/requirements.txt
COPY bookmark_handoff.py /usr/local/bin/bookmark_handoff.py
ENTRYPOINT ["python3", "/usr/local/bin/bookmark_handoff.py"]
