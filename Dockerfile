# Node.js v15.5.0 / Debian Buster (original environment)
FROM node:15.5.0-buster
 
WORKDIR /nodetaint
 
# Buster is end-of-life: point apt at the Debian archive
RUN sed -i 's|deb.debian.org|archive.debian.org|g; s|security.debian.org|archive.debian.org|g; /buster-updates/d' /etc/apt/sources.list \
 && echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid
 
# Essential packages + Python build deps
RUN apt-get -qq update && apt-get install -qqy \
    bash make vim git graphviz wget curl unzip build-essential \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev llvm \
    libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev python3-openssl \
 && rm -rf /var/lib/apt/lists/*
 
# z3 4.8.9
RUN wget -q https://github.com/Z3Prover/z3/releases/download/z3-4.8.9/z3-4.8.9-x64-ubuntu-16.04.zip \
 && unzip -q z3-4.8.9-x64-ubuntu-16.04.zip \
 && mv z3-4.8.9-x64-ubuntu-16.04 z3 \
 && rm z3-4.8.9-x64-ubuntu-16.04.zip
ENV PATH="/nodetaint/z3/bin:${PATH}"
 
# hyperfine 1.11.0
RUN wget -q https://github.com/sharkdp/hyperfine/releases/download/v1.11.0/hyperfine_1.11.0_amd64.deb \
 && dpkg -i hyperfine_1.11.0_amd64.deb \
 && rm hyperfine_1.11.0_amd64.deb
 
# Node tools (TypeScript pinned)
RUN npm i -g n typescript@5.4.5
 
# Python 3.11.4 via pyenv (git clone + PATH set before use)
ENV PYENV_ROOT=/root/.pyenv
ENV PATH="${PYENV_ROOT}/shims:${PYENV_ROOT}/bin:${PATH}"
ENV PYTHON_VERSION=3.11.4
RUN git clone --depth 1 https://github.com/pyenv/pyenv.git ${PYENV_ROOT} \
 && pyenv install ${PYTHON_VERSION} \
 && pyenv global ${PYTHON_VERSION} \
 && python --version \
 && echo 'eval "$(pyenv init -)"' >> /root/.bashrc
 
# Copy over files
COPY lib ./lib
COPY src ./src
COPY tests ./tests
COPY package*.json ./
COPY tsconfig.json .
COPY Makefile .
COPY pipeline ./pipeline
 
# Strip Windows line endings from shell scripts (safe on a Windows host)
RUN find . -name "*.sh" -not -path "*/node_modules/*" -exec sed -i 's/\r$//' {} +
 
# Dependencies (npm i, not npm ci, so a lockfile drift doesn't hard-fail the build)
RUN npm i
RUN cd pipeline && npm i
RUN chmod +x lib/setup-deps.sh && cd lib && ./setup-deps.sh
 
# Build analysis
RUN make clean && make
 
COPY entrypoint.sh ./entrypoint.sh
RUN sed -i 's/\r$//' entrypoint.sh && chmod +x entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]
 