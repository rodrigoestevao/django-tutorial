FROM python:3.12-slim AS python-base

# envs
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1 \
    PIP_NO_CACHE_DIR=on \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    POETRY_HOME="/opt/poetry" \
    POETRY_VIRTUALENVS_IN_PROJECT=true \
    POETRY_NO_INTERACTION=1 \
    POETRY_VERSION=1.8.3 \
    APP_PATH="/opt/mysite" \
    PYSETUP_PATH="/opt/pysetup" \
    VENV_PATH="/opt/pysetup/.venv"

ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# prepend poetry and venv to path
ENV PATH="$POETRY_HOME/bin:$VENV_PATH/bin:$PATH"

# `builder-base` stage is used to build deps + create our virtual environment
FROM python-base as builder-base

RUN apt update \
    && apt full-upgrade -y \
    && apt install --no-install-recommends -y \
        build-essential \
        postgresql-client \
        curl \
    && apt autoremove -y \
    && apt clean


# Install Poetry - respects $POETRY_VERSION & $POETRY_HOME
RUN curl -sSL https://install.python-poetry.org | python3 -

# We copy our Python requirements here to cache them
# and install only runtime deps using poetry
WORKDIR $PYSETUP_PATH
COPY ./poetry.lock ./pyproject.toml ./
# RUN poetry install --only=main,test,dev --sync
RUN poetry install --sync


# 'development' stage installs all dev deps and can be used to develop code.
# For example using docker-compose to mount local volume under /app
FROM python-base as development

ARG USER=docker
ARG UID=1000
ARG GID=1000

# Copying poetry and venv into image
COPY --from=builder-base $POETRY_HOME $POETRY_HOME
COPY --from=builder-base $PYSETUP_PATH $PYSETUP_PATH

# venv already has runtime deps installed we get a quicker install
WORKDIR $PYSETUP_PATH
RUN poetry update && poetry install

WORKDIR $APP_PATH

COPY ./poetry.lock ./pyproject.toml ./

RUN addgroup --gid $GID $USER \
    && adduser --disabled-password --no-create-home --uid $UID --gid $GID $USER \
    && chown -R $UID:$GID $APP_PATH

USER $USER


# # 'lint' stage runs black and isort
# # running in check mode means build will fail if any linting errors occur
# FROM development AS lint
# RUN black --config ./pyproject.toml --check mysite
# RUN isort --settings-path ./pyproject.toml --recursive --check-only
# CMD ["sleep", "infinity"]
