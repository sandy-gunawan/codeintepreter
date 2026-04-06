FROM python:3.11-slim

LABEL maintainer="code-interpreter-platform"
LABEL description="Sandboxed Python executor for untrusted code"

# Install system dependencies for matplotlib rendering
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Python data science packages
RUN pip install --no-cache-dir \
    pandas==2.2.3 \
    numpy==2.1.3 \
    matplotlib==3.9.3 \
    seaborn==0.13.2 \
    openpyxl==3.1.5 \
    azure-storage-blob==12.24.0 \
    scipy==1.14.1

# Use non-interactive backend for matplotlib
ENV MPLBACKEND=Agg

# Create working directory
WORKDIR /sandbox

# Copy executor script
COPY executor.py /sandbox/executor.py

# Create non-root user for execution
RUN useradd -m -s /bin/bash sandboxuser && \
    chown -R sandboxuser:sandboxuser /sandbox
USER sandboxuser

ENTRYPOINT ["python", "/sandbox/executor.py"]
