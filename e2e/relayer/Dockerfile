#---------------------------------------------------
FROM golang:1.21 as cache
ARG RELAYER_VERSION
ARG IBC_ETH_VERSION
ARG IBC_HD_SIGNER_VERSION
ARG RELAYER="github.com/hyperledger-labs/yui-relayer"
ARG IBC_ETH="github.com/datachainlab/ethereum-ibc-relay-chain"
ARG IBC_HD_SIGNER="github.com/datachainlab/ibc-hd-signer"

WORKDIR /root

ADD . relayer

WORKDIR /root/relayer

RUN RELAYER=${RELAYER} RELAYER_VERSION=${RELAYER_VERSION} \
    IBC_ETH=${IBC_ETH} IBC_ETH_VERSION=${IBC_ETH_VERSION} \
    IBC_HD_SIGNER=${IBC_HD_SIGNER} IBC_HD_SIGNER_VERSION=${IBC_HD_SIGNER_VERSION} \
    sh ./scripts/gen-gomod.sh go.mod.template > go.mod && \
    cat go.mod && \
    go mod tidy

#---------------------------------------------------
FROM cache as builder

# Enable a comment to change blocks_per_epoch.
# RUN go build -tags dev -ldflags="-X github.com/datachainlab/ibc-parlia-relay/module/constant.blocksPerEpoch=200" -o yrly .
RUN go build -o yrly .

#---------------------------------------------------
FROM ubuntu:22.04 as runner

RUN apt-get update && apt-get install -y jq gettext-base \
  && apt-get clean && rm -rf /var/libapt/lists/*

COPY --from=builder /root/relayer/yrly /usr/bin/yrly
COPY --from=builder /root/relayer/scripts /scripts

ENTRYPOINT ["yrly"]
