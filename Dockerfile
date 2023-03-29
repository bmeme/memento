FROM debian:buster-slim

RUN apt update && \
    apt install -y lsb-release vim bash sudo perl-modules build-essential git liblwp-protocol-https-perl && \
    rm -rf /var/lib/apt/lists/*

RUN cpan CPAN
 
COPY ./ /opt/memento

RUN cd /opt/memento && ./install.pl

RUN groupadd --gid 1000 memento && \
    useradd \
      --uid 1000 \
      --gid 1000 \
      --groups sudo \
      --create-home \
      --shell /bin/bash \
      memento

RUN echo "memento\nmemento" | passwd memento

USER memento

