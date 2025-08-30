# Docker support for testing dotfiles setup
# Based on Ubuntu LTS for consistency

FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Install basic packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    build-essential \
    sudo \
    locales \
    && locale-gen en_US.UTF-8 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create user (will be replaced by build arg)
ARG USERNAME=testuser
RUN useradd -m -s /bin/bash -G sudo "$USERNAME" \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to user
USER $USERNAME
WORKDIR /home/$USERNAME

# Set up basic shell environment
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Install chezmoi
RUN curl -sfL https://get.chezmoi.io | sh -s -- -b "$HOME/.local/bin"

# Copy dotfiles (will be mounted as volume)
COPY --chown=$USERNAME:$USERNAME . /home/$USERNAME/.local/share/chezmoi

# Default command
CMD ["/bin/bash", "--login"]