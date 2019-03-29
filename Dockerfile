# ThaiChain Public Blockchain
#
FROM parity/parity:stable

WORKDIR /thaichain

USER root
ADD thaichain/ /thaichain/
RUN mkdir -p /thaichain/data
RUN chown 1000.1000 /thaichain/data

USER parity
