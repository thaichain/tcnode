# ThaiChain Public Blockchain
#
FROM parity/parity:stable

WORKDIR /thaichain

ADD thaichain/ /thaichain/
RUN mkdir -p /thaichain/data
