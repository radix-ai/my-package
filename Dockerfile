# syntax=docker/dockerfile:experimental
FROM python:3.8-slim AS base

# Configure Python to print tracebacks on crash [1], and to not buffer stdout and stderr [2].
# [1] https://docs.python.org/3/using/cmdline.html#envvar-PYTHONFAULTHANDLER
# [2] https://docs.python.org/3/using/cmdline.html#envvar-PYTHONUNBUFFERED
ENV PYTHONFAULTHANDLER 1
ENV PYTHONUNBUFFERED 1

# Install Poetry.
ENV POETRY_VERSION 1.1.13
RUN --mount=type=cache,id=poetry,target=/root/.cache/ pip install poetry==$POETRY_VERSION

# Create and activate a virtual environment.
RUN python -m venv /opt/app-env
ENV PATH /opt/app-env/bin:$PATH
ENV VIRTUAL_ENV /opt/app-env

# Set the working directory.
WORKDIR /app/

FROM base as deps

# Install compilers that may be required for certain packages or platforms.
RUN rm /etc/apt/apt.conf.d/docker-clean
RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt/ \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt/ \
    apt-get update && \
    apt-get install --no-install-recommends --yes build-essential

# Install the run time Python environment.
COPY poetry.lock* pyproject.toml /app/
RUN --mount=type=cache,id=poetry,target=/root/.cache/ \
    mkdir -p src/my_package/ && touch src/my_package/__init__.py && touch README.md && \
    poetry install --no-dev --no-interaction

FROM deps as ci

# Install git so we can run pre-commit.
RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt/ \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt/ \
    apt-get update && \
    apt-get install --no-install-recommends --yes git

# Install the development Python environment.
RUN --mount=type=cache,id=poetry,target=/root/.cache/ \
    poetry install --no-interaction

FROM ci as dev

# Install development tools: compilers, curl, git, gpg, ssh, starship, vim, and zsh.
RUN --mount=type=cache,id=apt-cache,target=/var/cache/apt/ \
    --mount=type=cache,id=apt-lib,target=/var/lib/apt/ \
    apt-get update && \
    apt-get install --no-install-recommends --yes build-essential curl git gnupg ssh vim zsh zsh-antigen && \
    chsh --shell /usr/bin/zsh && \
    sh -c "$(curl -fsSL https://starship.rs/install.sh)" -- "--yes" && \
    echo 'source /usr/share/zsh-antigen/antigen.zsh' >> ~/.zshrc && \
    echo 'antigen bundle zsh-users/zsh-syntax-highlighting' >> ~/.zshrc && \
    echo 'antigen bundle zsh-users/zsh-autosuggestions' >> ~/.zshrc && \
    echo 'antigen apply' >> ~/.zshrc && \
    echo 'eval "$(starship init zsh)"' >> ~/.zshrc && \
    echo 'HISTFILE=/opt/app-env/.zsh_history' >> ~/.zshrc && \
    zsh -c 'source ~/.zshrc'

# Persist output generated during docker build so that we can restore it in the dev container.
COPY .pre-commit-config.yaml /app/
RUN mkdir -p /var/lib/poetry/ && cp poetry.lock /var/lib/poetry/ && \
    git init && pre-commit install --install-hooks && \
    mkdir -p /var/lib/git/ && cp .git/hooks/commit-msg .git/hooks/pre-commit /var/lib/git/

FROM deps AS app

# Copy the package source code to the working directory.
COPY src/ *.py /app/

# Expose the application.
ENTRYPOINT ["/opt/app-env/bin/poe"]
CMD ["serve"]

# The following variables are supplied as build args at build time and made available at run time as
# environment variables.
ARG SOURCE_BRANCH
ENV SOURCE_BRANCH $SOURCE_BRANCH
ARG SOURCE_COMMIT
ENV SOURCE_COMMIT $SOURCE_COMMIT
ARG SOURCE_TIMESTAMP
ENV SOURCE_TIMESTAMP $SOURCE_TIMESTAMP
