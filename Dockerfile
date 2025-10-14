FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    # Build essentials
    build-essential \
    pkg-config \
    curl \
    xz-utils \
    # System libraries required by the project
    libminizip-dev \
    libexpat1-dev \
    libjemalloc-dev \
    doctest-dev \
    zlib1g-dev

# Install Zig 0.15.2
RUN curl -L https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz -o zig.tar.xz \
    && tar -xf zig.tar.xz \
    && mv zig-x86_64-linux-0.15.2 /opt/zig \
    && ln -s /opt/zig/zig /usr/local/bin/zig \
    && rm zig.tar.xz

# Set working directory
WORKDIR /app

# Copy source code
COPY . .

# Set up environment variables for the build
ENV FLAKE_INCLUDES="/usr/include/minizip:/usr/include:/usr/include/expat"

# Build the project
RUN zig build compile -Doptimize=ReleaseSmall

# Create a runtime stage for smaller final image
FROM debian:12-slim AS runtime

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    libminizip1 \
    libexpat1 \
    libjemalloc2 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Copy the built executables from the build stage
COPY --from=0 /app/zig-out/bin/excel2csv /usr/local/bin/excel2csv
COPY --from=0 /app/zig-out/bin/excel2csv_tests /usr/local/bin/excel2csv_tests

# Set working directory
WORKDIR /data

# Default command
ENTRYPOINT ["excel2csv"]
CMD ["--help"]