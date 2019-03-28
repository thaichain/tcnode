# ThaiChain Public Blockchain
#
FROM parity/parity:stable

WORKDIR /thaichain

ADD thaichain/ /thaichain/
#RUN chown 1000.1000 /thaichain/data
